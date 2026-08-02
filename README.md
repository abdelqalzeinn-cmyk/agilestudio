# AgileStudio Platform

A complete AI coding assistant platform for Roblox Studio, split into **two deployables**:

- **API** (`backend/`) — a pure JSON FastAPI service (auth, API tokens, usage/quota,
  admin, streaming chat, Roblox OAuth). No HTML.
- **Site** (`site/`) — a separate static website (login, dashboard, admin, legal pages)
  that calls the API over the network via `API_BASE`.
- **Plugin** (`plugin/`) — the Roblox Studio plugin that talks to the API.

```
agilestudio/
├── backend/            # API service (FastAPI, SQLite, CORS-enabled)
│   ├── main.py         # routes: auth, tokens, usage, chat, admin  (NO static files)
│   ├── auth.py         # password hashing, sessions, API tokens, Roblox OAuth
│   ├── usage.py        # per-user/token usage + quota
│   ├── db.py           # SQLite schema + helpers
│   ├── requirements.txt
│   └── (deployed from repo root render.yaml as service "agilestudio-api")
├── site/               # static website (deployed separately)
│   ├── index.html      # login + register + Continue with Roblox
│   ├── dashboard.html  # mint tokens, see usage
│   ├── admin.html      # admin panel
│   ├── terms.html, privacy.html
│   ├── app.js          # calls API_BASE (the separate API service)
│   └── style.css
├── plugin/             # AgileStudio.rbxmx (Roblox Studio plugin)
│   ├── AgileStudio.lua # full plugin source
│   ├── convert.py      # compiles Lua -> .rbxmx
│   └── AgileStudio.rbxmx
├── render.yaml         # BOTH services (web api + static site)
└── assets/mascot.svg   # brand mascot artwork
```

The API and site are **different services / different origins**. The site sends the
session token as a `?session=` query param (or `x-session-token` header); the API has
CORS enabled for the site origin.

## API endpoints
- `GET /health`, `GET /models/gateway`
- `POST /auth/register`, `POST /auth/login`, `GET /auth/logout`, `GET /auth/me`
- `GET /auth/roblox/start`, `GET /auth/roblox/callback` (Roblox OAuth)
- `GET /tokens`, `POST /tokens` (mint `agst_…`), `POST /tokens/revoke`
- `GET /usage`
- `POST /conversations`, `POST /conversations/{id}/messages` (Bearer/query `token`, usage counted)
- `GET /operations/{id}/events`, `POST /operations/{id}/tool_results`, `GET /conversations/{id}/timeline`
- **Admin (admin-only):** `GET /admin/stats`, `GET /admin/users`, `POST /admin/users/{id}/quota`, `POST /admin/users/{id}/admin`

## Local dev (split)
```bash
# terminal 1 — API
cd backend
python -m venv .venv && .venv/Scripts/activate
pip install -r requirements.txt
export AGILESTUDIO_OWNER_EMAIL=you@example.com
export AGILESTUDIO_ADMIN_API_KEY=some-long-random
export SITE_BASE=http://127.0.0.1:3000
uvicorn main:app --host 127.0.0.1 --port 8080

# terminal 2 — Site (any static server)
cd site
python -m http.server 3000
# then edit site/app.js API_BASE to http://127.0.0.1:8080
```
Open http://127.0.0.1:3000 → register (first user is admin) → Dashboard → mint a token.

## Deploy to Render (two services, one repo)
1. Push this repo to GitHub and connect it in Render. The included root `render.yaml`
   defines **two** services: `agilestudio-api` (web, from `backend/`) and
   `agilestudio-site` (static, from `site/`).
2. Set **Environment Variables** on the **API** service:
   | Key | Value |
   |---|---|
   | `FREELLMAPI_KEY` | your FreeLLMAPI key (chat won't stream without it) |
   | `AGILESTUDIO_OWNER_EMAIL` | the email you'll register with → becomes admin |
   | `AGILESTUDIO_ADMIN_API_KEY` | a long random string (admin via `x-api-key` header) |
   | `ROBLOX_OAUTH_CLIENT_ID` | Roblox OAuth app client id |
   | `ROBLOX_OAUTH_CLIENT_SECRET` | Roblox OAuth app client secret |
   | `ROBLOX_OAUTH_REDIRECT` | `https://<api-url>/auth/roblox/callback` |
   | `API_BASE` | `https://<api-url>` |
   | `SITE_BASE` | `https://<site-url>` |
   | `CORS_ORIGINS` | `https://<site-url>` |
3. In `site/app.js`, set `API_BASE` to your API URL (the `agilestudio-api.onrender.com`
   default matches the service name; change if yours differs).
4. Deploy both. Render gives you two URLs: the API (`agilestudio-api.onrender.com`) and
   the site (`agilestudio.onrender.com`).

## Roblox OAuth (for site users)
1. Roblox Creator Hub → OAuth Apps → create an app named `AgileStudio`.
2. Redirect URI = `https://<api-url>/auth/roblox/callback` (exact, incl. trailing slash).
3. Scopes: `openid profile`. Copy Client ID + Secret into the API env vars above.
4. The site's **Continue with Roblox** button now works (over HTTPS / the deployed URL).

## Owner login
- Register at the site with the `AGILESTUDIO_OWNER_EMAIL` you set (or simply register
  first before anyone else) → account is admin → Admin tab appears in the dashboard.
- For API/scripts: send header `x-api-key: <AGILESTUDIO_ADMIN_API_KEY>` to any `/admin/*` route.

## Plugin
1. In Roblox Studio: open the built `plugin/AgileStudio.rbxmx`, or drop it into
   `AppData/Local/Roblox/Plugins/`.
2. Open Settings (gear) → paste your API token from the dashboard → set Backend URL to your
   API URL → Save.
3. Chat, request animations/scripts, approve tool cards.

> No secrets are committed — everything sensitive is read from environment variables.
