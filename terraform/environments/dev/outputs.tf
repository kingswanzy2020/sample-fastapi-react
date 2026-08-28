# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

output "vpc_id" {
  description = "VPC ID."
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs."
  value       = module.network.private_subnet_ids
}

# ---------------------------------------------------------------------------
# Compute
# ---------------------------------------------------------------------------

output "instance_id" {
  description = "EC2 instance ID."
  value       = module.compute.instance_id
}

output "instance_public_ip" {
  description = "Elastic IP of the application instance."
  value       = module.compute.public_ip
}

output "app_url" {
  description = "URL the application is served from."
  value       = "http://${module.compute.public_ip}"
}

output "ssm_command" {
  description = "Open a shell with no open port and no SSH key."
  value       = "aws ssm start-session --target ${module.compute.instance_id} --region ${var.aws_region}"
}

output "ssh_command" {
  description = "SSH command, or a note if SSH is disabled."
  value = length(var.ssh_allowed_cidrs) > 0 && var.key_name != null ? (
    "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${module.compute.public_ip}"
  ) : "SSH disabled -- use the ssm_command output instead"
}

# ---------------------------------------------------------------------------
# Registry
# ---------------------------------------------------------------------------

output "ecr_registry_prefix" {
  description = "Value of REGISTRY for docker-compose. Combined with the compose file's $${REGISTRY}/backend this is the full image path."
  value       = module.ecr.registry_prefix
}

output "ecr_repository_urls" {
  description = "Full URL of each image repository."
  value       = module.ecr.repository_urls
}

output "docker_login_command" {
  description = "Authenticate your local Docker daemon against this registry."
  value       = module.ecr.docker_login_command
}

# ---------------------------------------------------------------------------
# Secrets
# ---------------------------------------------------------------------------

output "app_secret_arn" {
  description = "ARN of the application secret. Terraform created it empty; you set the value."
  value       = aws_secretsmanager_secret.app.arn
}

output "set_app_secret_command" {
  description = "Run this once, before the first deploy. The value never enters Terraform state."
  value       = <<-EOT
    aws secretsmanager put-secret-value \
      --secret-id ${aws_secretsmanager_secret.app.arn} \
      --region ${var.aws_region} \
      --secret-string "{\"SECRET_KEY\":\"$(openssl rand -hex 32)\",\"POSTGRES_PASSWORD\":\"$(openssl rand -base64 32 | tr -d '/+=')\"}"
  EOT
}

# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------

output "db_endpoint" {
  description = "RDS endpoint, or null when the database is disabled."
  value       = var.create_database ? module.database[0].endpoint : null
}

output "db_secret_arn" {
  description = "ARN of the RDS-managed master password secret."
  value       = var.create_database ? module.database[0].master_user_secret_arn : null
}

output "db_password_command" {
  description = "Read the RDS master password. The deploy script does this automatically; this is for debugging."
  value = var.create_database ? (
    "aws secretsmanager get-secret-value --secret-id ${module.database[0].master_user_secret_arn} --region ${var.aws_region} --query SecretString --output text | jq -r .password"
  ) : null
}

# ---------------------------------------------------------------------------
# Deployment runbook
# ---------------------------------------------------------------------------

output "next_steps" {
  description = "Everything left to do after a successful apply."
  value       = <<-EOT

    ── Infrastructure is up. Three things remain. ──────────────────────────

    1. SET THE APPLICATION SECRET  (once, ever)

       Terraform created an empty secret on purpose -- writing the value here
       would put it in Terraform state in plaintext.

         aws secretsmanager put-secret-value \
           --secret-id ${aws_secretsmanager_secret.app.arn} \
           --region ${var.aws_region} \
           --secret-string "{\"SECRET_KEY\":\"$(openssl rand -hex 32)\",\"POSTGRES_PASSWORD\":\"$(openssl rand -base64 32 | tr -d '/+=')\"}"

    2. BUILD AND PUSH THE IMAGES  (from your workstation, until CI does it)

         ${module.ecr.docker_login_command}

         export REGISTRY=${module.ecr.registry_prefix}
         export IMAGE_TAG=$(git rev-parse --short HEAD)

         docker build -t $REGISTRY/backend:$IMAGE_TAG  ./backend
         docker build -t $REGISTRY/frontend:$IMAGE_TAG --target production ./frontend
         docker push $REGISTRY/backend:$IMAGE_TAG
         docker push $REGISTRY/frontend:$IMAGE_TAG

    3. START THE STACK

         aws ssm start-session --target ${module.compute.instance_id} --region ${var.aws_region}

         sudo app-deploy $IMAGE_TAG      # reads secrets, pulls, starts
         sudo systemctl start ${module.compute.service_name}

    ── Verify ─────────────────────────────────────────────────────────────

      curl -sS http://${module.compute.public_ip}/api/v1
      # expect: {"message":"Hello World"}

    ── Note ───────────────────────────────────────────────────────────────

    Plain HTTP on port 80, single instance, single AZ. No TLS, no redundancy.
    Fine for dev; see the prod environment's production_checklist output for
    what production additionally needs.
  EOT
}
