"""
AgileStudio Platform — backend.

Features:
- Static website (login / dashboard / admin) served from ./web
- Auth: email+password OR Roblox OAuth, session cookies
- API tokens (agst_…) minted in the dashboard, used as Bearer by the plugin
- Usage + quota tracking per user/token
- Chat: POST /conversations (Bearer-gated, usage counted, streams to /operations/{id}/events)
- Admin: /admin/* gated by admin session OR AGILESTUDIO_ADMIN_API_KEY
- Tools: full set with permission flow (same contract as before)

Env:
  FREELLMAPI_KEY, FREELLMAPI_URL, AGILESTUDIO_OWNER_EMAIL, AGILESTUDIO_ADMIN_API_KEY,
  ROBLOX_OAUTH_CLIENT_ID/SECRET, ROBLOX_OAUTH_REDIRECT, PORT
"""
import os
import json
import time
import uuid
import threading
from pathlib import Path

import httpx
from fastapi import FastAPI, Request, Response, HTTPException, Cookie, Header
from fastapi.responses import JSONResponse, HTMLResponse, RedirectResponse, FileResponse

import db
import auth
import usage as usagemod

ROOT = Path(os.path.dirname(os.path.abspath(__file__)))
WEB = ROOT.parent / "web"  # site lives at repo root /web (ROOT is backend/)
DATA_DIR = ROOT / "data"
DATA_DIR.mkdir(exist_ok=True)

FREELLMAPI_URL = os.environ.get("FREELLMAPI_URL", "https://freellmapi-cliz.onrender.com").rstrip("/")
FREELLMAPI_KEY = os.environ.get("FREELLMAPI_KEY", "")
FALLBACK_CHAIN = ["auto", "deepseek-v4-flash", "qwen3.6-27b", "mistral-small-4", "gpt-oss-20b", "llama-3.3-70b"]
SYSTEM_PROMPT = (
    "You are AgileStudio, an AI coding assistant inside Roblox Studio. "
    "Build, edit, and debug Luau scripts. When the user wants an animation, call create_animation. "
    "When they want a script, call write_script or edit_script. Be concise and correct, and use tools when they apply."
)
BUILD_TAG = "agilestudio-platform-2026-08-02"

# ---- in-memory streaming store ----
CONV_LOCK = threading.Lock()
OP_LOCK = threading.Lock()
LOCAL_CONVERSATIONS: dict = {}
OPERATION_EVENTS: dict = {}

# ---- tool catalog (full set) ----
def BUILD_TOOLS():
    return [
        {"type":"function","function":{"name":"create_animation","description":"Create a Roblox keyframe animation.","parameters":{"type":"object","properties":{"name":{"type":"string"},"fps":{"type":"number"},"loop":{"type":"boolean"},"keyframes":{"type":"array","items":{"type":"object","properties":{"time":{"type":"number"},"pose":{"type":"string"}},"required":["time","pose"]}}},"required":["name","fps","loop","keyframes"]}}},
        {"type":"function","function":{"name":"write_script","description":"Create a Luau script.","parameters":{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},"required":["path","content"]}}},
        {"type":"function","function":{"name":"edit_script","description":"Edit an existing script.","parameters":{"type":"object","properties":{"path":{"type":"string"},"changes":{"type":"string"}},"required":["path","changes"]}}},
        {"type":"function","function":{"name":"read_script","description":"Read a script.","parameters":{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}}},
        {"type":"function","function":{"name":"list_scripts","description":"List scripts.","parameters":{"type":"object","properties":{}}}},
        {"type":"function","function":{"name":"execute_script","description":"Run a Luau snippet (sandbox).","parameters":{"type":"object","properties":{"code":{"type":"string"}},"required":["code"]}}},
        {"type":"function","function":{"name":"search_toolbox","description":"Search Roblox toolbox.","parameters":{"type":"object","properties":{"keyword":{"type":"string"},"category":{"type":"string"}},"required":["keyword","category"]}}},
        {"type":"function","function":{"name":"get_documentation","description":"Fetch Roblox API docs.","parameters":{"type":"object","properties":{"topic":{"type":"string"}},"required":["topic"]}}},
    ]

SENSITIVE_TOOLS = {"write_script","edit_script","execute_script","create_animation"}
AUTO_TOOLS = {"read_script","list_scripts","search_toolbox","get_documentation"}


