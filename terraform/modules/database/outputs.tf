output "endpoint" {
  description = "Connection endpoint, host:port."
  value       = aws_db_instance.this.endpoint
}

output "address" {
  description = "Hostname of the instance, without the port."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Port the database listens on."
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Name of the initial database."
  value       = aws_db_instance.this.db_name
}

output "username" {
  description = "Master username."
  value       = aws_db_instance.this.username
}

output "master_user_secret_arn" {
  description = <<-EOT
    ARN of the Secrets Manager secret holding the master password. RDS owns this
    secret; the password itself never enters Terraform state.

    Read it with:
      aws secretsmanager get-secret-value --secret-id <arn> \
        --query SecretString --output text | jq -r .password
  EOT
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "security_group_id" {
  description = "ID of the database security group."
  value       = aws_security_group.db.id
}

output "instance_id" {
  description = "RDS instance identifier."
  value       = aws_db_instance.this.identifier
}

output "database_url_template" {
  description = <<-EOT
    DATABASE_URL with the password left as a placeholder. Substitute the value
    fetched from Secrets Manager at deploy time -- never store the resolved
    string in Terraform, in git, or in a tfvars file.
  EOT
  value       = "postgresql://${aws_db_instance.this.username}:__PASSWORD__@${aws_db_instance.this.address}:${aws_db_instance.this.port}/${aws_db_instance.this.db_name}"
}
