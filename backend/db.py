"""SQLite persistence for AgileStudio Platform. Single-file, no external deps."""
import os
import sqlite3
import time
import threading

DB_PATH = os.environ.get("AGILESTUDIO_DB", os.path.join(os.path.dirname(os.path.abspath(__file__)), "data", "agilestudio.db"))

def _ensure_dir(path):
    d = os.path.dirname(path)
    try:
        os.makedirs(d, exist_ok=True)
    except (PermissionError, OSError):
        # Render free / read-only parent (e.g. /data): fall back to a writable cwd path
        fallback = os.path.join(os.getcwd(), "agilestudio.db")
        return fallback
    return path

DB_PATH = _ensure_dir(DB_PATH)

_lock = threading.Lock()
_conn = None


def conn():
    global _conn
    if _conn is None:
        _conn = sqlite3.connect(DB_PATH, check_same_thread=False)
        _conn.row_factory = sqlite3.Row
    return _conn


def init():
    with _lock:
        c = conn()
        c.executescript("""
        CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            email TEXT UNIQUE,
            name TEXT,
            password_hash TEXT,
            roblox_id TEXT,
            roblox_username TEXT,
            is_admin INTEGER DEFAULT 0,
            created_at INTEGER
        );
        CREATE TABLE IF NOT EXISTS sessions (
            token TEXT PRIMARY KEY,
            user_id TEXT,
            created_at INTEGER,
            expires_at INTEGER
        );
        CREATE TABLE IF NOT EXISTS apitokens (
            id TEXT PRIMARY KEY,
            user_id TEXT,
            name TEXT,
            token TEXT UNIQUE,
            scopes TEXT,
            created_at INTEGER,
            last_used INTEGER,
            revoked INTEGER DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS usage (
            id TEXT PRIMARY KEY,
            token_id TEXT,
            user_id TEXT,
            op TEXT,
            model TEXT,
            cost REAL,
            created_at INTEGER
        );
        CREATE TABLE IF NOT EXISTS oauth_state (
            state TEXT PRIMARY KEY,
            redirect_after TEXT,
            created_at INTEGER
        );
        CREATE TABLE IF NOT EXISTS quotas (
            user_id TEXT PRIMARY KEY,
            daily_requests INTEGER DEFAULT 1000,
            daily_cost REAL DEFAULT 1.0
        );
        CREATE INDEX IF NOT EXISTS idx_usage_user ON usage(user_id);
        CREATE INDEX IF NOT EXISTS idx_usage_token ON usage(token_id);
        """)
        c.commit()


def q(sql, params=()):
    with _lock:
        cur = conn().execute(sql, params)
        return cur.fetchall()


def execute(sql, params=()):
    with _lock:
        cur = conn().execute(sql, params)
        conn().commit()
        return cur


init()
