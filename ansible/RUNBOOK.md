# home-stack Ansible Runbook

## Pre-flight: manual, one-time per VPS

Generate the CI deploy keypair:

```sh
ssh-keygen -t ed25519 -C "github-actions@home-stack" -f ~/.ssh/home-stack-ci
```

Add the private key to GitHub Actions as `VPS_SSH_KEY`.

Add the public key to the initial VPS user, usually `debian`, through the OVH console or during first login:

```sh
cat ~/.ssh/home-stack-ci.pub
```

Add the same public key content to the Ansible vault as `ci_ssh_public_key`.

In OVH Control Panel, enable the VPS Network Firewall and allow TCP `22`, `80`, and `443`. The implicit deny-all covers everything else.

Optionally enable OVH VPS snapshots before provisioning.

Confirm SSH key authentication works before running Ansible:

```sh
ssh debian@VPS_IP
```

## First-Time Ansible Setup

Create a local inventory and fill in the VPS IP:

```sh
cd ansible
cp inventory.yml.example inventory.yml
```

Create and encrypt the vault file:

```sh
cp group_vars/all.vault.yml.example group_vars/all.vault.yml
ansible-vault encrypt group_vars/all.vault.yml
ansible-vault edit group_vars/all.vault.yml
```

Set every vault value before provisioning:

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

If you want non-interactive local runs, put the vault password in `ansible/.vault_pass`. This file is gitignored.

## Running

Run the full playbook:

```sh
cd ansible
ansible-playbook playbook.yml --vault-password-file .vault_pass
```

For an interactive vault prompt:

```sh
cd ansible
ansible-playbook playbook.yml --ask-vault-pass
```

## What The Playbook Does

The `docker` role creates the `deploy` user, installs the CI deploy key, installs Docker from Docker's official apt repository, installs the Docker Compose plugin, and adds `deploy` to the Docker group so the service can run Compose without root.

The `common` role upgrades packages, applies hostname settings through cloud-init-compatible files, enables UFW for SSH/HTTP/HTTPS only, configures fail2ban for SSH, enables unattended security upgrades, and disables SSH password authentication after the deploy key is installed.

The `stack` role clones this repository to `/home/deploy/home-stack`, renders `/etc/home-stack.env`, installs `home-stack.service`, and enables the systemd service. The system service is managed by root but runs the Compose process as `deploy`.

## GitHub Actions Provisioning

The `Provision VPS` workflow runs on pushes to `main` that affect Ansible, Compose, or Traefik files, and can also be started manually.

Required GitHub Actions secrets:

```text
VPS_SSH_KEY
VPS_HOST
ANSIBLE_VAULT_PASSWORD
```

The workflow generates `ansible/inventory.yml` dynamically from `VPS_HOST`, so the real VPS IP is not committed.
