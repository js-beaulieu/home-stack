# home-stack

Docker Compose stack for a personal VPS. Traefik is the single entry point for all services — it handles TLS and routes requests to the right container.

Keycloak is the planned authentication provider, but authentication is not implemented yet in this cleanup stage. Do not describe the current stack as protected by JWT validation until the Keycloak gateway stage lands.

## Architecture

```
Internet (HTTPS :443)
        │
        ▼
   [Traefik]
        │  • TLS via Let's Encrypt
        │  • Routes by Docker container labels
        │
        ├──▶ tasks-api  (tasks.DOMAIN/api) — REST + MCP
        ├──▶ future Keycloak auth host
        └──▶ future services

[Future Keycloak]  ← self-hosted OIDC provider
                    will issue JWTs for Traefik validation and provide login, account, discovery, and DCR
```

The target auth model is handled entirely at the gateway. Traefik will validate Keycloak JWTs and forward identity headers; individual services will trust forwarded identity headers and never validate tokens themselves.

## Planned auth flow

1. Keycloak will serve OIDC discovery, authorization, token, JWKS, account, and DCR endpoints on `auth.DOMAIN`.
2. MCP clients will register through Keycloak DCR.
3. Users will authenticate in Keycloak.
4. Clients will call service APIs with Keycloak access tokens.
5. Traefik will validate those tokens against Keycloak JWKS, inject `X-User-ID`, `X-User-Email`, and `X-User-Name`, then forward requests.

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
| Public-facing API | yes | none until Keycloak JWT validation lands |
| Health | yes | none (priority 10) |
| Internal service-to-service | no | Docker `internal` network |
| Personal admin | yes | future Keycloak admin routes on the normal Keycloak host, IP-restricted |

## Adding a new service

1. Add a `services:` block in `docker-compose.yml`
2. Attach to `public` network (and `internal` if it calls other services)
3. Add Traefik labels following the existing pattern (protected router + health router)
4. Environment variables go in the host's `/etc/environment` — no `.env` files

## Commands

```bash
task install            # install uv-managed dev tooling and the pre-commit hook
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
| `TASKS_PORT` | Internal port for tasks-api (default `8080`) |
| `LOG_FORMAT` | `json` or `text` |
| `LOG_LEVEL` | `debug`, `info`, `warn`, `error` |
| `ACME_EMAIL` | Email for Let's Encrypt certificate notifications |

## Structure

```
home-stack/
  docker-compose.yml
  traefik/
    traefik.yml          # static config: entrypoints and providers
    dynamic/
      middlewares.yml    # shared route middleware definitions
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
