locals {
  runtime_env = merge(
    {
      ACME_EMAIL                 = local.secrets.acme_email
      DOMAIN                     = local.secrets.domain
      KEYCLOAK_ADMIN_ALLOWED_IPS = local.secrets.keycloak_admin_allowed_ips
      KEYCLOAK_ADMIN_PASSWORD    = local.secrets.keycloak_admin_password
      KEYCLOAK_ADMIN_USERNAME    = local.keycloak_admin_username
      KEYCLOAK_HOSTNAME          = local.keycloak_public_url
      KEYCLOAK_ISSUER_URL        = "${local.keycloak_public_url}/realms/home-stack"
      LOG_DETAILED               = local.log_detailed
      LOG_FORMAT                 = local.log_format
      LOG_LEVEL                  = local.log_level
      OAUTH2_PROXY_CLIENT_SECRET = local.generated_secrets.oauth2_proxy_client_secret
      OAUTH2_PROXY_COOKIE_SECRET = local.generated_secrets.oauth2_proxy_cookie_secret
      OAUTH2_PROXY_COOKIE_SECURE = tostring(local.secrets.domain != "localhost")
      OAUTH2_PROXY_REDIRECT_URL  = local.oauth2_proxy_redirect_url
      PG_ADMIN_DATABASE          = local.pg_admin_database
      PG_ADMIN_PASSWORD          = local.secrets.pg_admin_password
      PG_ADMIN_USERNAME          = local.pg_admin_username
      PG_KEYCLOAK_DATABASE       = local.pg_keycloak_database
      PG_KEYCLOAK_PASSWORD       = local.generated_secrets.pg_keycloak_password
      PG_KEYCLOAK_USERNAME       = local.pg_keycloak_username
      POSTGRES_PORT              = "5432"
      TASKS_PORT                 = "8080"
      TRAEFIK_TRUSTED_PROXY_IPS  = local.traefik_trusted_proxy_ips
    },
    var.environment == "local" ? { LOCAL_SMOKE_USER_PASSWORD = local.generated_secrets.local_smoke_user_password } : {}
  )

  runtime_env_lines = [
    for key in sort(keys(local.runtime_env)) :
    "${key}=${replace(tostring(local.runtime_env[key]), "\n", "")}"
  ]
}

resource "local_sensitive_file" "runtime_env" {
  filename = var.runtime_env_file
  content  = "${join("\n", local.runtime_env_lines)}\n"
}
