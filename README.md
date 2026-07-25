# MTProto Manager

One-command installer + management panel for MTProto Proxy on Ubuntu servers.

---

## English

### Features

- **One-command installation** — Just run the script and everything is set up
- **Interactive management panel** — Add/remove proxies, change port, Fake-TLS domain
- **Web UI Dashboard** — Modern browser-based panel for managing proxies visually
- **Auto-generated secrets** — Or use your own 32-character hex secrets
- **Fake-TLS** — Traffic looks like regular HTTPS
- **Per-user limits** — Data quota (GB) and max simultaneous connections
- **Sponsor channel support** — Connect to Telegram's official MTProto bot
- **Systemd services** — Auto-start on boot with restart on failure

### Requirements

- Ubuntu (or Debian-based) server
- Root/sudo access
- Python 3, git, curl (auto-installed)

### Quick Install (from GitHub)

```bash
bash <(curl -s https://raw.githubusercontent.com/winston-hub/mtproto/main/mtproto-manager.sh)
```

### Manual Install (without GitHub)

1. Upload all files to `/tmp/webui/` on your server:
   ```
   webui.py
   templates/index.html
   mtproto-manager.sh
   ```
2. Run:
   ```bash
   cd /tmp/webui
   bash mtproto-manager.sh
   ```

### Management Menu

```bash
mtproto-manager
```

```
=== MTProto Proxy Manager ===
1) Create new proxy
2) Show all proxies and links
3) Remove a proxy
4) Change port (global)
5) Change Fake-TLS domain (global)
6) Set/remove sponsor channel
7) Restart service
8) Web UI (install / manage)
0) Exit
```

### Web UI

Open browser: `http://YOUR_SERVER_IP:5000`

- Add/remove proxies with one click
- Copy proxy links instantly
- Change port, Fake-TLS domain, sponsor channel
- Service status monitoring
- Auto-refresh every 30 seconds

### Technical Details

- Based on [alexbers/mtprotoproxy](https://github.com/alexbers/mtprotoproxy)
- Proxy installs to `/opt/mtprotoproxy`
- Web UI at `/opt/mtprotoproxy-webui`
- State file: `/opt/mtprotoproxy/manager_state.json`
- Proxy service: `mtprotoproxy`
- Web UI service: `mtproto-webui`

---

## License

MIT License
