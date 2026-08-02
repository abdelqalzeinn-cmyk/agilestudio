"""Usage / quota tracking per user+token."""
import time
import uuid

import db
import auth


def cost_for(op, model):
    if op == "chat":
        return 0.002
    if op == "tool":
        return 0.001
    return 0.0005


def daily_usage(user_id):
    start = int(time.time()) - 86400
    rows = db.q("SELECT COUNT(*) AS c, COALESCE(SUM(cost),0) AS cost FROM usage WHERE user_id=? AND created_at>?", (user_id, start))
    r = rows[0]
    return {"requests": r["c"], "cost": float(r["cost"])}


def check_quota(user_id):
    q = db.q("SELECT * FROM quotas WHERE user_id=?", (user_id,))
    quota = q[0] if q else {"daily_requests": 1000, "daily_cost": 1.0}
    used = daily_usage(user_id)
    if used["requests"] >= quota["daily_requests"]:
        return False, "daily request quota reached"
    if used["cost"] >= quota["daily_cost"]:
        return False, "daily cost quota reached"
    return True, ""


def record(token_id, user_id, op, model, cost=None):
    c = cost if cost is not None else cost_for(op, model)
    db.execute("INSERT INTO usage (id,token_id,user_id,op,model,cost,created_at) VALUES (?,?,?,?,?,?,?)",
               (uuid.uuid4().hex, token_id, user_id, op, model, c, int(time.time())))
    db.execute("UPDATE apitokens SET last_used=? WHERE id=?", (int(time.time()), token_id))
