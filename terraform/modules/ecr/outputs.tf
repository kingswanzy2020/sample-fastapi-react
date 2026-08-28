output "registry_url" {
  description = "Account registry hostname, e.g. 123456789012.dkr.ecr.us-east-1.amazonaws.com."
  value       = local.registry_url
}

output "registry_prefix" {
  description = <<-EOT
    Value to set as REGISTRY for docker-compose. Combined with the compose file's
    "$${REGISTRY}/backend", this resolves to the full repository URL.
  EOT
  value       = "${local.registry_url}/${local.name_prefix}"
}

output "repository_urls" {
  description = "Map of image name to full repository URL."
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

output "repository_arns" {
  description = "Map of image name to repository ARN. Use these to scope a CI push policy."
  value       = { for k, v in aws_ecr_repository.this : k => v.arn }
}

output "docker_login_command" {
  description = "Authenticate a local Docker daemon against this registry."
  value       = "aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${local.registry_url}"
}
