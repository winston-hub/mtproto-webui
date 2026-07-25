#!/usr/bin/env python3
"""
MTProto Manager Web UI - Flask dashboard for mtprotoproxy
"""
import json, os, secrets, subprocess, re
from pathlib import Path
from flask import Flask, jsonify, request, render_template

INSTALL_DIR = Path("/opt/mtprotoproxy")
STATE_FILE = INSTALL_DIR / "manager_state.json"
CONFIG_FILE = INSTALL_DIR / "config.py"
SERVICE_NAME = "mtprotoproxy"

app = Flask(__name__, template_folder="templates", static_folder="static")


def _run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(cmd, -1, "", "timeout")


def load_state():
    if not STATE_FILE.exists():
        return {"port": 443, "tls_domain": "www.google.com", "ad_tag": "", "users": {}}
    with open(STATE_FILE) as f:
        return json.load(f)


def save_state(state):
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE_FILE.with_suffix(".json.tmp")
    with open(tmp, "w") as f:
        json.dump(state, f, indent=2)
    tmp.rename(STATE_FILE)


def regenerate_config(state):
    lines = []
    lines.append("PORT = {}".format(state["port"]))
    lines.append("")
    lines.append('USERS = {')
    for name, u in state["users"].items():
        lines.append('    "{}": "{}",'.format(name, u["secret"]))
    lines.append('}')
    lines.append("")
    lines.append('MODES = {"classic": False, "secure": False, "tls": True}')
    lines.append("")
    tls = state.get("tls_domain", "")
    if tls:
        lines.append('TLS_DOMAIN = "{}"'.format(tls))
        lines.append("")
    mc = {n: u["max_conns"] for n, u in state["users"].items() if u.get("max_conns", 0) > 0}
    if mc:
        lines.append("USER_MAX_TCP_CONNS = {")
        for n, v in mc.items():
            lines.append('    "{}": {},'.format(n, v))
        lines.append("}")
        lines.append("")
    q = {n: u["quota_bytes"] for n, u in state["users"].items() if u.get("quota_bytes", 0) > 0}
    if q:
        lines.append("USER_DATA_QUOTA = {")
        for n, v in q.items():
            lines.append('    "{}": {},'.format(n, v))
        lines.append("}")
        lines.append("")
    if state.get("ad_tag"):
        lines.append('AD_TAG = "{}"'.format(state["ad_tag"]))
        lines.append("")
    CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_FILE.write_text("\n".join(lines) + "\n")


def restart_service():
    _run(["systemctl", "restart", SERVICE_NAME])
    r = _run(["systemctl", "is-active", SERVICE_NAME])
    return "Service restarted (status: {})".format(r.stdout.strip())


def get_public_ip():
    r = _run(["curl", "-s", "-4", "-m", "5", "https://api.ipify.org"])
    if r.returncode == 0 and r.stdout.strip():
        return r.stdout.strip()
    return "YOUR_SERVER_IP"


def make_link(secret, port, domain, ip):
    if domain:
        hexdom = domain.encode().hex()
        return "https://t.me/proxy?server={}&port={}&secret=ee{}{}".format(ip, port, secret, hexdom)
    return "https://t.me/proxy?server={}&port={}&secret=dd{}".format(ip, port, secret)


def bytes_to_human(b):
    if b <= 0:
        return "Unlimited"
    return "{:.2f} GB".format(b / 1024**3)


def human_to_bytes(gb):
    try:
        v = float(gb)
        if v > 0:
            return int(v * 1024**3)
        return 0
    except (ValueError, TypeError):
        return 0


@app.route("/api/status")
def api_status():
    state = load_state()
    r = _run(["systemctl", "is-active", SERVICE_NAME])
    svc = r.stdout.strip() if r.returncode == 0 else "inactive"
    return jsonify({
        "service": svc,
        "port": state["port"],
        "tls_domain": state.get("tls_domain", ""),
        "ad_tag": state.get("ad_tag", ""),
        "server_ip": get_public_ip(),
        "users_count": len(state.get("users", {})),
    })


@app.route("/api/users")
def api_users():
    state = load_state()
    ip = get_public_ip()
    port = state["port"]
    domain = state.get("tls_domain", "")
    out = []
    for name, u in state.get("users", {}).items():
        link = make_link(u["secret"], port, domain, ip)
        qbytes = u.get("quota_bytes", 0)
        out.append({
            "name": name,
            "secret": u["secret"],
            "link": link,
            "quota_bytes": qbytes,
            "quota_human": bytes_to_human(qbytes),
            "max_conns": u.get("max_conns", 0),
        })
    return jsonify(out)


@app.route("/api/users", methods=["POST"])
def api_add_user():
    data = request.get_json(force=True)
    name = data.get("name", "").strip()
    if not name:
        return jsonify({"error": "Name required"}), 400
    state = load_state()
    if name in state["users"]:
        return jsonify({"error": "'{}' already exists".format(name)}), 409
    secret = data.get("secret", "").strip().lower()
    if secret:
        if not re.fullmatch(r"[0-9a-f]{32}", secret):
            return jsonify({"error": "Secret must be 32 hex chars"}), 400
        for u in state["users"].values():
            if u["secret"] == secret:
                return jsonify({"error": "Secret already used"}), 409
    else:
        secret = secrets.token_hex(16)
    if "port" in data:
        state["port"] = int(data["port"])
    if "tls_domain" in data:
        state["tls_domain"] = data["tls_domain"].strip()
    state["users"][name] = {
        "secret": secret,
        "quota_bytes": human_to_bytes(data.get("quota_gb", 0)),
        "max_conns": int(data.get("max_conns") or 0),
    }
    save_state(state)
    regenerate_config(state)
    restart_service()
    link = make_link(secret, state["port"], state.get("tls_domain", ""), get_public_ip())
    return jsonify({"success": True, "name": name, "link": link, "secret": secret})


@app.route("/api/users/<name>", methods=["DELETE"])
def api_remove_user(name):
    state = load_state()
    if name not in state["users"]:
        return jsonify({"error": "Not found"}), 404
    del state["users"][name]
    save_state(state)
    regenerate_config(state)
    restart_service()
    return jsonify({"success": True})


@app.route("/api/settings", methods=["PUT"])
def api_update_settings():
    data = request.get_json(force=True)
    state = load_state()
    if "port" in data:
        p = int(data["port"])
        if 1 <= p <= 65535:
            state["port"] = p
    if "tls_domain" in data:
        state["tls_domain"] = data["tls_domain"].strip()
    if "ad_tag" in data:
        state["ad_tag"] = data["ad_tag"].strip()
    save_state(state)
    regenerate_config(state)
    msg = restart_service()
    return jsonify({"success": True, "service_message": msg})


@app.route("/api/restart", methods=["POST"])
def api_restart():
    return jsonify({"success": True, "message": restart_service()})


@app.route("/")
def index():
    return render_template("index.html")


if __name__ == "__main__":
    print("MTProto Web UI starting on http://0.0.0.0:5000")
    app.run(host="0.0.0.0", port=5000, debug=False)
