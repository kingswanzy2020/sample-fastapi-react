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

output "ami_id" {
  description = "AMI the instance was launched from. Copy this into terraform.tfvars to pin it."
  value       = module.compute.ami_id
}

output "app_url" {
  description = "URL the application is served from."
  value       = var.enable_https ? "https://${module.compute.public_ip}" : "http://${module.compute.public_ip}"
}

output "ssm_command" {
  description = "Open a shell with no open port and no SSH key."
  value       = "aws ssm start-session --target ${module.compute.instance_id} --region ${var.aws_region}"
}

# ---------------------------------------------------------------------------
# Registry
# ---------------------------------------------------------------------------

output "ecr_registry_prefix" {
  description = "Value of REGISTRY for docker-compose."
  value       = module.ecr.registry_prefix
}

output "ecr_repository_urls" {
  description = "Full URL of each image repository."
  value       = module.ecr.repository_urls
}

output "docker_login_command" {
  description = "Authenticate a Docker daemon against this registry."
  value       = module.ecr.docker_login_command
}

# ---------------------------------------------------------------------------
# Secrets and database
# ---------------------------------------------------------------------------

output "app_secret_arn" {
  description = "ARN of the application secret. Terraform created it empty; you set the value."
  value       = aws_secretsmanager_secret.app.arn
}

output "db_endpoint" {
  description = "RDS endpoint, or null when the database is disabled."
  value       = var.create_database ? module.database[0].endpoint : null
}

output "db_secret_arn" {
  description = "ARN of the RDS-managed master password secret."
  value       = var.create_database ? module.database[0].master_user_secret_arn : null
}

# ---------------------------------------------------------------------------
# Deployment
# ---------------------------------------------------------------------------

output "next_steps" {
  description = "Ordered next steps after a successful apply."
  value       = <<-EOT

    ── Infrastructure is up. ───────────────────────────────────────────────

    1. SET THE APPLICATION SECRET  (once, ever)

         aws secretsmanager put-secret-value \
           --secret-id ${aws_secretsmanager_secret.app.arn} \
           --region ${var.aws_region} \
           --secret-string "{\"SECRET_KEY\":\"$(openssl rand -hex 32)\",\"POSTGRES_PASSWORD\":\"$(openssl rand -base64 32 | tr -d '/+=')\"}"

    2. PUSH IMAGES, TAGGED WITH A GIT SHA

         ${module.ecr.docker_login_command}

         export REGISTRY=${module.ecr.registry_prefix}
         export IMAGE_TAG=$(git rev-parse --short HEAD)

         docker build -t $REGISTRY/backend:$IMAGE_TAG  ./backend
         docker build -t $REGISTRY/frontend:$IMAGE_TAG --target production ./frontend
         docker push $REGISTRY/backend:$IMAGE_TAG
         docker push $REGISTRY/frontend:$IMAGE_TAG

    3. DEPLOY THAT EXACT SHA

         aws ssm start-session --target ${module.compute.instance_id} --region ${var.aws_region}
         sudo app-deploy $IMAGE_TAG

       Rolling back is the same command with the previous SHA.

    4. PIN THE AMI

         Set ami_id = "${module.compute.ami_id}" in terraform.tfvars, so a
         rebuild produces the same image rather than whatever is current.
  EOT
}

output "production_checklist" {
  description = "What this configuration deliberately does not do for you."
  value       = <<-EOT

    Four things production needs that this Terraform does not provide:

    1. TLS. Port 443 is open but nothing terminates it. Either put an ACM
       certificate on an ALB in front of the instance, or run Caddy on the box
       for automatic Let's Encrypt certificates. A bare Elastic IP cannot have
       an ACM certificate -- you need a DNS name either way.

    2. DNS. Point a Route 53 record at ${module.compute.public_ip}. The Elastic
       IP survives stop/start, so the record stays valid across reboots.

    3. Backups of anything that is not RDS. The database has ${var.db_backup_retention_period}-day automated
       backups and point-in-time recovery. The EBS root volume has neither --
       add a DLM lifecycle policy, or accept that the box is disposable (which
       it is: everything on it is rebuilt by user_data and app-deploy).

    4. Redundancy. This is ONE instance in ONE availability zone. An AZ failure
       or a bad deploy is a full outage, and `app-deploy` restarts containers in
       place rather than rolling. Real availability starts with an ALB and an
       autoscaling group -- a different compute module, not a bigger instance.

    Also worth doing before this carries real traffic:
      - CloudWatch alarms on instance status checks and RDS free storage
      - A rate limit on /api/token (AWS WAF, or slowapi in the application)
      - Structured JSON logs shipped off the box
  EOT
}
