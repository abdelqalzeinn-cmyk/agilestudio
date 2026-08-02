// AgileStudio site — talks to the SEPARATE API service (API_BASE).
// The API and this site are different origins; auth travels as ?session=<token>.
const API_BASE = (location.hostname === "localhost" || location.hostname === "127.0.0.1")
  ? "http://127.0.0.1:8080"          // local API (set to your API port)
  : "https://agilestudio-api.onrender.com"; // <-- your deployed API URL

const $ = (s) => document.querySelector(s);

// session token lives in localStorage (set from ?session= after OAuth, or login response)
function getSession() { return localStorage.getItem("as_session") || ""; }
function setSession(t) { if (t) localStorage.setItem("as_session", t); else localStorage.removeItem("as_session"); }

// capture ?session= from OAuth redirect, then strip it from the URL
(function captureSession() {
  const p = new URLSearchParams(location.search);
  const s = p.get("session");
  if (s) { setSession(s); history.replaceState(null, "", location.pathname); }
})();

// API helper: always appends ?session= (and token via header for Bearer users)
async function api(method, path, body) {
  const url = API_BASE + path + (path.includes("?") ? "&" : "?") + "session=" + encodeURIComponent(getSession());
  const opts = { method, headers: { "Content-Type": "application/json" } };
  if (body) opts.body = JSON.stringify(body);
  const r = await fetch(url, opts);
  if (r.status === 401 && path !== "/auth/me") { setSession(""); location.href = "/"; throw new Error("auth"); }
  let data = null; try { data = await r.json(); } catch (e) {}
  // if login/register returned a session_token, store it
  if (data && data.session_token) setSession(data.session_token);
  return { status: r.status, data };
}
const toast = (m) => { const t = $("#toast"); if (!t) return; t.textContent = m; t.classList.remove("hidden"); setTimeout(() => t.classList.add("hidden"), 2600); };

// ---------- index: login / register / oauth ----------
const loginForm = $("#loginForm"), registerForm = $("#registerForm");
if (loginForm) {
  $("#toRegister").onclick = (e) => { e.preventDefault(); loginForm.classList.add("hidden"); registerForm.classList.remove("hidden"); };
  $("#toLogin").onclick = (e) => { e.preventDefault(); registerForm.classList.add("hidden"); loginForm.classList.remove("hidden"); };
  loginForm.onsubmit = async (e) => {
    e.preventDefault();
    const r = await api("POST", "/auth/login", { email: $("#email").value, password: $("#password").value });
    if (r.status === 200 && r.data?.session_token) location.href = "/dashboard";
    else $("#loginErr").textContent = r.data?.detail || "Login failed";
  };
  registerForm.onsubmit = async (e) => {
    e.preventDefault();
    const r = await api("POST", "/auth/register", { email: $("#regEmail").value, name: $("#regName").value, password: $("#regPassword").value });
    if (r.status === 200 && r.data?.session_token) location.href = "/dashboard";
    else $("#regErr").textContent = r.data?.detail || "Register failed";
  };
  // Roblox OAuth: ask the API for the authorize URL, then go there
  $("#robloxBtn").onclick = async () => {
    const r = await api("GET", "/auth/roblox/start?redirect_after=/dashboard");
    if (r.data?.authorization_url) location.href = r.data.authorization_url;
  };
}

// ---------- dashboard ----------
if ($("#createToken")) {
  const loadUsage = async () => {
    const r = await api("GET", "/usage");
    $("#usageBox").textContent = `Requests: ${r.data?.requests ?? 0} · Cost: $${(r.data?.cost ?? 0).toFixed(4)} (last 24h)`;
  };
  const loadTokens = async () => {
    const r = await api("GET", "/tokens");
    const list = $("#tokenList"); list.innerHTML = "";
    (r.data?.tokens || []).forEach((t) => {
      const el = document.createElement("div"); el.className = "token-row";
      el.innerHTML = `<div><b>${t.name}</b> <span class="muted">${t.scopes}</span></div>
        <div class="muted mono">${t.revoked ? "REVOKED" : (t.token.slice(0, 12) + "…")}</div>
        ${t.revoked ? "" : `<button data-id="${t.id}">Revoke</button>`}`;
      const btn = el.querySelector("button");
      if (btn) btn.onclick = async () => { await api("POST", "/tokens/revoke", { id: t.id }); loadTokens(); };
      list.appendChild(el);
    });
  };
  $("#createToken").onclick = async () => {
    const name = $("#tokenName").value || "Token";
    const scopes = $("#tokenScopes").value;
    const r = await api("POST", "/tokens", { name, scopes });
    if (r.data?.token) {
      const box = $("#newToken");
      box.classList.remove("hidden");
      box.innerHTML = `Copy your token (shown once):<br><code>${r.data.token}</code><br>
        <button id="copyTok">Copy</button>`;
      $("#copyTok").onclick = () => { navigator.clipboard.writeText(r.data.token); toast("Copied"); };
      loadTokens();
    }
  };
  loadUsage(); loadTokens();
  (async () => {
    const me = await api("GET", "/auth/me");
    if (me.data?.is_admin) $("#adminLinkWrap").classList.remove("hidden");
  })();
}

// ---------- admin ----------
if ($("#statsBox")) {
  const load = async () => {
    const s = await api("GET", "/admin/stats");
    $("#statsBox").innerHTML = `Users: <b>${s.data?.users ?? 0}</b> · Active tokens: <b>${s.data?.active_tokens ?? 0}</b> · Requests (24h): <b>${s.data?.requests_today ?? 0}</b> · Cost (24h): <b>$${(s.data?.cost_today ?? 0).toFixed(4)}</b>`;
    const u = await api("GET", "/admin/users");
    const tbl = $("#userTable"); tbl.innerHTML = "";
    (u.data?.users || []).forEach((x) => {
      const row = document.createElement("div"); row.className = "user-row";
      row.innerHTML = `<span><b>${x.name}</b> <span class="muted">${x.email}</span> ${x.is_admin ? '<span class="badge">admin</span>' : ''}</span>
        ${x.is_admin ? '' : '<button data-id="' + x.id + '">Make admin</button>'}`;
      const b = row.querySelector("button");
      if (b) b.onclick = async () => { await api("POST", "/admin/users/" + x.id + "/admin"); load(); };
      tbl.appendChild(row);
    });
  };
  load();
}