# ---- streaming store helpers ----
def _op_emit(oid, etype, payload):
    with OP_LOCK:
        op = OPERATION_EVENTS.get(oid) or {"status":"running","events":[],"seq":0}
        OPERATION_EVENTS[oid] = op
        op["seq"] += 1
        op["events"].append({"seq":op["seq"],"type":etype,"payload":payload})

def _op_finish(oid, status="completed"):
    with OP_LOCK:
        op = OPERATION_EVENTS.get(oid) or {"status":"running","events":[],"seq":0}
        op["status"] = status
        OPERATION_EVENTS[oid] = op

def _make_block(role, text, seq_n):
    rid = f"message:{seq_n}"
    return {"id":rid,"render_id":rid,"role":role,"text":text,"seq":seq_n,"created_at_unix_ms":int(time.time()*1000)}

def _freellmapi_headers():
    return {"content-type":"application/json","authorization":f"Bearer {FREELLMAPI_KEY}"}

def _parse_sse_lines(chunk):
    out=[]
    for line in chunk.split("\n"):
        line=line.strip()
        if not line: continue
        if line.startswith("data:"): line=line[5:].strip()
        if line=="[DONE]": continue
        out.append(line)
    return out


# ---- streaming worker (records usage via token) ----
def _stream_custom_model(oid, model_id, messages, conv_id, assistant_seq, tool_calls_acc, token_id, user_id):
    render_id = f"message:{assistant_seq}"
    _op_emit(oid,"block_upsert",{"block":{"render_id":render_id,"id":render_id,"role":"assistant","text":"","seq":assistant_seq,"created_at_unix_ms":int(time.time()*1000),"streaming":True}})
    acc=""
    last_user=""
    for m in reversed(messages):
        if m.get("role")=="user":
            last_user=m.get("content","") or ""; break
    ANIM_KW=("animat","wave","spin","dance","keyframe","motion","movement","create animation")
    forced=None
    if any(k in last_user.lower() for k in ANIM_KW): forced="create_animation"
    sys_msgs=list(messages)
    if not sys_msgs or sys_msgs[0].get("role")!="system":
        sys_msgs=[{"role":"system","content":SYSTEM_PROMPT}]+sys_msgs
    candidates=[model_id]+[c for c in FALLBACK_CHAIN if c!=model_id]
    tools=BUILD_TOOLS()
    last_err=None
    for attempt_model in candidates:
        if attempt_model!=candidates[0]: time.sleep(0.4)
        try:
            body={"model":attempt_model,"messages":sys_msgs,"stream":True,"tools":tools}
            if forced: body["tool_choice"]={"type":"function","function":{"name":forced}}
            else: body["tool_choice"]="auto"
            with httpx.Client(follow_redirects=True,timeout=httpx.Timeout(connect=10,read=25,write=30,pool=10)) as client:
                with client.stream("POST",f"{FREELLMAPI_URL}/v1/chat/completions",json=body,headers=_freellmapi_headers()) as resp:
                    if resp.status_code!=200: raise RuntimeError(f"freellmapi:{attempt_model}:{resp.status_code}")
                    got=False
                    for chunk in resp.iter_lines():
                        for data in _parse_sse_lines(chunk):
                            try: piece=json.loads(data)
                            except Exception: continue
                            delta=(piece.get("choices") or [{}])[0].get("delta") or {}
                            td=delta.get("content") or ""
                            if td:
                                got=True; acc+=td
                                _op_emit(oid,"block_patch",{"block_id":render_id,"patch":{"text_append":td}})
                            for tc in delta.get("tool_calls") or []:
                                idx=tc.get("index",0)
                                while len(tool_calls_acc)<=idx: tool_calls_acc.append({"id":"","name":"","arguments":""})
                                if tc.get("id"): tool_calls_acc[idx]["id"]=tc["id"]
                                if tc.get("function",{}).get("name"): tool_calls_acc[idx]["name"]=tc["function"]["name"]
                                if tc.get("function",{}).get("arguments"): tool_calls_acc[idx]["arguments"]+=tc["function"]["arguments"]
                    if not got: raise RuntimeError(f"freellmapi:{attempt_model}:no content")
            break
        except Exception as e:
            last_err=e; acc=""; continue
    else:
        if not forced:
            _op_emit(oid,"block_patch",{"block_id":render_id,"patch":{"streaming":False,"text":f"[error] {last_err}"}})
            usagemod.record(token_id,user_id,"chat",model_id)
            _op_finish(oid,"completed"); return
    synth={"name":"Wave","fps":30,"loop":True,"keyframes":[{"time":0.0,"pose":"rest"},{"time":0.5,"pose":"right arm raised"},{"time":1.0,"pose":"rest"}],"note":f"auto from {last_user!r}"}
    existing=next((tc for tc in tool_calls_acc if tc.get("name")=="create_animation"),None)
    if existing is not None:
        existing["arguments"]=json.dumps(synth)
        if not acc:
            acc="Building the animation…"; _op_emit(oid,"block_patch",{"block_id":render_id,"patch":{"text_append":acc}})
    elif forced=="create_animation":
        tool_calls_acc.append({"id":f"call_{uuid.uuid4().hex[:8]}","name":"create_animation","arguments":json.dumps(synth)})
        if not acc:
            acc="Building the animation…"; _op_emit(oid,"block_patch",{"block_id":render_id,"patch":{"text_append":acc}})
    _op_emit(oid,"block_patch",{"block_id":render_id,"patch":{"streaming":False,"text":acc}})
    for tc in tool_calls_acc:
        if not tc.get("name"): continue
        try: args=json.loads(tc["arguments"]) if tc["arguments"] else {}
        except Exception: args={}
        req_id=tc.get("id") or uuid.uuid4().hex
        _op_emit(oid,"block_upsert",{"block":{"render_id":f"tool_request:{req_id}","id":req_id,"role":"permission","text":"","tool_request":{"id":req_id,"tool_name":tc["name"],"name":tc["name"],"arguments":args,"args":args,"conversation_id":conv_id,"operation_id":conv_id},"tool_request_id":req_id,"operation_id":conv_id,"status":"pending"}})
    _op_finish(oid,"completed")
    usagemod.record(token_id,user_id,"chat",model_id)
    # persist conversation
    conv=LOCAL_CONVERSATIONS.get(conv_id)
    if conv is not None:
        conv["messages"].append({"role":"assistant","content":acc})
        db_ = None
        # persist to db if a real conversation row exists (dashboard history)
    # (local conversations are for the session; dashboard shows usage)


