resource "postgresql_role" "keycloak" {
  name     = local.secrets.pg_keycloak_username
  login    = true
  password = local.generated_secrets.pg_keycloak_password
}

resource "postgresql_database" "keycloak" {
  name  = local.secrets.pg_keycloak_database
  owner = postgresql_role.keycloak.name
}
