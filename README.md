# home-stack

Docker Compose stack for a personal VPS. Traefik is the single entry point for all services. It terminates TLS and routes traffic to containers by label.

Keycloak is the planned authentication provider, but authentication is not implemented yet in this cleanup stage. Until the Keycloak gateway stage lands, public service routes are not protected by JWT validation.

## Architecture

```text
Internet (HTTPS :443)
        |
        v
   [Traefik]
        |  - TLS via Let's Encrypt
        |  - Routes by Docker labels
        |
        +--> tasks-api  (tasks.DOMAIN/api) - REST + MCP
        +--> future Keycloak auth host
        +--> future services

[Future Keycloak]
  - self-hosted OIDC provider
  - will issue JWTs for Traefik validation
  - will provide discovery, login, account console, and DCR
```

The target auth model remains gateway-owned: Traefik will validate Keycloak JWTs and forward identity headers to services. Individual services will trust forwarded identity headers and will not validate tokens themselves.

## Domain Convention

| Service | URL |
| --- | --- |
| Frontend | `appname.DOMAIN` |
| API / MCP | `appname.DOMAIN/api` |

Only one wildcard DNS record is required for this routing model:

- `*.DOMAIN`

## Environment

The deployed stack does not rely on a checked-in `.env` file. Ansible renders `/etc/home-stack.env` on the VPS from the values in `ansible/group_vars/all.yml` and the encrypted `ansible/group_vars/all.vault.yml`. The systemd unit loads that file before running `docker compose`.

## Local Tooling

Install the repo development tools and Git hooks with:

```sh
task install
```

Runtime Ansible dependencies are kept in the default uv dependency set. Linters and hook tooling live in the `dev` dependency group.

The pre-commit hook is managed by `lefthook` and runs:

```sh
task check
```

## Local Development

Local development uses the committed Compose overlay and plain HTTP Traefik config:

```sh
task dev:start
```

This starts the stack with:

- `docker-compose.yml`
- `docker-compose.local.yml`
- `traefik/local/traefik.yml`

Local routes use localhost-friendly hostnames and do not require wildcard DNS, Let's Encrypt, self-signed certificates, or `/etc/hosts` edits:

- `http://tasks.localhost/api`
- `http://auth.localhost/` reserved for the future Keycloak service

Postgres is internal-only in the base stack. Local development exposes it on `127.0.0.1:5432` so a local database client can connect without routing the database through Traefik.

The local overlay is for development only. Production provisioning continues to use the base Compose file and the VPS environment rendered by Ansible.

Follow local logs separately:

```sh
task dev:logs
```

Stop local containers without deleting volumes:

```sh
task dev:stop
```

## Manual Pre-Deploy Steps

These are the minimum manual steps before the first real deployment to a new VPS. The intended default is to let GitHub Actions perform the first provisioning run.

### 1. Generate the CI SSH keypair and make it available on the VM bootstrap user

```sh
ssh-keygen -t ed25519 -C "github-actions@home-stack" -f ~/.ssh/home-stack-ci
cat ~/.ssh/home-stack-ci.pub
```

Ideally, do this before provisioning the VM so the public key can be injected during VM creation through cloud-init or your provider's SSH key bootstrap mechanism.

The goal is that the initial `debian` user already has this public key in `~/.ssh/authorized_keys` before GitHub Actions tries to connect. If your provider or cloud-init did not install it during VM creation, add it manually after the VM comes up.

Use the public key in two places:

- make sure it is present for the initial `debian` user in `~/.ssh/authorized_keys`
- store the same public key in Ansible vault as `ci_ssh_public_key`

Use the private key as the GitHub Actions secret `VPS_SSH_KEY`.

The first provisioning path assumes the VM is reachable as `debian` with sudo access.

### 2. Enable the provider firewall

In OVH Control Panel, enable the VPS Network Firewall with these rules:

- priority `0`: `Allow` `TCP` destination port `22`
- priority `1`: `Allow` `TCP` destination port `80`
- priority `2`: `Allow` `TCP` destination port `443`
- final rule, e.g. priority `19`: `Deny` `IPv4`

Leave source IP and source port blank, leave TCP state as `None`, and leave fragments disabled.

Optionally enable OVH VPS snapshots before provisioning.

### 3. Point DNS at the VPS