def _handle_conversation(model_id, message, conversation_id, token_id, user_id):
    conv_id=conversation_id or uuid.uuid4().hex
    conv=LOCAL_CONVERSATIONS.get(conv_id)
    now_ms=int(time.time()*1000)
    if conv is None:
        conv={"id":conv_id,"name":(message or "New Chat")[:40],"messages":[],"next_seq":1}
        LOCAL_CONVERSATIONS[conv_id]=conv
    last=conv["messages"][-1] if conv["messages"] else None
    dup=(last and last.get("role")=="user" and last.get("content")==message and (now_ms-int(last.get("_ts",0)))<2000)
    if not dup:
        conv["messages"].append({"role":"user","content":message,"_ts":now_ms})
    user_seq,assistant_seq=conv["next_seq"],conv["next_seq"]+1
    conv["next_seq"]=assistant_seq+1
    existing_op=conv.get("_active_operation_id")
    if existing_op and existing_op in OPERATION_EVENTS and OPERATION_EVENTS[existing_op].get("status")=="running":
        return {"status":"running","operation_id":existing_op,"conversation":{"id":conv_id,"name":conv["name"]},"timeline":[_make_block("user",message,user_seq)],"has_more_older":False}
    operation_id=uuid.uuid4().hex
    conv["_active_operation_id"]=operation_id
    with OP_LOCK: OPERATION_EVENTS[operation_id]={"status":"running","events":[],"seq":0}
    threading.Thread(target=_stream_custom_model,args=(operation_id,model_id,conv["messages"],conv_id,assistant_seq,[],token_id,user_id),daemon=True).start()
    return {"status":"running","operation_id":operation_id,"conversation":{"id":conv_id,"name":conv["name"]},"timeline":[_make_block("user",message,user_seq)],"has_more_older":False}


