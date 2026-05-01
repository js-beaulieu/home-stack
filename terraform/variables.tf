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

variable "keycloak_base_url_override" {
  type    = string
  default = ""
}
