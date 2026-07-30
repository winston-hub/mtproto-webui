#!/bin/bash
# ============================================================
#  mtproto-manager.sh
#  One-command installer + management panel for a lightweight
#  MTProto Proxy (based on alexbers/mtprotoproxy).
#
#  After install, run the panel anytime with:
#     mtproto-manager
#
#  Usage:
#    bash mtproto-manager.sh          # install (or open panel if already installed)
# ============================================================

set -e

INSTALL_DIR="/opt/mtprotoproxy"
CONFIG="${INSTALL_DIR}/config.py"
STATE="${INSTALL_DIR}/manager_state.json"
SERVICE_NAME="mtprotoproxy"
BIN_PATH="/usr/local/bin/mtproto-manager"

RED='\033[0;31m'
GR='\033[0;32m'
YE='\033[0;33m'
CY='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GR}[INFO]${NC} $1"; }
warn()  { echo -e "${YE}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" 1>&2; exit 1; }

# ------------------------------------------------------------
# INSTALL
# ------------------------------------------------------------
do_install() {
    info "Installing dependencies..."
    apt update -y
    apt install -y python3 python3-pip git curl

    info "Cloning mtprotoproxy..."
    rm -rf "$INSTALL_DIR"
    git clone https://github.com/alexbers/mtprotoproxy.git "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    info "Attempting to install cryptg for better performance (optional)..."
    pip3 install cryptg --break-system-packages 2>/dev/null || warn "cryptg not installed, proxy will still work but slower"

    info "Creating initial state..."
    python3 - "$STATE" <<'EOF'
import json, sys, os
state_path = sys.argv[1]
if not os.path.exists(state_path):
    state = {
        "port": 443,
        "tls_domain": "www.google.com",
        "ad_tag": "",
        "users": {}
    }
    with open(state_path, "w") as f:
        json.dump(state, f, indent=2)
EOF

    regenerate_config

    info "Creating systemd service..."
    cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=Lightweight MTProto Proxy
After=network.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/python3 ${INSTALL_DIR}/mtprotoproxy.py
Restart=on-failure
RestartSec=3
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ${SERVICE_NAME}
    systemctl restart ${SERVICE_NAME}

    info "Installing management panel as 'mtproto-manager'..."
    write_panel

    info "Installation complete. From now on just run: mtproto-manager"
}

# ------------------------------------------------------------
# Rebuild config.py from manager_state.json (single source of truth)
# ------------------------------------------------------------
regenerate_config() {
    python3 - "$STATE" "$CONFIG" <<'EOF'
import json, sys

state_path, config_path = sys.argv[1], sys.argv[2]
with open(state_path) as f:
    state = json.load(f)

lines = []
lines.append('PORT = {}'.format(state["port"]))
lines.append('')
lines.append('# name -> secret (32 hex chars)')
lines.append('USERS = {')
for name, u in state["users"].items():
    lines.append('    "{}": "{}",'.format(name, u["secret"]))
lines.append('}')
lines.append('')
lines.append('MODES = {')
lines.append('    "classic": False,')
lines.append('    "secure": False,')
lines.append('    "tls": True')
lines.append('}')
lines.append('')
if state.get("tls_domain"):
    lines.append('TLS_DOMAIN = "{}"'.format(state["tls_domain"]))
    lines.append('')

max_conns = {n: u["max_conns"] for n, u in state["users"].items() if u.get("max_conns", 0) > 0}
if max_conns:
    lines.append('# per-user simultaneous TCP connection limit')
    lines.append('USER_MAX_TCP_CONNS = {')
    for name, val in max_conns.items():
        lines.append('    "{}": {},'.format(name, val))
    lines.append('}')
    lines.append('')

quotas = {n: u["quota_bytes"] for n, u in state["users"].items() if u.get("quota_bytes", 0) > 0}
if quotas:
    lines.append('# per-user data quota in bytes')
    lines.append('USER_DATA_QUOTA = {')
    for name, val in quotas.items():
        lines.append('    "{}": {},'.format(name, val))
    lines.append('}')
    lines.append('')

if state.get("ad_tag"):
    lines.append('# sponsor channel tag, obtained from @MTProxybot')
    lines.append('AD_TAG = "{}"'.format(state["ad_tag"]))
    lines.append('')

with open(config_path, "w") as f:
    f.write("\n".join(lines) + "\n")
EOF
}