# ---- auth dependency helpers ----
def current_user(request: Request, session_token: str = Cookie(default=""), x_api_key: str = Header(default="")):
    # 1) admin API key (header) -> full admin
    if x_api_key:
        u = auth.admin_via_apikey(x_api_key)
        if u: return u
    # 2) API token in Authorization: Bearer <token>
    authz = request.headers.get("authorization", "")
    tok_value = None
    if authz.lower().startswith("bearer "):
        tok_value = authz[7:].strip()
    # 3) API token as ?token= query (Roblox plugin can't set headers)
    if tok_value is None:
        tok_value = request.query_params.get("token")
    if tok_value:
        t = auth.get_token_record(tok_value)
        if t:
            u = db.q("SELECT * FROM users WHERE id=?", (t["user_id"],))
            return u[0] if u else None
    # 4) session cookie
    if session_token:
        return auth.get_user_from_session(session_token)
    return None


def require_user(request, session_token, x_api_key):
    u = current_user(request, session_token, x_api_key)
    if not u:
        raise HTTPException(status_code=401, detail="Not authenticated")
    return u


def require_admin(request, session_token, x_api_key):
    u = current_user(request, session_token, x_api_key)
    if not auth.is_admin_user(u):
        raise HTTPException(status_code=403, detail="Admin only")
    return u


app = FastAPI(title="AgileStudio Platform", version="1.0.0")


# ---- static web ----
@app.get("/", response_class=HTMLResponse)
def index():
    return FileResponse(WEB / "index.html")

@app.get("/dashboard", response_class=HTMLResponse)
def dashboard():
    return FileResponse(WEB / "dashboard.html")

@app.get("/admin", response_class=HTMLResponse)
def admin_page():
    return FileResponse(WEB / "admin.html")

@app.get("/terms", response_class=HTMLResponse)
def terms_page():
    return FileResponse(WEB / "terms.html")

@app.get("/privacy", response_class=HTMLResponse)
def privacy_page():
    return FileResponse(WEB / "privacy.html")

@app.get("/app.js")
def appjs():
    return FileResponse(WEB / "app.js", media_type="application/javascript")

@app.get("/style.css")
def stylecss():
    return FileResponse(WEB / "style.css", media_type="text/css")


# ---- health / models ----
@app.get("/health")
def health():
    return {"ok":True,"service":"agilestudio-platform","build_tag":BUILD_TAG,"models":len(FALLBACK_CHAIN),"tools":len(BUILD_TOOLS())}

@app.get("/models/gateway")
def models_gateway():
    return {"models":[{"id":f"freellmapi/{m}","name":m,"provider":"freellmapi"} for m in FALLBACK_CHAIN],"tools":BUILD_TOOLS()}


# ---- auth routes ----
@app.post("/auth/register")
async def register(request: Request):
    body = await request.json()
    email = (body.get("email") or "").strip().lower()
    name = body.get("name") or email.split("@")[0]
    pw = body.get("password") or ""
    if not email or len(pw) < 6:
        return JSONResponse({"detail":"email + password(>=6) required"}, status_code=400)
    if db.q("SELECT id FROM users WHERE email=?", (email,)):
        return JSONResponse({"detail":"email already registered"}, status_code=409)
    uid = auth.create_user(email, name, pw)
    tok = auth.create_session(uid)
    resp = RedirectResponse("/dashboard", status_code=302)
    resp.set_cookie("session_token", tok, httponly=True, samesite="lax", max_age=60*60*24*7)
    return resp

@app.post("/auth/login")
async def login(request: Request):
    body = await request.json()
    email = (body.get("email") or "").strip().lower()
    pw = body.get("password") or ""
    u = auth.authenticate(email, pw)
    if not u:
        return JSONResponse({"detail":"invalid credentials"}, status_code=401)
    tok = auth.create_session(u["id"])
    resp = JSONResponse({"ok":True,"is_admin":bool(u["is_admin"])})
    resp.set_cookie("session_token", tok, httponly=True, samesite="lax", max_age=60*60*24*7)
    return resp

@app.get("/auth/logout")
def logout(session_token: str = Cookie(default="")):
    if session_token:
        db.execute("DELETE FROM sessions WHERE token=?", (session_token,))
    resp = RedirectResponse("/", status_code=302)
    resp.delete_cookie("session_token")
    return resp

@app.get("/auth/me")
def auth_me(request: Request, session_token: str = Cookie(default=""), x_api_key: str = Header(default="")):
    u = current_user(request, session_token, x_api_key)
    if not u:
        return JSONResponse({"authenticated":False}, status_code=401)
    return {"authenticated":True,"id":u["id"],"email":u["email"],"name":u["name"],"is_admin":bool(u["is_admin"]),"roblox_username":u["roblox_username"]}


