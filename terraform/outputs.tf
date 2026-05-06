output "runtime_env_file" {
  value = local_sensitive_file.runtime_env.filename
}

output "local_smoke_user_password" {
  value     = local.generated_secrets.local_smoke_user_password
  sensitive = true
}
