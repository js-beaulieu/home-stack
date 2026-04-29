# Keycloak Assets

This directory owns repo-local Keycloak bootstrap and configuration assets.

Current stage:

- `scripts/` is reserved for small bootstrap helpers used by Ansible or local validation.
- Realm import, client setup, DCR policy, claim mapping, and broker setup are intentionally deferred to later stages.
- Secrets do not live here. Local development reads local-only values from `.env`; VPS provisioning renders secret values from Ansible vault into `/etc/home-stack.env`.

Target ownership:

- Ansible owns repeatable realm/bootstrap provisioning.
- Keycloak owns login, account, discovery, token, JWKS, and DCR behavior.
- Traefik owns gateway authentication and forwarded identity headers.