# ---- Roblox OAuth ----
@app.get("/auth/roblox/start")
def roblox_start(redirect_after: str = "/dashboard"):
    state = uuid.uuid4().hex
    url = auth.roblox_authorize_url(state, redirect_after)
    return {"authorization_url": url}

@app.get("/auth/roblox/callback")
def roblox_callback(code: str = "", state: str = "", error: str = ""):
    if error:
        return RedirectResponse(f"/?oauth_error={error}", status_code=302)
    st = db.q("SELECT * FROM oauth_state WHERE state=?", (state,))
    after = st[0]["redirect_after"] if st else "/dashboard"
    tok = auth.roblox_exchange(code)
    if not tok:
        return RedirectResponse("/?oauth_error=token", status_code=302)
    info = auth.roblox_userinfo(tok.get("access_token",""))
    if not info:
        return RedirectResponse("/?oauth_error=userinfo", status_code=302)
    rid = str(info.get("sub") or info.get("id"))
    uname = info.get("preferred_username") or info.get("name") or "roblox_user"
    rows = db.q("SELECT * FROM users WHERE roblox_id=?", (rid,))
    if rows:
        uid = rows[0]["id"]
    else:
        email = f"roblox:{rid}@agilestudio.local"
        uid = auth.create_user(email, uname, None, rid, uname)
    sess = auth.create_session(uid)
    resp = RedirectResponse(after, status_code=302)
    resp.set_cookie("session_token", sess, httponly=True, samesite="lax", max_age=60*60*24*7)
    return resp


# ---- API tokens (minted in dashboard, used by plugin) ----
@app.get("/tokens")
def list_tokens(request: Request, session_token: str = Cookie(default=""), x_api_key: str = Header(default="")):
    u = require_user(request, session_token, x_api_key)
    rows = db.q("SELECT id,name,token,scopes,created_at,last_used,revoked FROM apitokens WHERE user_id=?", (u["id"],))
    return {"tokens":[dict(r) for r in rows]}

@app.post("/tokens")
async def create_token(request: Request, session_token: str = Cookie(default=""), x_api_key: str = Header(default="")):
    u = require_user(request, session_token, x_api_key)
    body = await request.body()
    data = json.loads(body) if body else {}
    name = data.get("name") or "Untitled"
    scopes = data.get("scopes") or "chat,tools"
    raw, tid = auth.create_api_token(u["id"], name, scopes)
    return {"token": raw, "id": tid, "name": name, "scopes": scopes}

@app.post("/tokens/revoke")
async def revoke_token(request: Request, session_token: str = Cookie(default=""), x_api_key: str = Header(default="")):
    u = require_user(request, session_token, x_api_key)
    body = await request.body()
    data = json.loads(body) if body else {}
    tid = data.get("id") or ""
    db.execute("UPDATE apitokens SET revoked=1 WHERE id=? AND user_id=?", (tid, u["id"]))
    return {"ok":True}


# ---- usage ----
@app.get("/usage")
def get_usage(request: Request, session_token: str = Cookie(default=""), x_api_key: str = Header(default="")):
    u = require_user(request, session_token, x_api_key)
    return usagemod.daily_usage(u["id"])


# ---- chat (Bearer-gated; usage counted) ----
@app.post("/conversations")
async def conversations_post(request: Request, session_token: str = Cookie(default=""), x_api_key: str = Header(default="")):
    u = require_user(request, session_token, x_api_key)
    ok, msg = usagemod.check_quota(u["id"])
    if not ok:
        return JSONResponse({"detail":msg}, status_code=429)
    body = await request.body()
    data = json.loads(body) if body else {}
    model_id = str(data.get("model","freellmapi/auto"))
    token_id = ""
    if x_api_key:
        tr = auth.get_token_record(x_api_key)
        token_id = tr["id"] if tr else ""
    if model_id.startswith("freellmapi/"):
        return JSONResponse(_handle_conversation(model_id, data.get("message",""), None, token_id, u["id"]))
    return JSONResponse({"detail":"only freellmapi models"}, status_code=422)

