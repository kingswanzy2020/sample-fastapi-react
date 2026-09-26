output "lb_controller_version" {
  description = "Installed AWS Load Balancer Controller chart version."
  value       = helm_release.lb_controller.version
}

output "external_secrets_version" {
  description = "Installed External Secrets Operator chart version."
  value       = helm_release.external_secrets.version
}

output "verify_commands" {
  description = "Check both controllers are running with IRSA, not keys."
  value       = <<-EOT
    kubectl -n kube-system rollout status deploy/aws-load-balancer-controller
    kubectl -n external-secrets rollout status deploy/external-secrets
    kubectl -n kube-system get sa aws-load-balancer-controller -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'; echo
    kubectl -n external-secrets get sa external-secrets -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'; echo
  EOT
}
