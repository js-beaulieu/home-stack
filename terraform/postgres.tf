locals {
  pg_keycloak_username = "keycloak"
  pg_keycloak_database = "keycloak"
  pg_admin_username    = "home_stack_admin"
  pg_admin_database    = "postgres"
}

resource "postgresql_role" "keycloak" {
  name     = local.pg_keycloak_username
  login    = true
  password = local.generated_secrets.pg_keycloak_password

  lifecycle {
    prevent_destroy = true
  }
}

resource "postgresql_database" "keycloak" {
  name  = local.pg_keycloak_database
  owner = postgresql_role.keycloak.name

  lifecycle {
    prevent_destroy = true
  }
}