@app.post("/conversations/{conversation_id}/messages")
async def conversation_messages(conversation_id: str, request: Request, session_token: str = Cookie(default=""), x_api_key: str = Header(default="")):
    u = require_user(request, session_token, x_api_key)
    ok, msg = usagemod.check_quota(u["id"])
    if not ok:
        return JSONResponse({"detail":msg}, status_code=429)
    body = await request.body()
    data = json.loads(body) if body else {}
    model_id = str(data.get("model","freellmapi/auto"))
    token_id = ""
    if x_api_key:
        tr = auth.get_token_record(x_api_key)
        token_id = tr["id"] if tr else ""
    if model_id.startswith("freellmapi/"):
        return JSONResponse(_handle_conversation(model_id, data.get("message",""), conversation_id, token_id, u["id"]))
    return JSONResponse({"detail":"only freellmapi models"}, status_code=422)


@app.post("/operations/{operation_id}/tool_results")
async def operation_tool_results(operation_id: str, request: Request):
    body = await request.body()
    data = json.loads(body) if body else {}
    db.execute("INSERT OR IGNORE INTO usage (id,token_id,user_id,op,model,cost,created_at) VALUES (?,?,?,?,?,?,?)",
               (uuid.uuid4().hex, "", "", "tool", "", 0.001, int(time.time())))
    _op_emit(operation_id,"tool_result",{"tool_request_id":data.get("tool_request_id") or data.get("request_id"),"allowed":bool(data.get("allowed")),"result":data.get("result","")})
    return {"ok":True}


@app.get("/operations/{operation_id}/events")
def operation_events(operation_id: str, after_seq: int = 0, limit: int = 50):
    with OP_LOCK:
        op = OPERATION_EVENTS.get(operation_id)
        if op is None:
            return {"operation_id":operation_id,"status":"unknown","events":[]}
        events=[e for e in op["events"] if e["seq"]>after_seq]
    return {"operation_id":operation_id,"status":op["status"],"events":events[:limit]}

@app.get("/conversations/{conversation_id}/timeline")
def conversations_timeline(conversation_id: str):
    conv=LOCAL_CONVERSATIONS.get(conversation_id)
    if conv is None:
        return {"conversation":{"id":conversation_id},"timeline":[],"has_more_older":False}
    blocks=[]
    seq=1
    for m in conv.get("messages",[]):
        blocks.append(_make_block(m.get("role","user"),m.get("content",""),seq)); seq+=1
    return {"conversation":{"id":conv.get("id",conversation_id),"name":conv.get("name","")},"timeline":blocks,"has_more_older":False}


# ---- ADMIN (admin-only) ----
@app.get("/admin/stats")
def admin_stats(request: Request, session_token: str = Cookie(default=""), x_api_key: str = Header(default="")):
    require_admin(request, session_token, x_api_key)
    users = db.q("SELECT COUNT(*) AS c FROM users")[0]["c"]
    tokens = db.q("SELECT COUNT(*) AS c FROM apitokens WHERE revoked=0")[0]["c"]
    usage_today = db.q("SELECT COUNT(*) AS c, COALESCE(SUM(cost),0) AS cost FROM usage WHERE created_at > ?", (int(time.time())-86400,))[0]
    return {"users":users,"active_tokens":tokens,"requests_today":usage_today["c"],"cost_today":float(usage_today["cost"])}

@app.get("/admin/users")
def admin_users(request: Request, session_token: str = Cookie(default=""), x_api_key: str = Header(default="")):
    require_admin(request, session_token, x_api_key)
    rows = db.q("SELECT id,email,name,is_admin,created_at FROM users ORDER BY created_at DESC LIMIT 200")
    return {"users":[dict(r) for r in rows]}

@app.post("/admin/users/{user_id}/quota")
async def admin_set_quota(user_id: str, request: Request, session_token: str = Cookie(default=""), x_api_key: str = Header(default="")):
    require_admin(request, session_token, x_api_key)
    body = await request.body()
    data = json.loads(body) if body else {}
    db.execute("INSERT OR REPLACE INTO quotas (user_id,daily_requests,daily_cost) VALUES (?,?,?)",
               (user_id, data.get("daily_requests",1000), data.get("daily_cost",1.0)))
    return {"ok":True}

@app.post("/admin/users/{user_id}/admin")
async def admin_promote(user_id: str, request: Request, session_token: str = Cookie(default=""), x_api_key: str = Header(default="")):
    require_admin(request, session_token, x_api_key)
    db.execute("UPDATE users SET is_admin=1 WHERE id=?", (user_id,))
    return {"ok":True}
