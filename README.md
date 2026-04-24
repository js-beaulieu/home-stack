# home-stack

Docker Compose stack for a personal VPS. Traefik is the single entry point for all services. It terminates TLS, validates JWTs against Zitadel JWKS, injects identity headers, and routes traffic to containers by label.

## Architecture

```text
Internet (HTTPS :443)
        |
        v
   [Traefik]
        |  - TLS via Let's Encrypt
        |  - JWT validation via Zitadel JWKS
        |  - Injects X-User-ID, X-User-Email, X-User-Name
        |  - Routes by Docker labels
        |
        +--> auth-api   (auth.api.DOMAIN)  - OAuth2 discovery + DCR facade
        +--> tasks-api  (tasks.api.DOMAIN) - REST + MCP
        +--> future services

[Zitadel Cloud]
  - external OIDC provider
  - issues JWTs
  - auth-api proxies discovery and handles DCR
```

Auth is handled entirely at the gateway. Individual services trust forwarded identity headers and do not validate tokens themselves.

## Domain Convention

| Service | URL |
| --- | --- |
| Frontend | `appname.DOMAIN` |
| API / MCP | `appname.api.DOMAIN` |

Two wildcard DNS records are required:

- `*.DOMAIN`
- `*.api.DOMAIN`

## Environment

The deployed stack does not rely on a checked-in `.env` file. Ansible renders `/etc/home-stack.env` on the VPS from the values in `ansible/group_vars/all.yml` and the encrypted `ansible/group_vars/all.vault.yml`. The systemd unit loads that file before running `docker compose`.

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

### 2. Point DNS at the VPS

Create wildcard DNS records for:

- `*.DOMAIN`
- `*.api.DOMAIN`

Both should resolve to the VPS public IP before expecting Traefik and Let's Encrypt to work.

### 3. Create and fill the encrypted vault

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
zitadel_issuer: ""
zitadel_auth_url: ""
zitadel_token_url: ""
zitadel_jwks_url: ""
zitadel_mcp_client_id: ""
ci_ssh_public_key: ""
```

If you want non-interactive local runs, create `ansible/.vault_pass` with your vault password. That file is gitignored.

### 4. Add GitHub Actions secrets

Add these repository secrets:

- `VPS_SSH_KEY`
- `VPS_HOST`
- `ANSIBLE_VAULT_PASSWORD`

### 5. Trigger first-time provisioning from GitHub

Once the vault file is committed and the GitHub secrets exist, trigger provisioning from GitHub:

- run `.github/workflows/provision.yml` with `workflow_dispatch`, or
- push a change to `main` that touches `ansible/**`, `docker-compose.yml`, or `traefik/**`

The workflow generates `ansible/inventory.yml` dynamically from `VPS_HOST`, so no local inventory file is required.

### 6. Push once provisioning succeeds

After the first successful provision:

- push to `main` to trigger `.github/workflows/provision.yml` for infra changes
- push to `main` to trigger `.github/workflows/deploy.yml` for stack updates

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
   Clones the repo into `/home/deploy/home-stack`, renders `/etc/home-stack.env`, installs `home-stack.service`, and enables the service.

## Ongoing Deployment

- `.github/workflows/provision.yml` runs on changes to `ansible/**`, `docker-compose.yml`, or `traefik/**`
- `.github/workflows/deploy.yml` runs on pushes to `main` and SSHes into the VPS as `deploy`

## Repo Structure

```text
home-stack/
  README.md
  docker-compose.yml
  traefik/
    traefik.yml
    dynamic/
      middlewares.yml
  ansible/
    RUNBOOK.md
    playbook.yml
    inventory.yml.example
    group_vars/
      all.yml
      all.vault.yml.example
  .github/
    workflows/
      check.yml
      provision.yml
      deploy.yml
```
