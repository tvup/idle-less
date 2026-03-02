# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in idle-less or Wakeforce, please report it responsibly.

**Email:** [security@torbenit.dk](mailto:security@torbenit.dk)

Please include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

We will acknowledge your report within 48 hours and aim to release a fix within 7 days for critical issues.

## Security Design

### Network Architecture
- Wakeforce uses **macvlan networking** for LAN access — isolated from Docker's default bridge
- Wake-on-LAN packets are Layer 2 broadcast — they cannot cross router boundaries
- The reverse proxy terminates SSL/TLS before forwarding to backends

### License Validation
- License keys are validated against the **LemonSqueezy License API** over HTTPS (primary provider)
- Fallback validation against `validate.torbenit.dk` over HTTPS
- Validation results are cached locally for 24 hours (configurable via `LICENSE_CACHE_TTL_SECONDS`)
- No sensitive data is transmitted — only the license key and instance identifier
- Instance IDs are stored in a Docker volume (`/var/lib/wakeforce/license/`)

### Container Security
- Wakeforce requires `NET_RAW` capability for WoL packets — no other elevated permissions
- Containers run with default Docker security profiles
- No host filesystem access beyond certificate mounts (read-only)

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest  | Yes       |
| < Latest | Best effort |
