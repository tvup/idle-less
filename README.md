# idle-less

**Your servers sleep. Traffic wakes them.**

A Docker-based reverse proxy with built-in Wake-on-LAN. Visitors hit your domain, the server boots automatically, and traffic flows — all in seconds.

## How it works

```
Internet → idle-less (reverse proxy) → Backend server
                 ↓ (if server is sleeping)
            Wakeforce gateway
                 ↓
            Sends Wake-on-LAN packet
                 ↓
            Server boots → traffic flows
```

1. Traffic arrives at your domain
2. idle-less checks if the backend server is online
3. If offline, Wakeforce sends a Wake-on-LAN magic packet
4. Visitors see a professional waiting screen while the server boots
5. Once online, traffic is proxied seamlessly

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/tvup/idle-less/master/install.sh | bash
```

The interactive installer will guide you through:
- Domain and backend configuration
- SSL certificate setup (Let's Encrypt compatible)
- Wakeforce Wake-on-LAN settings
- Docker Compose generation

### Installation modes

| Mode | Command | Description |
|------|---------|-------------|
| Reverse proxy + Wakeforce | `bash install.sh --wakeforce` | Full setup with WoL |
| Reverse proxy only | `bash install.sh` | Proxy without WoL |
| Wakeforce standalone | `bash install.sh --wakeforce-only` | WoL gateway with direct port mapping |

## Features

- **Automatic Wake-on-LAN** — Magic packets sent when sleeping servers receive traffic
- **SSL / HTTPS** — Full SSL termination with Let's Encrypt support
- **Multi-domain** — Route unlimited domains to different backend servers
- **Multi-platform** — Native Docker images for AMD64 and ARM64 (Raspberry Pi, Synology, QNAP)
- **One-command install** — Interactive setup generates all configuration automatically
- **Professional waiting screen** — Visitors see a polished status page with real-time health checks

## Requirements

- Docker with Compose v2
- `curl` for installation
- A server that supports Wake-on-LAN (most modern servers do)
- For Wakeforce: a device on the same LAN as the target servers (e.g., Raspberry Pi)

## Configuration

After installation, configuration is managed through the `.env` file:

```env
DOMAIN_1_HOSTNAME=app.example.com
DOMAIN_1_IP=192.168.1.50
DOMAIN_1_PORT=3080
DOMAIN_1_USE_SSL=yes
DOMAIN_1_CONFIG=wakeforce
DOMAIN_1_MAC=D8:9E:F3:12:D0:10
DOMAIN_1_BROADCAST=192.168.1.255
```

Multiple domains are supported via the `DOMAIN_{i}_*` pattern.

## Architecture

```
┌──────────────────────────────────────────┐
│  Docker Host (e.g., Raspberry Pi)        │
│                                          │
│  ┌─────────────────┐  ┌──────────────┐  │
│  │  reverse-proxy   │  │  wakeforce   │  │
│  │  (nginx)         │──│  (gateway)   │  │
│  │  :80 :443        │  │  WoL + UI    │  │
│  └─────────────────┘  └──────────────┘  │
│         │ bridge            │ macvlan    │
└─────────┼───────────────────┼────────────┘
          │                   │
    ┌─────┴─────┐     ┌──────┴──────┐
    │  Internet │     │  LAN (WoL)  │
    └───────────┘     └─────────────┘
```

## License

The **reverse proxy** is open source and free to use.

**Wakeforce** (the Wake-on-LAN gateway) requires a license key. Contact [info@torbenit.dk](mailto:info@torbenit.dk) for licensing.

---

Built by [Torben IT ApS](mailto:info@torbenit.dk) · CVR 39630605
