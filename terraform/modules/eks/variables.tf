variable "project" {
  description = "Project name. Used as a prefix for every resource name."
  type        = string
}

variable "environment" {
  description = "Environment name. The cluster is named <project>-<environment>."
  type        = string
}

variable "kubernetes_version" {
  description = <<-EOT
    EKS Kubernetes version. Keep it in STANDARD support: a version in extended
    support bills the control plane at $0.60/h instead of $0.10/h. Check with:
      aws eks describe-cluster-versions --status STANDARD_SUPPORT \
        --query 'clusterVersions[].clusterVersion'
  EOT
  type        = string
}

variable "vpc_id" {
  description = "VPC the cluster runs in."
  type        = string
}

variable "subnet_ids" {
  description = <<-EOT
    Private subnets for the control plane ENIs and the nodes, in at least two
    AZs. The VPC CNI gives every pod a VPC IP from these subnets, so size them
    for pods (/20 or larger), not for nodes.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "EKS requires subnets in at least two availability zones."
  }
}

variable "endpoint_public_access_cidrs" {
  description = <<-EOT
    CIDRs allowed to reach the public API endpoint. Every request still needs
    valid IAM credentials, but narrowing this to your own address is cheap:
      curl -s https://checkip.amazonaws.com
  EOT
  type        = list(string)
}

variable "node_instance_types" {
  description = "Managed node group instance types. A t3.medium holds 17 pods (ENI limit), 4 GiB RAM."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_min_size" {
  description = "Minimum nodes. Two, so one node (and its AZ) can fail."
  type        = number
  default     = 2
}

variable "node_desired_size" {
  description = "Desired nodes."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum nodes."
  type        = number
  default     = 4
}

variable "external_secrets_secret_arns" {
  description = <<-EOT
    Secrets Manager ARNs the External Secrets Operator may read -- and nothing
    else. Pass the application secret and the RDS-managed master user secret.
  EOT
  type        = list(string)
}

variable "log_retention_days" {
  description = "Retention for the control plane log group."
  type        = number
  default     = 7
}
