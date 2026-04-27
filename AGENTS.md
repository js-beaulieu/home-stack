# home-stack

Docker Compose stack for a personal VPS. Traefik is the single entry point for all services — it handles TLS, JWT validation, and routes requests to the right container.

## Architecture

```
Internet (HTTPS :443)
        │
        ▼
   [Traefik]
        │  • TLS via Let's Encrypt
        │  • JWT validation (Zitadel JWKS) → injects X-User-ID, X-User-Email, X-User-Name
        │  • Routes by Docker container labels
        │
        ├──▶ auth-api   (auth.DOMAIN/api)  — OAuth2 discovery + DCR facade
        ├──▶ tasks-api  (tasks.DOMAIN/api) — REST + MCP
        └──▶ future services

[Zitadel Cloud]  ← external OIDC provider, zero-maintenance
                   issues JWTs; auth-api proxies discovery and handles DCR
```

Auth is handled entirely at the gateway. Individual services trust forwarded identity headers — they never validate tokens themselves.

## Auth flow (MCP client connecting for the first time)

1. Client hits `auth.DOMAIN/api/.well-known/oauth-authorization-server`
2. auth-api returns discovery doc with Zitadel endpoints + `registration_endpoint: https://auth.DOMAIN/api/register`
3. Client POSTs to `auth.DOMAIN/api/register` with a valid Zitadel Bearer JWT — auth-api calls Zitadel Management API to register redirect URI, returns `mcp` client ID
4. Client redirects user to Zitadel's `authorization_endpoint` with PKCE
5. User authenticates in Zitadel, code returned to client
6. Client exchanges code at Zitadel's `token_endpoint` → JWT
7. Client calls `tasks.DOMAIN/api/...` with `Authorization: Bearer <jwt>`
8. Traefik validates JWT via JWKS, injects identity headers, forwards request

## Domain convention

Services follow a consistent subdomain pattern under the base `DOMAIN`:

| Service | URL |
|---|---|
| Frontend | `appname.DOMAIN` |
| API / MCP | `appname.DOMAIN/api` |

Only `*.DOMAIN` wildcard DNS is needed for this routing model.

## Route types

| Type | Traefik | Middleware |
|---|---|---|
| Public-facing API | yes | `jwt-auth` |
| Health | yes | none (priority 10) |
| Internal service-to-service | no | Docker `internal` network |
| Personal admin | yes | IP allowlist |

## Adding a new service

1. Add a `services:` block in `docker-compose.yml`
2. Attach to `public` network (and `internal` if it calls other services)
3. Add Traefik labels following the existing pattern (protected router + health router)
4. Environment variables go in the host's `/etc/environment` — no `.env` files

## Commands

```bash
task install            # install uv-managed tooling and the pre-commit hook
task check              # format + lint + validate
task format             # yamllint on repo YAML files
task lint               # yamllint + ansible-lint
task validate           # ansible syntax + docker compose config
```

`lefthook` runs `task check` on `pre-commit`.

## Deployment

**App image updates:** Watchtower polls `ghcr.io` every 5 minutes and auto-restarts containers on new images.

**Stack config changes:** `.github/workflows/provision.yml` runs on `main` changes to `ansible/**`, `docker-compose.yml`, or `traefik/**`, then applies the Ansible playbook. The playbook updates the checkout on the VPS and runs `docker compose up -d --remove-orphans` through `home-stack.service`.

## Environment variables

Set on the VPS host, referenced in `docker-compose.yml` via `${VAR}`:

| Variable | Description |
|---|---|
| `DOMAIN` | Base domain (e.g. `jsbeaulieu.com`) |
| `ZITADEL_ISSUER` | Zitadel issuer URL (e.g. `https://home-stack-fpczvt.us1.zitadel.cloud`) |
| `ZITADEL_AUTH_URL` | Zitadel authorization endpoint |
| `ZITADEL_TOKEN_URL` | Zitadel token endpoint |
| `ZITADEL_JWKS_URL` | Zitadel JWKS endpoint |
| `ZITADEL_MCP_CLIENT_ID` | Zitadel `mcp` app client ID returned on every DCR registration |
| `TASKS_PORT` | Internal port for tasks-api (default `8080`) |
| `AUTH_PORT` | Internal port for auth-api (default `8080`) |
| `LOG_FORMAT` | `json` or `text` |
| `LOG_LEVEL` | `debug`, `info`, `warn`, `error` |
| `ACME_EMAIL` | Email for Let's Encrypt certificate notifications |

## Structure

```
home-stack/
  docker-compose.yml
  traefik/
    traefik.yml          # static config: entrypoints, plugin declaration
    dynamic/
      middlewares.yml    # jwt-auth middleware definition
  ansible/
    playbook.yml         # VPS provisioning and stack apply
  .github/
    workflows/
      ci.yml             # repo checks on PRs to main
      provision.yml      # apply VPS config on main changes
  Taskfile.yml
  lefthook.yml
  AGENTS.md
  CLAUDE.md -> AGENTS.md
```


<claude-mem-context>
# Memory Context

# [home-stack] recent context, 2026-04-23 12:53am EDT

No previous sessions found.
</claude-mem-context>