For an IPv4-only setup, create these `A` records pointing at the VPS public IPv4:

- `DOMAIN`
- `*.DOMAIN`

The `DOMAIN` record handles the base hostname itself, for example `jsbeaulieu.com`. The wildcard record handles service subdomains such as `auth.DOMAIN` and `tasks.DOMAIN`. `*.DOMAIN` does not match `DOMAIN` itself, so both records are required.

It should resolve to the VPS public IP before expecting Traefik and Let's Encrypt to work.

### 4. Create and fill the encrypted vault

```sh
cd ansible
cp group_vars/all.vault.yml.example group_vars/all.vault.yml
ansible-vault encrypt group_vars/all.vault.yml
ansible-vault edit group_vars/all.vault.yml
```

Set all required values:

```yaml
domain: ""
acme_email: ""
ci_ssh_public_key: ""
postgres_db: ""
postgres_user: ""
postgres_password: ""
```

If you want non-interactive local runs, create `ansible/.vault_pass` with your vault password. That file is gitignored.

### 5. Add GitHub Actions secrets

Add these repository secrets:

- `VPS_SSH_KEY`
- `VPS_HOST`
- `ANSIBLE_VAULT_PASSWORD`

### 6. Push to `main` or run provisioning manually

Once the vault file is committed and the GitHub secrets exist:

- push a change to `main` that touches `ansible/**`, `docker-compose.yml`, or `traefik/**` to trigger `.github/workflows/provision.yml`
- or run `.github/workflows/provision.yml` with `workflow_dispatch`

The workflow generates `ansible/inventory.yml` dynamically from `VPS_HOST`, so no local inventory file is required.

## Manual Provisioning Fallback

If you need to provision from your own machine instead of GitHub Actions, run Ansible locally from `ansible/`.

Interactive vault prompt:

```sh
cd ansible
cp inventory.yml.example inventory.yml
ansible-playbook playbook.yml --ask-vault-pass
```

Or non-interactive if you created `ansible/.vault_pass`:

```sh
cd ansible
cp inventory.yml.example inventory.yml
ansible-playbook playbook.yml --vault-password-file .vault_pass
```

In either case, edit `ansible/inventory.yml` first so `ansible_host` points at the real VPS IP.

## What Provisioning Does

The Ansible playbook applies three roles in order:

1. `docker`
   Creates the `deploy` user, installs the CI public key for that user, installs Docker from Docker's apt repo, installs the Compose plugin, and adds `deploy` to the `docker` group.
2. `common`
   Upgrades packages, applies hostname settings, enables UFW for SSH and web traffic, configures fail2ban, enables unattended upgrades, and disables SSH password authentication.
3. `stack`
   Syncs the repo into `/home/deploy/home-stack`, renders `/etc/home-stack.env`, installs `home-stack.service`, and enables the service.

## Ongoing Deployment

- `.github/workflows/provision.yml` runs on changes to `ansible/**`, `docker-compose.yml`, or `traefik/**`
- the playbook updates `/home/deploy/home-stack` on the VPS and runs `docker compose up -d --remove-orphans` through `home-stack.service` when the repo checkout, environment file, or systemd unit changes
- Watchtower handles container image refreshes for services when upstream images are updated

## Postgres Backup And Restore

Use logical backups as the default Postgres backup path. They are portable across hosts and are the right fit while this stack has one small database service.

Create a backup from a running local stack:

```sh
docker compose -f docker-compose.yml -f docker-compose.local.yml exec -T postgres sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom' > postgres.dump
```

Restore that dump into a running local stack:

```sh
docker compose -f docker-compose.yml -f docker-compose.local.yml exec -T postgres sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists' < postgres.dump
```

Volume-level backups of `postgres-data` are a coarse fallback for whole-stack recovery, not the primary day-to-day backup model. Stop the stack before copying the volume data directly.

## Repo Structure

```text
home-stack/
  README.md
  docker-compose.yml
  docker-compose.local.yml
  keycloak/
    README.md
    scripts/
  traefik/
    traefik.yml
    local/
      traefik.yml
    dynamic/
      middlewares.yml
  ansible/
    playbook.yml
    local.yml
    inventory.yml.example
    group_vars/
      all.yml
      all.vault.yml.example
  .github/
    workflows/
      ci.yml
      provision.yml
  Taskfile.yml
  lefthook.yml
```
