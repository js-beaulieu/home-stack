locals {
  keycloak_admin_username           = "admin"
  keycloak_bootstrap_admin_username = "temp-admin"
  keycloak_master_realm_id          = "master"

  dcr_trusted_hosts = ["localhost", "claude.ai", "claude.com"]
  dcr_web_origins   = ["https://claude.ai", "https://claude.com"]
}

resource "keycloak_realm" "home_stack" {
  realm                          = "home-stack"
  display_name                   = "home-stack"
  enabled                        = true
  registration_allowed           = false
  login_with_email_allowed       = true
  duplicate_emails_allowed       = false
  reset_password_allowed         = true
  remember_me                    = true
  edit_username_allowed          = false
  verify_email                   = false
  first_broker_login_flow        = "first broker login"
  default_default_client_scopes  = ["basic", "profile", "email", "roles"]
  default_optional_client_scopes = []

  lifecycle {
    prevent_destroy = true
  }
}

resource "keycloak_openid_client" "home_stack_cli" {
  realm_id                     = keycloak_realm.home_stack.id
  client_id                    = "home-stack-cli"
  name                         = "home-stack-cli"
  enabled                      = true
  access_type                  = "PUBLIC"
  standard_flow_enabled        = false
  direct_access_grants_enabled = true
  valid_redirect_uris          = []
  web_origins                  = []
}

resource "keycloak_openid_client" "oauth2_proxy" {
  realm_id                     = keycloak_realm.home_stack.id
  client_id                    = "oauth2-proxy"
  name                         = "oauth2-proxy"
  enabled                      = true
  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = true
  direct_access_grants_enabled = false
  full_scope_allowed           = true
  client_secret                = local.generated_secrets.oauth2_proxy_client_secret
  valid_redirect_uris          = [local.oauth2_proxy_redirect_url]
  web_origins                  = [local.secrets.domain == "localhost" ? "http://private.localhost" : "https://private.${local.secrets.domain}"]
  base_url                     = local.secrets.domain == "localhost" ? "http://private.localhost" : "https://private.${local.secrets.domain}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "keycloak_user" "local_smoke_user" {
  count          = local.local_smoke_user.username != "" ? 1 : 0
  realm_id       = keycloak_realm.home_stack.id
  username       = local.local_smoke_user.username
  email          = local.local_smoke_user.email
  enabled        = true
  email_verified = true
  first_name     = local.local_smoke_user.first_name
  last_name      = local.local_smoke_user.last_name

  initial_password {
    value     = local.generated_secrets.local_smoke_user_password
    temporary = false
  }
}

resource "keycloak_oidc_google_identity_provider" "google" {
  count                         = local.google_identity_provider.enabled ? 1 : 0
  realm                         = keycloak_realm.home_stack.realm
  alias                         = "google"
  enabled                       = true
  client_id                     = local.google_identity_provider.client_id
  client_secret                 = local.google_identity_provider.client_secret
  first_broker_login_flow_alias = "first broker login"
  gui_order                     = "10"
  hosted_domain                 = local.google_identity_provider.hosted_domain
  store_token                   = true
  sync_mode                     = "IMPORT"
  trust_email                   = true
}

# The permanent admin is created out-of-band by scripts/bootstrap_keycloak_admin.py
# (run before tofu apply) and then imported into state so Terraform owns it.
# Import IDs: keycloak_user → master/{uuid}, keycloak_user_roles → master/{uuid}.
data "keycloak_role" "master_admin" {
  realm_id = local.keycloak_master_realm_id
  name     = "admin"
}

resource "keycloak_user" "keycloak_admin" {
  realm_id       = local.keycloak_master_realm_id
  username       = local.keycloak_admin_username
  enabled        = true
  email_verified = true

  initial_password {
    value     = local.secrets.keycloak_admin_password
    temporary = false
  }
}

resource "keycloak_user_roles" "keycloak_admin" {
  realm_id = local.keycloak_master_realm_id
  user_id  = keycloak_user.keycloak_admin.id
  role_ids = [data.keycloak_role.master_admin.id]
}

resource "terraform_data" "keycloak_dcr" {
  triggers_replace = [
    sha256(jsonencode({
      client_registration_policy_provider_type = "org.keycloak.services.clientregistration.policy.ClientRegistrationPolicy"
      realm                                    = keycloak_realm.home_stack.realm
      trusted_hosts                            = local.dcr_trusted_hosts
      web_origins                              = local.dcr_web_origins
    }))
  ]

  provisioner "local-exec" {
    command = <<-EOT
      python3 scripts/upsert_keycloak_dcr.py \
        --base-url '${local.keycloak_provider_url}' \
        --realm '${keycloak_realm.home_stack.realm}' \
        --admin-username '${local.keycloak_admin_username}' \
        --admin-password '${local.secrets.keycloak_admin_password}' \
        --trusted-hosts '${jsonencode(local.dcr_trusted_hosts)}' \
        --web-origins '${jsonencode(local.dcr_web_origins)}'
    EOT
  }

  depends_on = [keycloak_realm.home_stack]
}
