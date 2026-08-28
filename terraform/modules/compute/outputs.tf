output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.app.id
}

output "public_ip" {
  description = "Elastic IP attached to the instance."
  value       = aws_eip.app.public_ip
}

output "private_ip" {
  description = "Private IP of the instance inside the VPC."
  value       = aws_instance.app.private_ip
}

output "web_security_group_id" {
  description = "ID of the web security group. Pass this to the database module so it can allow Postgres from the app."
  value       = aws_security_group.web.id
}

output "ssh_security_group_id" {
  description = "ID of the SSH security group, or null when SSH is disabled."
  value       = length(var.ssh_allowed_cidrs) > 0 ? aws_security_group.ssh[0].id : null
}

output "iam_role_name" {
  description = "Name of the instance IAM role."
  value       = aws_iam_role.instance.name
}

output "iam_role_arn" {
  description = "ARN of the instance IAM role."
  value       = aws_iam_role.instance.arn
}

output "ami_id" {
  description = "AMI the instance was launched from."
  value       = local.ami_id
}

output "app_directory" {
  description = "Directory on the instance the application is deployed into."
  value       = var.app_directory
}

output "service_name" {
  description = "Name of the systemd unit that manages the application stack."
  value       = local.service_name
}
