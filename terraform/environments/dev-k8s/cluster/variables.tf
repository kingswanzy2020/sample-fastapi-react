# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

variable "project" {
  description = "Project name, used as a prefix for every resource."
  type        = string
  default     = "fastapi-react"
}

variable "environment" {
  description = "Environment name. The EKS cluster is named <project>-<environment>."
  type        = string
  default     = "dev-k8s"
}

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "repository_url" {
  description = "Source repository, recorded as a tag on every resource."
  type        = string
  default     = "https://github.com/kingswanzy2020/sample-fastapi-react"
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Distinct from environments/dev (10.20.0.0/16) so both can coexist."
  type        = string
  default     = "10.30.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones. Two: nodes and replicas spread across both."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "Public subnets: the ALB and the NAT Gateway."
  type        = list(string)
  default     = ["10.30.0.0/24", "10.30.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = <<-EOT
    Private subnets: nodes, pods and RDS. /20 (4,091 addresses) each, because
    the VPC CNI gives every pod its own VPC IP.
  EOT
  type        = list(string)
  default     = ["10.30.16.0/20", "10.30.32.0/20"]
}

# ---------------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------------

variable "kubernetes_version" {
  description = "EKS version. Must be in standard support -- see modules/eks/variables.tf."
  type        = string
  default     = "1.34"
}

variable "endpoint_public_access_cidrs" {
  description = <<-EOT
    Who may reach the Kubernetes API endpoint (IAM auth still applies). Set to
    your own /32 in terraform.tfvars for the session; GitHub-hosted runners
    need 0.0.0.0/0 or a self-hosted runner.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_types" {
  description = "Node instance types."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_min_size" {
  description = "Minimum nodes."
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

# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_name" {
  description = "Initial database name. Must match database.name in values-eks.yaml."
  type        = string
  default     = "app"
}

variable "db_username" {
  description = "Master username. 'postgres' is reserved by RDS."
  type        = string
  default     = "appuser"
}
