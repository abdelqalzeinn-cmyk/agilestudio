// AgileStudio web app logic
const $ = (s) => document.querySelector(s);
const api = async (method, path, body) => {
  const opts = { method, credentials: "same-origin", headers: { "Content-Type": "application/json" } };
  if (body) opts.body = JSON.stringify(body);
  const r = await fetch(path, opts);
  if (r.status === 401) { if (path !== "/auth/me") location.href = "/"; throw new Error("auth"); }
  let data = null; try { data = await r.json(); } catch (e) {}
  return { status: r.status, data };
};
const toast = (m) => { const t = $("#toast"); if (!t) return; t.textContent = m; t.classList.remove("hidden"); setTimeout(() => t.classList.add("hidden"), 2600); };

// ---------- index: login / register / oauth ----------
const loginForm = $("#loginForm"), registerForm = $("#registerForm");
if (loginForm) {
  $("#toRegister").onclick = (e) => { e.preventDefault(); loginForm.classList.add("hidden"); registerForm.classList.remove("hidden"); };
  $("#toLogin").onclick = (e) => { e.preventDefault(); registerForm.classList.add("hidden"); loginForm.classList.remove("hidden"); };
  loginForm.onsubmit = async (e) => {
    e.preventDefault();
    const r = await api("POST", "/auth/login", { email: $("#email").value, password: $("#password").value });
    if (r.status === 200) location.href = "/dashboard"; else $("#loginErr").textContent = r.data?.detail || "Login failed";
  };
  registerForm.onsubmit = async (e) => {
    e.preventDefault();
    const r = await api("POST", "/auth/register", { email: $("#regEmail").value, name: $("#regName").value, password: $("#regPassword").value });
    if (r.status === 200 || r.status === 302) location.href = "/dashboard"; else $("#regErr").textContent = r.data?.detail || "Register failed";
  };
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
  const me = await api("GET", "/auth/me");
  if (me.data?.is_admin) $("#adminLinkWrap").classList.remove("hidden");
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
