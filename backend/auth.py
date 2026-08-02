"""Auth: password hashing, sessions, API tokens, admin gating, Roblox OAuth."""
import os
import time
import uuid
import hashlib
import secrets
import urllib.parse
import httpx

import db

OWNER_EMAIL = os.environ.get("AGILESTUDIO_OWNER_EMAIL", "").lower()
ADMIN_API_KEY = os.environ.get("AGILESTUDIO_ADMIN_API_KEY", "")
SESSION_TTL = 60 * 60 * 24 * 7  # 7 days
APIKEY_PREFIX = "agst_"


def hash_password(pw: str) -> str:
    salt = secrets.token_hex(16)
    return "sha256$" + salt + "$" + hashlib.sha256((salt + pw).encode()).hexdigest()


def verify_password(pw: str, stored: str) -> bool:
    if not stored or "$" not in stored:
        return False
    _, salt, h = stored.split("$", 2)
    return h == hashlib.sha256((salt + pw).encode()).hexdigest()


def create_user(email, name, password=None, roblox_id=None, roblox_username=None):
    uid = uuid.uuid4().hex
    is_admin = 0
    # first user or the configured owner becomes admin automatically
    if (OWNER_EMAIL and email and email.lower() == OWNER_EMAIL) or db.q("SELECT COUNT(*) AS c FROM users")[0]["c"] == 0:
        is_admin = 1
    db.execute(
        "INSERT INTO users (id,email,name,password_hash,roblox_id,roblox_username,is_admin,created_at) VALUES (?,?,?,?,?,?,?,?)",
        (uid, email, name, hash_password(password) if password else None, roblox_id, roblox_username, is_admin, int(time.time())),
    )
    # default quota
    db.execute("INSERT OR IGNORE INTO quotas (user_id,daily_requests,daily_cost) VALUES (?,?,?)", (uid, 1000, 1.0))
    return uid


def authenticate(email, password):
    rows = db.q("SELECT * FROM users WHERE email=?", (email.lower(),))
    if not rows:
        return None
    u = rows[0]
    if not u["password_hash"] or not verify_password(password, u["password_hash"]):
        return None
    return u


def create_session(user_id):
    token = secrets.token_urlsafe(32)
    now = int(time.time())
    db.execute("INSERT INTO sessions (token,user_id,created_at,expires_at) VALUES (?,?,?,?)",
               (token, user_id, now, now + SESSION_TTL))
    return token


def get_user_from_session(token):
    if not token:
        return None
    rows = db.q("SELECT * FROM sessions WHERE token=?", (token,))
    if not rows:
        return None
    s = rows[0]
    if s["expires_at"] < int(time.time()):
        return None
    u = db.q("SELECT * FROM users WHERE id=?", (s["user_id"],))
    return u[0] if u else None


def is_admin_user(user) -> bool:
    if not user:
        return False
    if isinstance(user, dict):
        if ADMIN_API_KEY and user.get("id") == "__admin_key__":
            return True
        return bool(user.get("is_admin"))
    # sqlite3.Row or similar mapping interface
    try:
        if ADMIN_API_KEY and user["id"] == "__admin_key__":
            return True
        return bool(user["is_admin"])
    except Exception:
        return False


def create_api_token(user_id, name, scopes):
    raw = APIKEY_PREFIX + secrets.token_urlsafe(28)
    tid = uuid.uuid4().hex
    db.execute("INSERT INTO apitokens (id,user_id,name,token,scopes,created_at) VALUES (?,?,?,?,?,?)",
               (tid, user_id, name, raw, scopes, int(time.time())))
    return raw, tid


def get_token_record(raw):
    rows = db.q("SELECT * FROM apitokens WHERE token=? AND revoked=0", (raw,))
    return rows[0] if rows else None


def admin_via_apikey(key):
    if ADMIN_API_KEY and key and key == ADMIN_API_KEY:
        return {"id": "__admin_key__", "email": "admin@apikey", "is_admin": 1, "name": "Admin"}
    return None


# ---- Roblox OAuth ----
ROBLOX_CLIENT_ID = os.environ.get("ROBLOX_OAUTH_CLIENT_ID", "")
ROBLOX_CLIENT_SECRET = os.environ.get("ROBLOX_OAUTH_CLIENT_SECRET", "")
ROBLOX_REDIRECT = os.environ.get("ROBLOX_OAUTH_REDIRECT", "http://127.0.0.1:8056/auth/roblox/callback")


def roblox_authorize_url(state, redirect_after="/dashboard"):
    db.execute("INSERT OR REPLACE INTO oauth_state (state,redirect_after,created_at) VALUES (?,?,?)",
               (state, redirect_after, int(time.time())))
    params = {
        "client_id": ROBLOX_CLIENT_ID,
        "redirect_uri": ROBLOX_REDIRECT,
        "response_type": "code",
        "scope": "openid profile",
        "state": state,
        "prompt": "consent",
    }
    return "https://apis.roblox.com/oauth/v1/authorize?" + urllib.parse.urlencode(params)


def roblox_exchange(code):
    resp = httpx.post("https://apis.roblox.com/oauth/v1/token", data={
        "client_id": ROBLOX_CLIENT_ID,
        "client_secret": ROBLOX_CLIENT_SECRET,
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": ROBLOX_REDIRECT,
    }, timeout=20)
    if resp.status_code != 200:
        return None
    return resp.json()


def roblox_userinfo(access_token):
    resp = httpx.get("https://apis.roblox.com/oauth/v1/userinfo",
                     headers={"Authorization": f"Bearer {access_token}"}, timeout=20)
    if resp.status_code != 200:
        return None
    return resp.json()