# ------------------------------------------------------------
# PANEL (written to /usr/local/bin/mtproto-manager)
# ------------------------------------------------------------
write_panel() {
cat > "$BIN_PATH" <<'PANEL_EOF'
#!/bin/bash
# MTProto Proxy management panel

INSTALL_DIR="/opt/mtprotoproxy"
CONFIG="${INSTALL_DIR}/config.py"
STATE="${INSTALL_DIR}/manager_state.json"
SERVICE_NAME="mtprotoproxy"

RED='\033[0;31m'
GR='\033[0;32m'
YE='\033[0;33m'
CY='\033[0;36m'
NC='\033[0m'

if [ ! -f "$STATE" ]; then
    echo -e "${RED}manager_state.json not found. Is mtprotoproxy installed via mtproto-manager.sh?${NC}"
    exit 1
fi

regenerate_config() {
    python3 - "$STATE" "$CONFIG" <<'EOF'
import json, sys

state_path, config_path = sys.argv[1], sys.argv[2]
with open(state_path) as f:
    state = json.load(f)

lines = []
lines.append('PORT = {}'.format(state["port"]))
lines.append('')
lines.append('# name -> secret (32 hex chars)')
lines.append('USERS = {')
for name, u in state["users"].items():
    lines.append('    "{}": "{}",'.format(name, u["secret"]))
lines.append('}')
lines.append('')
lines.append('MODES = {')
lines.append('    "classic": False,')
lines.append('    "secure": False,')
lines.append('    "tls": True')
lines.append('}')
lines.append('')
if state.get("tls_domain"):
    lines.append('TLS_DOMAIN = "{}"'.format(state["tls_domain"]))
    lines.append('')

max_conns = {n: u["max_conns"] for n, u in state["users"].items() if u.get("max_conns", 0) > 0}
if max_conns:
    lines.append('# per-user simultaneous TCP connection limit')
    lines.append('USER_MAX_TCP_CONNS = {')
    for name, val in max_conns.items():
        lines.append('    "{}": {},'.format(name, val))
    lines.append('}')
    lines.append('')

quotas = {n: u["quota_bytes"] for n, u in state["users"].items() if u.get("quota_bytes", 0) > 0}
if quotas:
    lines.append('# per-user data quota in bytes')
    lines.append('USER_DATA_QUOTA = {')
    for name, val in quotas.items():
        lines.append('    "{}": {},'.format(name, val))
    lines.append('}')
    lines.append('')

if state.get("ad_tag"):
    lines.append('# sponsor channel tag, obtained from @MTProxybot')
    lines.append('AD_TAG = "{}"'.format(state["ad_tag"]))
    lines.append('')

with open(config_path, "w") as f:
    f.write("\n".join(lines) + "\n")
EOF
}

get_ip() {
    curl -s -4 -m 8 https://api.ipify.org || echo "YOUR_SERVER_IP"
}

get_state() {
    python3 -c "
import json
state = json.load(open('$STATE'))
print($1)
"
}

human_to_bytes() {
    local val="$1"
    if [ -z "$val" ] || [ "$val" = "0" ]; then
        echo 0
    else
        python3 -c "print(int(float('$val') * 1024**3))"
    fi
}

bytes_to_human() {
    local val="$1"
    if [ -z "$val" ] || [ "$val" = "0" ]; then
        echo "unlimited"
    else
        python3 -c "print('{:.2f} GB'.format($val / 1024**3))"
    fi
}

make_link() {
    local secret="$1"
    local ip=$(get_ip)
    local port=$(get_state 'state["port"]')
    local domain=$(get_state 'state["tls_domain"]')
    if [ -n "$domain" ] && [ "$domain" != "None" ]; then
        local hexdom=$(echo -n "$domain" | od -An -tx1 | tr -d ' \n')
        echo "https://t.me/proxy?server=${ip}&port=${port}&secret=ee${secret}${hexdom}"
    else
        echo "https://t.me/proxy?server=${ip}&port=${port}&secret=dd${secret}"
    fi
}

show_all() {
    local port=$(get_state 'state["port"]')
    local domain=$(get_state 'state["tls_domain"]')
    local ad_tag=$(get_state 'state["ad_tag"] or "-"')
    echo -e "${CY}--- Global settings ---${NC}"
    echo "Port: $port"
    echo "Fake-TLS domain: $domain"
    echo "Sponsor channel (AD_TAG): $ad_tag"
    echo ""
    echo -e "${CY}--- Proxies ---${NC}"
    python3 -c "
import json
state = json.load(open('$STATE'))
for name, u in state['users'].items():
    print(name)
" > /tmp/mtp_names.$$
    if [ ! -s /tmp/mtp_names.$$ ]; then
        echo "No proxies created yet."
        rm -f /tmp/mtp_names.$$
        return
    fi
    while read -r name; do
        [ -z "$name" ] && continue
        local secret=$(get_state "state['users']['$name']['secret']")
        local quota=$(get_state "state['users']['$name'].get('quota_bytes', 0)")
        local conns=$(get_state "state['users']['$name'].get('max_conns', 0)")
        echo -e "${GR}${name}${NC}: $(make_link "$secret")"
        echo "   Data limit: $(bytes_to_human "$quota")   |   Max simultaneous connections: $([ "$conns" = "0" ] && echo "unlimited" || echo "$conns")"
    done < /tmp/mtp_names.$$
    rm -f /tmp/mtp_names.$$
}

set_sponsor_channel() {
    local current=$(get_state 'state["ad_tag"] or "(not set)"')
    echo -e "${CY}Current sponsor channel: ${current}${NC}"
    echo "To get a tag, message @MTProxybot on Telegram, give it your server IP and port, then enter one of your users' secrets when asked."
    read -p "Enter the sponsor channel tag (leave empty to disable): " tag
    python3 - "$tag" <<'EOF'
import json, sys
tag = sys.argv[1]
state = json.load(open("/opt/mtprotoproxy/manager_state.json"))
state["ad_tag"] = tag
json.dump(state, open("/opt/mtprotoproxy/manager_state.json", "w"), indent=2)
EOF
    regenerate_config
    systemctl restart "$SERVICE_NAME"
    if [ -n "$tag" ]; then
        echo -e "${GR}Sponsor channel set.${NC}"
    else
        echo -e "${YE}Sponsor channel disabled.${NC}"
    fi
}

add_user() {
    local cur_port=$(get_state 'state["port"]')
    local cur_domain=$(get_state 'state["tls_domain"]')

    read -p "Name for this proxy (no spaces): " name
    if [ -z "$name" ]; then
        echo -e "${RED}Name cannot be empty.${NC}"
        return
    fi

    echo -e "${YE}Note: port and Fake-TLS domain are global and affect ALL proxies, not just this one.${NC}"
    read -p "Port [current: ${cur_port}]: " port
    port=${port:-$cur_port}

    read -p "Fake-TLS domain [current: ${cur_domain}]: " domain
    domain=${domain:-$cur_domain}

    read -p "Data limit in GB (0 or empty = unlimited): " quota_gb
    quota_bytes=$(human_to_bytes "$quota_gb")

    read -p "Max simultaneous connections / roughly equals device or IP limit (0 or empty = unlimited): " max_conns
    max_conns=${max_conns:-0}

    secret=""
    while true; do
        read -p "Secret (32 hex chars, leave empty to auto-generate): " custom_secret
        if [ -z "$custom_secret" ]; then
            secret=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
            echo -e "${GR}Auto-generated secret: ${secret}${NC}"
            break
        fi
        custom_secret=$(echo -n "$custom_secret" | tr '[:upper:]' '[:lower:]')
        if ! [[ "$custom_secret" =~ ^[0-9a-f]{32}$ ]]; then
            echo -e "${RED}Invalid secret: must be exactly 32 hex characters (0-9, a-f).${NC}"
            continue
        fi
        dup=$(python3 -c "
import json
state = json.load(open('$STATE'))
print('yes' if any(u['secret'] == '$custom_secret' for u in state['users'].values()) else 'no')
")
        if [ "$dup" = "yes" ]; then
            echo -e "${RED}This secret is already used by another proxy. Choose a different one.${NC}"
            continue
        fi
        secret="$custom_secret"
        break
    done

    python3 - "$name" "$secret" "$port" "$domain" "$quota_bytes" "$max_conns" <<'EOF'
import json, sys
name, secret, port, domain, quota_bytes, max_conns = sys.argv[1:7]
state = json.load(open("/opt/mtprotoproxy/manager_state.json"))
state["port"] = int(port)
state["tls_domain"] = domain
state["users"][name] = {
    "secret": secret,
    "quota_bytes": int(quota_bytes),
    "max_conns": int(max_conns)
}
json.dump(state, open("/opt/mtprotoproxy/manager_state.json", "w"), indent=2)
EOF
    regenerate_config
    systemctl restart "$SERVICE_NAME"

    echo ""
    echo -e "${GR}Proxy '${name}' created:${NC}"
    echo "$(make_link "$secret")"

    echo ""
    read -p "Do you want to set/change the sponsor channel too? (y/n): " want_sponsor
    if [ "$want_sponsor" = "y" ] || [ "$want_sponsor" = "Y" ]; then
        set_sponsor_channel
    fi
}

remove_user() {
    show_all
    echo ""
    read -p "Name of the proxy to remove: " name
    python3 - "$name" <<'EOF'
import json, sys
name = sys.argv[1]
state = json.load(open("/opt/mtprotoproxy/manager_state.json"))
state["users"].pop(name, None)
json.dump(state, open("/opt/mtprotoproxy/manager_state.json", "w"), indent=2)
EOF
    regenerate_config
    systemctl restart "$SERVICE_NAME"
    echo -e "${YE}Proxy '${name}' removed (if it existed).${NC}"
}

change_port() {
    read -p "New port (affects ALL proxies): " newport
    python3 - "$newport" <<'EOF'
import json, sys
newport = int(sys.argv[1])
state = json.load(open("/opt/mtprotoproxy/manager_state.json"))
state["port"] = newport
json.dump(state, open("/opt/mtprotoproxy/manager_state.json", "w"), indent=2)
EOF
    regenerate_config
    systemctl restart "$SERVICE_NAME"
    echo -e "${GR}Port changed to ${newport} and service restarted.${NC}"
}

change_domain() {
    read -p "New Fake-TLS domain (affects ALL proxies): " newdomain
    python3 - "$newdomain" <<'EOF'
import json, sys
newdomain = sys.argv[1]
state = json.load(open("/opt/mtprotoproxy/manager_state.json"))
state["tls_domain"] = newdomain
json.dump(state, open("/opt/mtprotoproxy/manager_state.json", "w"), indent=2)
EOF
    regenerate_config
    systemctl restart "$SERVICE_NAME"
    echo -e "${GR}Fake-TLS domain changed to ${newdomain}.${NC}"
}

restart_service() {
    systemctl restart "$SERVICE_NAME"
    systemctl status "$SERVICE_NAME" --no-pager -l | head -10
}

# ------------------------------------------------------------
# WEB UI — install / manage
# ------------------------------------------------------------
WEBUI_DIR="/opt/mtprotoproxy-webui"
WEBUI_SERVICE="mtproto-webui"

install_webui() {
    if systemctl list-unit-files 2>/dev/null | grep -q "^${WEBUI_SERVICE}.service"; then
        echo -e "${YE}Web UI is already installed.${NC}"
        local ip=$(curl -s -4 -m 5 https://api.ipify.org 2>/dev/null || echo "YOUR_SERVER_IP")
        echo -e "Your panel: ${CY}http://${ip}:5000${NC}"
        read -p "Reinstall anyway? (y/N): " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            return
        fi
    fi

    info "Installing Python dependencies..."
    pip3 install flask --break-system-packages --ignore-installed blinker 2>/dev/null || \
    pip3 install flask --break-system-packages

    info "Setting up Web UI directory..."
    rm -rf "$WEBUI_DIR"
    mkdir -p "$WEBUI_DIR/templates"

    local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "${SCRIPT_DIR}/webui.py" ]; then
        cp "${SCRIPT_DIR}/webui.py" "${WEBUI_DIR}/webui.py"
        [ -d "${SCRIPT_DIR}/templates" ] && cp -r "${SCRIPT_DIR}/templates" "${WEBUI_DIR}/"
    elif [ -f "/tmp/webui/webui.py" ]; then
        cp "/tmp/webui/webui.py" "${WEBUI_DIR}/webui.py"
        [ -d "/tmp/webui/templates" ] && cp -r "/tmp/webui/templates" "${WEBUI_DIR}/"
    else
        info "Downloading Web UI files from GitHub..."
        local REPO_URL="https://raw.githubusercontent.com/winston-hub/mtproto-webui/main"
        curl -sSL "${REPO_URL}/webui.py" -o "${WEBUI_DIR}/webui.py" || error "Failed to download webui.py"
        curl -sSL "${REPO_URL}/templates/index.html" -o "${WEBUI_DIR}/templates/index.html" || error "Failed to download index.html"
        curl -sSL "${REPO_URL}/templates/login.html" -o "${WEBUI_DIR}/templates/login.html" || error "Failed to download login.html"
    fi

    chmod +x "${WEBUI_DIR}/webui.py"

    info "Creating systemd service for Web UI..."
    cat > /etc/systemd/system/${WEBUI_SERVICE}.service <<EOF
[Unit]
Description=MTProto Manager Web UI
After=network.target ${SERVICE_NAME}.service

[Service]
Type=simple
WorkingDirectory=${WEBUI_DIR}
ExecStart=/usr/bin/python3 ${WEBUI_DIR}/webui.py
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ${WEBUI_SERVICE}
    systemctl restart ${WEBUI_SERVICE}

    local ip=$(curl -s -4 -m 5 https://api.ipify.org 2>/dev/null || echo "YOUR_SERVER_IP")
    echo ""
    echo -e "${GR}============================================${NC}"
    echo -e "${GR}  Web UI installed successfully!${NC}"
    echo -e "${CY}  http://${ip}:5000${NC}"
    echo -e "${GR}============================================${NC}"
}

webui_info() {
    if ! systemctl list-unit-files 2>/dev/null | grep -q "^${WEBUI_SERVICE}.service"; then
        echo -e "${YE}Web UI is not installed yet.${NC}"
        read -p "Do you want to install it now? (Y/n): " ans
        if [ "$ans" != "n" ] && [ "$ans" != "N" ]; then
            install_webui
        fi
        return
    fi
    local ip=$(curl -s -4 -m 5 https://api.ipify.org 2>/dev/null || echo "YOUR_SERVER_IP")
    local active=$(systemctl is-active ${WEBUI_SERVICE} 2>/dev/null)
    echo -e "${CY}--- Web UI ---${NC}"
    echo -e "URL:     ${GR}http://${ip}:5000${NC}"
    echo -e "Status:  $([ "$active" = "active" ] && echo -e "${GR}Running${NC}" || echo -e "${RED}Not running${NC}")"
    echo "Service: ${WEBUI_SERVICE}"
    if [ -f "${WEBUI_DIR}/auth.json" ]; then
        echo -e "Auth:    ${GR}Enabled${NC}"
    else
        echo -e "Auth:    ${YE}Disabled (open access)${NC}"
    fi
    echo ""
    echo "1) Start Web UI"
    echo "2) Stop Web UI"
    echo "3) Restart Web UI"
    echo "4) View logs (last 20 lines)"
    echo "5) Set/change login password"
    echo "6) Remove login password"
    echo "0) Back"
    read -p "Choice: " wc
    case $wc in
        1) systemctl start ${WEBUI_SERVICE}; echo -e "${GR}Started.${NC}" ;;
        2) systemctl stop ${WEBUI_SERVICE}; echo -e "${YE}Stopped.${NC}" ;;
        3) systemctl restart ${WEBUI_SERVICE}; echo -e "${GR}Restarted.${NC}" ;;
        4) journalctl -u ${WEBUI_SERVICE} --no-pager -n 20 ;;
        5) set_webui_password ;;
        6) remove_webui_password ;;
    esac
}

