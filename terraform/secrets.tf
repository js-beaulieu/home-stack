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

  keycloak_base_url = (
    var.keycloak_base_url_override != ""
    ? var.keycloak_base_url_override
    : (
      local.secrets.domain == "localhost"
      ? "http://auth.localhost"
      : "https://auth.${local.secrets.domain}"
    )
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
    local_smoke_user_password  = coalesce(trimspace(local.local_smoke_user.password), random_password.local_smoke_user_password.result)
  }
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
  length  = 24
  special = false
}
