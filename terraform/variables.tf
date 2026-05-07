variable "environment" {
  type = string
}

variable "secrets_file" {
  type = string
}

variable "local_override_file" {
  type    = string
  default = ""
}

variable "runtime_env_file" {
  type = string
}

variable "postgres_host" {
  type = string
}

variable "postgres_port" {
  type = number
}

variable "keycloak_port" {
  type        = number
  description = "Host port for the Keycloak admin API tunnel (18080 for prod, 8080 for local)"
}