set_webui_password() {
    echo -e "${CY}--- Set Web UI Password ---${NC}"
    read -p "Username: " wu_user
    if [ -z "$wu_user" ]; then
        echo -e "${RED}Username cannot be empty.${NC}"
        return
    fi
    read -s -p "Password: " wu_pass
    echo ""
    if [ -z "$wu_pass" ]; then
        echo -e "${RED}Password cannot be empty.${NC}"
        return
    fi
    read -s -p "Confirm password: " wu_pass2
    echo ""
    if [ "$wu_pass" != "$wu_pass2" ]; then
        echo -e "${RED}Passwords do not match.${NC}"
        return
    fi
    mkdir -p "$WEBUI_DIR"
    python3 - "$wu_user" "$wu_pass" "${WEBUI_DIR}/auth.json" <<'PWEOF'
import sys, json
from werkzeug.security import generate_password_hash
username, password, auth_path = sys.argv[1], sys.argv[2], sys.argv[3]
data = {"username": username, "password_hash": generate_password_hash(password)}
with open(auth_path, "w") as f:
    json.dump(data, f, indent=2)
PWEOF
    if [ $? -eq 0 ]; then
        chmod 600 "${WEBUI_DIR}/auth.json"
        systemctl restart ${WEBUI_SERVICE} 2>/dev/null
        echo -e "${GR}Password set! Restarting Web UI...${NC}"
        echo -e "User: ${CY}${wu_user}${NC}"
    else
        echo -e "${RED}Failed to set password (is werkzeug installed?)${NC}"
    fi
}

