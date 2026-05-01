# home-stack

`home-stack` is the VPS-facing infrastructure repo for the personal stack behind Traefik.

## Ownership

- Traefik remains the public TLS and routing entry point.
- Keycloak is the identity provider and owns login, brokering, account linking, and token issuance.
- `oauth2-proxy` stays behind Traefik and only handles browser-session auth.
- API and MCP routes stay on gateway JWT validation.
- Services behind the gateway trust forwarded identity headers instead of validating tokens themselves.
- OpenTofu owns service-level provisioning and generated runtime secrets.
- Ansible is host-only. It syncs the repo, installs the systemd unit, writes `/etc/home-stack.env`, and applies the stack.
- Watchtower only updates first-party images that opt in with labels.

Mixed ownership is not allowed during this migration. Runtime env, Postgres objects, and Keycloak realm/client state should not be managed by both Ansible and OpenTofu.

## Repo Layout

```text
home-stack/
  docker/
    docker-compose.yml
    docker-compose.local.yml
  terraform/
    *.tf
    envs/
  secrets/
    local.defaults.yaml
    prod.sops.yaml
  ansible/
    bootstrap.yml
    site.yml
    inventory/
  traefik/
  Taskfile.yml
```

## Tooling

Repo-managed tooling:

- `uv` manages Python dependencies for Ansible, local scripts, and validation.
- `task` is the command entrypoint.

External prerequisites:

- local development: Docker, Docker Compose plugin, OpenTofu
- production workflow or manual secrets work: `sops` and `age`

Install repo-managed tooling with:

```sh
task install
```

## Secrets

- shared local defaults live in `secrets/local.defaults.yaml`
- machine-local overrides belong in the gitignored `secrets/local.override.yaml`
- production operator inputs belong in `secrets/prod.sops.yaml`
- OpenTofu-generated secrets stay in OpenTofu state when OpenTofu owns their lifecycle end to end

`secrets/prod.sops.yaml` is committed as a structure template. Replace it with a real SOPS-encrypted file before production use.

## Local Development

The steady-state local loop is:

```sh
task local:up
task local:provision
task local:verify
task local:logs
```

What each step does:

- `task local:up` renders `.generated/local/home-stack.env` from `secrets/local.defaults.yaml`, optional `secrets/local.override.yaml`, and OpenTofu-generated secrets, then starts the stack
- `task local:provision` waits for Postgres and Keycloak, then applies OpenTofu provisioning for Postgres roles, the Keycloak realm, clients, smoke user, DCR policy, and optional Google broker config
- `task local:verify` runs the repo-owned smoke test
- `task local:logs` follows logs

Stop the stack without deleting volumes:

```sh
task local:down
```

Reset local state, generated env, and volumes to zero:

```sh
task local:reset
```

Local routes:

- `http://tasks.localhost/api/health`
- `http://tasks.localhost/api/users/me`
- `http://auth.localhost/`
- `http://auth.localhost/realms/home-stack/.well-known/openid-configuration`
- `http://private.localhost/`

The local smoke test verifies:

- public health
- Keycloak reachability
- OIDC discovery and JWKS
- anonymous DCR
- one protected `tasks-api` route with a real Keycloak token
- browser-auth redirect behavior through `oauth2-proxy`

## Ansible

`ansible/bootstrap.yml` is host bootstrap only:

- install Docker and Compose
- create the `deploy` user
- install the repo-owned systemd unit
- sync the repo checkout

`ansible/site.yml` is host apply only:

- sync the repo checkout
- copy a rendered runtime env file to `/etc/home-stack.env`
- reload the `home-stack` systemd unit

Manual syntax validation:

```sh
cd ansible
uv run --project .. --frozen --no-dev ansible-playbook --inventory localhost, --syntax-check bootstrap.yml
uv run --project .. --frozen --no-dev ansible-playbook --inventory localhost, --syntax-check site.yml
```

## OpenTofu

OpenTofu currently owns:

- runtime env rendering
- generated Keycloak DB password
- generated `oauth2-proxy` client secret
- generated `oauth2-proxy` cookie secret
- Keycloak Postgres role and database
- the `home-stack` realm
- the `home-stack-cli` and `oauth2-proxy` clients
- anonymous DCR policy components
- optional Google identity provider wiring
- the local smoke user

The Keycloak provider-backed resources are handled directly through the official `keycloak/keycloak` provider. Anonymous DCR policy components still use a small REST fallback under `terraform/scripts/upsert_keycloak_dcr.py`.

## Workflows

- `ci.yml`: PR checks
- `build.yml`: reusable or push-triggered repo checks
- `provision.yml`: render production runtime inputs and OpenTofu state prerequisites
- `deploy.yml`: orchestrate build, runtime-input preparation, stack apply, and post-start OpenTofu provisioning

Production delivery is GitHub Actions first. The normal path is:

1. render `.generated/prod/home-stack.env` from decrypted production secrets plus OpenTofu-generated values
2. push that env file to the VPS with `ansible/site.yml`
3. start or reload the stack
4. finish OpenTofu service provisioning against live Keycloak and Postgres

## Validation

Run the full repo check suite with:

```sh
task check
```
