# Idle-less

**Always-reachable services — even when your servers sleep.**

TL;DR
```
  curl -fsSL https://raw.githubusercontent.com/tvup/idle-less/master/install.sh | bash
```

Idle-less is a lightweight gateway solution that keeps your application reachable even when backend servers are scaled to zero, powered down, or temporarily unavailable.

It ensures that incoming requests are never “lost”, even if the actual workload is not currently running.

> **Idle-less is powered by the Wakeforce gateway.**

---

## The problem

Modern infrastructure increasingly relies on *sleeping* or *on-demand* servers:

* development and staging environments
* cost-optimized production workloads
* auto-scaled services
* energy-aware deployments

While this saves money and resources, it introduces a fundamental issue:

> If everything sleeps, the first request has nowhere to go.

Users experience timeouts, broken links, or confusing errors — even though the system is technically “healthy”.

---

## The solution

Idle-less introduces a small, always-on control layer **in front of your application**.

This layer:

* receives incoming traffic
* determines whether the backend is ready
* wakes the backend if necessary
* communicates the warm-up state clearly to the client

Your application code remains unchanged.

---

## How Idle-less works

1. All traffic enters through a reverse proxy
2. Requests are forwarded to the Wakeforce gateway
3. Wakeforce checks backend availability
4. If the backend is sleeping:

   * a wake action is triggered
   * the client receives a controlled warm-up response
5. Once the backend is ready, traffic flows normally

Idle-less stays online even when the backend is completely offline.

---

## Architecture overview

```
Client
  |
  v
[Reverse Proxy]        ← always on
  |
  v
[Wakeforce Gateway]    ← always on
  |
  v
[Backend Service]      ← may sleep
```

Only the proxy and gateway must remain awake.

---

## Core components

### Idle-less (product)

* Installation bundle
* Reverse proxy configuration
* Gateway orchestration
* Client-safe warm-up behavior
* Documentation and automation

### Wakeforce (gateway)

* Always-on HTTP gateway
* Backend health detection
* Wake triggering
* Request forwarding
* Explicit warm-up responses (`202 + Retry-After`)

**Idle-less is powered by the Wakeforce gateway.**

---

## What you get (v1)

Idle-less v1 ships as a minimal, self-contained bundle:

* **Two Docker images**

  * Nginx reverse proxy
  * Wakeforce gateway
* **One `docker-compose.yml`**
* **One install script**
* **Zero application code changes**

All images are versioned and pulled from a public registry.

---

## Quick start

### 1. Clone the repository

```bash
git clone https://github.com/yourorg/idle-less.git
cd idle-less
```

### 2. Create configuration

```bash
cp .env.example .env
```

At minimum, configure:

```env
WF_PUBLIC_HOST=app.example.com
WF_UPSTREAM_URL=http://app:8080
```

### 3. Install and start

```bash
./install.sh
```

### 4. Configure DNS

Point `WF_PUBLIC_HOST` to the server running Idle-less.

That’s it.

---

## Application integration

Your application does **not** need to be aware of Idle-less.

The only requirement is network connectivity between the Wakeforce gateway and your app.

### Side-by-side Docker Compose (recommended)

If your application runs in a separate compose project:

```yaml
networks:
  wakeforce_internal:
    external: true
    name: wakeforce_internal
```

Attach your app service to that network.

No other changes are required.

---

## Wake mechanism (v1)

Idle-less v1 uses a **webhook-based wake mechanism**.

When the backend is unavailable:

* Wakeforce calls a configured webhook
* The webhook is responsible for starting or waking the backend
* Wakeforce retries readiness checks automatically

This keeps Idle-less infrastructure-agnostic and flexible.

---

## HTTP behavior during warm-up

While the backend is waking, clients receive a clear and explicit response:

```http
HTTP/1.1 202 Accepted
Retry-After: 3
Content-Type: application/json

{ "status": "warming_up" }
```

This avoids timeouts, improves UX, and plays well with browsers and caches.

---

## Health checks

The following endpoints remain available at all times:

* Reverse proxy: `GET /healthz`
* Wakeforce gateway: `GET /healthz`

These can be used by load balancers, monitors, or orchestration tools.

---

## Updating Idle-less

```bash
docker compose pull
docker compose up -d
```

Images are versioned and pinned. No implicit breaking changes.

---

## Design principles

Idle-less is built around a few core ideas:

* **Always-on control plane**
* **Sleepable, stateless backends**
* **Explicit warm-up semantics**
* **Minimal installation effort**
* **No hidden behavior**

If the backend is unavailable, Idle-less explains *why* — and fixes it.

---

## What Idle-less is not

Idle-less is intentionally focused.

It is **not**:

* a Kubernetes ingress controller
* a service mesh
* a replacement for autoscalers or load balancers
* a platform that manages your infrastructure for you

Instead, it fills the gap between users and sleeping services.

---

## Who is Idle-less for?

* Teams running scale-to-zero environments
* Developers tired of broken links during warm-up
* Ops teams who want explicit and predictable behavior
* Anyone who wants sleeping servers without sleeping endpoints

---

## Status

Idle-less is actively developed.
Version 1 is production-usable for controlled environments.

Feedback, issues, and ideas are welcome.

---

## License

All rights served

---

