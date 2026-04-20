# home-stack

Docker Compose stack for a personal VPS. Traefik is the single entry point for all services — it handles TLS, JWT validation, and routes requests to the right container.

## Architecture

```
Internet (HTTPS :443)
        │
        ▼
   [Traefik]
        │  • TLS via Let's Encrypt
        │  • JWT validation (Zitadel Cloud JWKS) → injects X-User-ID, X-User-Email, X-User-Name
        │  • Routes by Docker container labels
        │
        ├──▶ tasks-api
        └──▶ future services

[Zitadel Cloud]  ← external auth provider, zero-maintenance
```

Auth is handled entirely at the gateway. Individual services trust forwarded identity headers — they never validate tokens themselves.

## Route types

| Type | Traefik | Middleware |
|---|---|---|
| Public-facing API | yes | `jwt-auth` |
| Health / `.well-known` | yes | none (higher router priority) |
| Internal service-to-service | no | Docker `internal` network |
| Personal admin | yes | IP allowlist |

## Adding a new service

1. Add a `services:` block in `docker-compose.yml`
2. Attach to `public` network (and `internal` if it calls other services)
3. Add Traefik labels following the existing pattern (protected router + public router for health)
4. Environment variables go in the host's `/etc/environment` — no `.env` files

## Deployment

**App image updates:** Watchtower polls `ghcr.io` every 5 minutes and auto-restarts containers on new images.

**Stack config changes:** push to `main` → GitHub Actions SSHes into VPS → `docker compose pull && docker compose up -d`.

## Environment variables

Set on the VPS host, referenced in `docker-compose.yml` via `${VAR}`:

| Variable | Description |
|---|---|
| `DOMAIN` | Base domain (e.g. `example.com`) |
| `ZITADEL_ISSUER` | Zitadel issuer URL |
| `ZITADEL_JWKS_URL` | Zitadel JWKS endpoint for JWT validation |
| `TASKS_PORT` | Internal port for tasks-api |
| `LOG_FORMAT` | `json` or `text` |
| `LOG_LEVEL` | `debug`, `info`, `warn`, `error` |

## Structure

```
home-stack/
  docker-compose.yml
  traefik/
    traefik.yml          # static config: entrypoints, plugin declaration
    dynamic/
      middlewares.yml    # jwt-auth middleware definition
  .github/
    workflows/
      deploy.yml         # SSH deploy on push to main
  CLAUDE.md
```
