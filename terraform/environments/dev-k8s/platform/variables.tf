variable "project" {
  description = "Project name. Must match ../cluster."
  type        = string
  default     = "fastapi-react"
}

variable "environment" {
  description = "Environment name. Must match ../cluster -- the cluster is found by <project>-<environment>."
  type        = string
  default     = "dev-k8s"
}

variable "aws_region" {
  description = "AWS region the cluster is in."
  type        = string
  default     = "us-east-1"
}

variable "lb_controller_chart_version" {
  description = <<-EOT
    aws-load-balancer-controller chart version. Bump together with
    modules/eks/lb-controller-iam-policy.json -- new controller versions add
    IAM permissions.
  EOT
  type        = string
  default     = "3.5.0"
}

variable "external_secrets_chart_version" {
  description = "external-secrets chart version. 0.17+ serves the external-secrets.io/v1 API the app chart uses."
  type        = string
  default     = "2.11.0"
}
