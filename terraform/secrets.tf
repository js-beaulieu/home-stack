locals {
  base_secrets = yamldecode(file(var.secrets_file))
  override_secrets = (
    var.local_override_file != "" && fileexists(var.local_override_file)
    ? yamldecode(file(var.local_override_file))
    : {}
  )

  secrets = merge(local.base_secrets, local.override_secrets)

  local_smoke_user = merge(
    {
      username   = ""
      email      = ""
      first_name = ""
      last_name  = ""
      password   = ""
    },
    try(local.secrets.local_smoke_user, {})
  )

  google_identity_provider = merge(
    {
      enabled       = false
      client_id     = ""
      client_secret = ""
      hosted_domain = ""
    },
    try(local.secrets.google_identity_provider, {})
  )

  # Direct URL for the Terraform Keycloak provider — always the tunnel address,
  # bypasses Traefik and its admin IP allowlist.
  keycloak_provider_url = "http://127.0.0.1:${var.keycloak_port}"

  # Public-facing URL for runtime config (KEYCLOAK_HOSTNAME, KEYCLOAK_ISSUER_URL).
  # Used by Keycloak itself and oauth2-proxy — never for the Terraform provider.
  keycloak_public_url = (
    local.secrets.domain == "localhost"
    ? "http://auth.localhost"
    : "https://auth.${local.secrets.domain}"
  )

  oauth2_proxy_redirect_url = (
    local.secrets.domain == "localhost"
    ? "http://private.localhost/oauth2/callback"
    : "https://private.${local.secrets.domain}/oauth2/callback"
  )

  generated_secrets = {
    pg_keycloak_password       = random_password.pg_keycloak_password.result
    oauth2_proxy_client_secret = random_password.oauth2_proxy_client_secret.result
    oauth2_proxy_cookie_secret = base64encode(random_password.oauth2_proxy_cookie_secret.result)
    local_smoke_user_password = (
      var.environment == "local"
      ? coalesce(trimspace(local.local_smoke_user.password), random_password.local_smoke_user_password[0].result)
      : ""
    )
  }

  log_format   = try(local.secrets.log_format, "json")
  log_level    = try(local.secrets.log_level, "info")
  log_detailed = try(tostring(local.secrets.log_detailed), "false")
}

resource "random_password" "pg_keycloak_password" {
  length  = 32
  special = false
}

resource "random_password" "oauth2_proxy_client_secret" {
  length  = 48
  special = false
}

resource "random_password" "oauth2_proxy_cookie_secret" {
  length  = 32
  special = false
}

resource "random_password" "local_smoke_user_password" {
  count   = var.environment == "local" ? 1 : 0
  length  = 24
  special = false
}
