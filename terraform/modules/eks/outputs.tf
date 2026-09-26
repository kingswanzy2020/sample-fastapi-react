output "cluster_name" {
  description = "EKS cluster name."
  value       = module.cluster.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = module.cluster.cluster_endpoint
}

output "cluster_version" {
  description = "Kubernetes version the control plane runs."
  value       = module.cluster.cluster_version
}

output "node_security_group_id" {
  description = <<-EOT
    Security group on the nodes. With the VPC CNI, pods use the node's ENIs, so
    this is also the source group for pod traffic -- pass it to the database
    module's allowed_security_group_ids.
  EOT
  value       = module.cluster.node_security_group_id
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider backing IRSA."
  value       = module.cluster.oidc_provider_arn
}

output "kms_key_arn" {
  description = "KMS key encrypting Kubernetes Secrets in etcd."
  value       = module.cluster.kms_key_arn
}

output "irsa_role_arns" {
  description = "IAM role ARN per in-cluster controller (lb-controller, external-secrets)."
  value       = { for k, v in aws_iam_role.irsa : k => v.arn }
}