remove_webui_password() {
    if [ ! -f "${WEBUI_DIR}/auth.json" ]; then
        echo -e "${YE}No password is set.${NC}"
        return
    fi
    read -p "Remove login password? (y/N): " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        rm -f "${WEBUI_DIR}/auth.json"
        systemctl restart ${WEBUI_SERVICE} 2>/dev/null
        echo -e "${YE}Password removed. Web UI is now open access.${NC}"
    fi
}

while true; do
    echo ""
    echo -e "${CY}=== MTProto Proxy Manager ===${NC}"
    echo "1) Create new proxy"
    echo "2) Show all proxies and links"
    echo "3) Remove a proxy"
    echo "4) Change port (global)"
    echo "5) Change Fake-TLS domain (global)"
    echo "6) Set/remove sponsor channel"
    echo "7) Restart service"
    echo "8) Web UI (install / manage)"
    echo "0) Exit"
    read -p "Choice: " choice
    case $choice in
        1) add_user ;;
        2) show_all ;;
        3) remove_user ;;
        4) change_port ;;
        5) change_domain ;;
        6) set_sponsor_channel ;;
        7) restart_service ;;
        8) webui_info ;;
        0) exit 0 ;;
        *) echo -e "${RED}Invalid option${NC}" ;;
    esac
done
PANEL_EOF
chmod +x "$BIN_PATH"
}

# ------------------------------------------------------------
# ENTRYPOINT
# ------------------------------------------------------------
if [ -f "$STATE" ] && systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service"; then
    warn "mtprotoproxy is already installed. Opening the panel..."
    write_panel
    exec "$BIN_PATH"
else
    do_install
    echo ""
    echo "================================================================"
    echo -e "${GR}[DONE] Installation complete.${NC}"
    echo "From now on just run:"
    echo -e "   ${CY}mtproto-manager${NC}"
    echo "================================================================"
    exec "$BIN_PATH"
fi
