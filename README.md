# AgileStudio Platform

A complete AI coding assistant platform for Roblox Studio: a FastAPI backend (auth,
API tokens, usage/quota, admin, streaming chat), a public website where users log in
(email/password **or Roblox OAuth**) and mint their own API tokens, and a Roblox Studio
plugin that talks to it.

```
agilestudio/
├── backend/            # FastAPI app + SQLite
│   ├── main.py         # routes: auth, tokens, usage, chat, admin, serves web/
│   ├── auth.py         # password hashing, sessions, API tokens, Roblox OAuth
│   ├── usage.py        # per-user/token usage + quota
│   ├── db.py           # SQLite schema + helpers
│   ├── render.yaml     # Render web service config
│   └── requirements.txt
├── web/                # static site (index/dashboard/admin + app.js + style.css)
├── plugin/             # AgileStudio.rbxmx (Roblox Studio plugin)
│   ├── AgileStudio.lua # full plugin source
│   ├── convert.py      # compiles Lua -> .rbxmx
│   └── AgileStudio.rbxmx
└── assets/mascot.svg   # brand mascot artwork
```

## Backend endpoints
- `GET /health`, `GET /models/gateway`
- `POST /auth/register`, `POST /auth/login`, `GET /auth/logout`, `GET /auth/me`
- `GET /auth/roblox/start`, `GET /auth/roblox/callback` (Roblox OAuth)
- `GET /tokens`, `POST /tokens` (mint `agst_…`), `POST /tokens/revoke`
- `GET /usage`
- `POST /conversations`, `POST /conversations/{id}/messages` (Bearer/query `token`, usage counted)
- `GET /operations/{id}/events`, `POST /operations/{id}/tool_results`, `GET /conversations/{id}/timeline`
- **Admin (admin-only):** `GET /admin/stats`, `GET /admin/users`, `POST /admin/users/{id}/quota`, `POST /admin/users/{id}/admin`

## Local dev
```bash
cd backend
python -m venv .venv && .venv/Scripts/activate
pip install -r requirements.txt
# (optional) set owner + admin key:
export AGILESTUDIO_OWNER_EMAIL=you@example.com
export AGILESTUDIO_ADMIN_API_KEY=some-long-random
uvicorn main:app --host 127.0.0.1 --port 8060
```
Open http://127.0.0.1:8060 → register (first user is admin) → Dashboard → mint a token.

## Deploy to Render
1. Push this repo to GitHub.
2. In Render: **New → Web Service** → connect the repo → use the included `render.yaml`
   (or set: Runtime `Python 3.11`, Build `pip install -r requirements.txt`,
   Start `uvicorn main:app --host 0.0.0.0 --port $PORT`, Health path `/health`).
3. Set **Environment Variables** in the Render dashboard:
   | Key | Value |
   |---|---|
   | `FREELLMAPI_KEY` | your FreeLLMAPI key (chat won't stream without it) |
   | `AGILESTUDIO_OWNER_EMAIL` | the email you'll register with → becomes admin |
   | `AGILESTUDIO_ADMIN_API_KEY` | a long random string (admin via `x-api-key` header) |
   | `ROBLOX_OAUTH_CLIENT_ID` | Roblox OAuth app client id (see below) |
   | `ROBLOX_OAUTH_CLIENT_SECRET` | Roblox OAuth app client secret |
   | `ROBLOX_OAUTH_REDIRECT` | `https://<your-render-url>/auth/roblox/callback` |
4. Deploy. Render gives you a URL (e.g. `https://agilestudio.onrender.com`).

## Roblox OAuth (for site users)
1. Roblox Creator Hub → OAuth Apps → create an app named `AgileStudio`.
2. Redirect URI = `https://<your-render-url>/auth/roblox/callback` (exact, incl. trailing slash).
3. Scopes: `openid profile`. Copy Client ID + Secret into the env vars above.
4. The site's **Continue with Roblox** button now works (only over HTTPS / the deployed URL).

## Owner login
- Register at the site with the `AGILESTUDIO_OWNER_EMAIL` you set (or simply register first
  before anyone else) → account is admin → Admin tab appears in the dashboard.
- For API/scripts: send header `x-api-key: <AGILESTUDIO_ADMIN_API_KEY>` to any `/admin/*` route.

## Plugin
1. In Roblox Studio: Plugins → open the built `plugin/AgileStudio.rbxmx`, or drag it into
   `AppData/Local/Roblox/Plugins/`.
2. Open Settings (gear) → paste your API token from the dashboard → set Backend URL to your
   Render URL → Save.
3. Chat, request animations/scripts, approve tool cards.

> No secrets are committed — everything sensitive is read from environment variables.
