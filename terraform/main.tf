terraform {
  required_version = ">= 1.11.0"

  required_providers {
    keycloak = {
      source  = "keycloak/keycloak"
      version = ">= 5.0.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.5.0"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = ">= 1.26.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0"
    }
  }
}

provider "keycloak" {
  client_id = "admin-cli"
  username  = local.secrets.keycloak_admin_username
  password  = local.secrets.keycloak_admin_password
  realm     = "master"
  url       = local.keycloak_base_url
}

provider "postgresql" {
  host            = var.postgres_host
  port            = var.postgres_port
  database        = local.secrets.pg_admin_database
  username        = local.secrets.pg_admin_username
  password        = local.secrets.pg_admin_password
  sslmode         = "disable"
  connect_timeout = 15
  superuser       = true
}
