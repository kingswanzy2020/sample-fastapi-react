# ---------------------------------------------------------------------------
# Identity
#
# Defaults here lean safe rather than cheap -- the opposite of dev. If a value
# is omitted from terraform.tfvars, the fallback should be the conservative one.
# ---------------------------------------------------------------------------

variable "project" {
  description = "Project name, used as a prefix for every resource."
  type        = string
  default     = "fastapi-react"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "prod"
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
  description = "CIDR block for the VPC. Must not overlap dev if the two are ever peered."
  type        = string
  default     = "10.30.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for subnets."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets."
  type        = list(string)
  default     = ["10.30.1.0/24", "10.30.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets. Sized /20 to leave room for EKS pods later."
  type        = list(string)
  default     = ["10.30.16.0/20", "10.30.32.0/20"]
}

variable "enable_nat_gateway" {
  description = "Create a NAT Gateway. Required once anything in a private subnet needs outbound access."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Compute
# ---------------------------------------------------------------------------

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.medium"
}

variable "ami_id" {
  description = <<-EOT
    Pin a specific AMI for production. Leaving this null resolves the latest
    Ubuntu 22.04 image, which means the AMI a rebuild produces depends on the
    day you run it.
  EOT
  type        = string
  default     = null
}

variable "root_volume_size" {
  description = "Root volume size in GB."
  type        = number
  default     = 50
}

variable "key_name" {
  description = "Existing EC2 key pair for SSH, or null for SSM-only access."
  type        = string
  default     = null
}

variable "ssh_allowed_cidrs" {
  description = "CIDRs allowed on port 22. Empty is correct for production: use SSM Session Manager."
  type        = list(string)
  default     = []
}

variable "app_allowed_cidrs" {
  description = "CIDRs allowed to reach the application on 80/443."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_https" {
  description = "Open port 443."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Application deployment
# ---------------------------------------------------------------------------

variable "image_tag" {
  description = <<-EOT
    Image tag deployed on first boot. In production this should always be a git
    SHA -- "latest" makes "which version is running?" unanswerable and makes
    rollback guesswork.
  EOT
  type        = string
  default     = "latest"
}

variable "app_repository_url" {
  description = "HTTPS git URL cloned on first boot for the compose files. Null to place them yourself."
  type        = string
  default     = "https://github.com/kingswanzy2020/sample-fastapi-react.git"
}

variable "app_repository_ref" {
  description = "Branch or tag to clone. Pin to a tag in production, not a moving branch."
  type        = string
  default     = "main"
}

variable "ecr_image_tag_mutability" {
  description = "IMMUTABLE in production: a tag that cannot be overwritten is what makes it a real guarantee."
  type        = string
  default     = "IMMUTABLE"
}

variable "ecr_keep_last_n_images" {
  description = "Images retained per repository. Keep enough history to roll back to any recent release."
  type        = number
  default     = 50
}

variable "secret_recovery_window_days" {
  description = "Days AWS holds a deleted secret before purging it. 30 in production, so a mistake is recoverable."
  type        = number
  default     = 30
}

# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------

variable "create_database" {
  description = "Provision RDS. Production should never run its database in a container on the app host."
  type        = bool
  default     = true
}

variable "db_engine_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "16"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.small"
}

variable "db_allocated_storage" {
  description = "Initial storage in GB."
  type        = number
  default     = 50
}

variable "db_max_allocated_storage" {
  description = "Storage autoscaling ceiling in GB."
  type        = number
  default     = 500
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "app"
}

variable "db_username" {
  description = "Master username."
  type        = string
  default     = "appuser"
}

variable "db_port" {
  description = "Database port."
  type        = number
  default     = 5432
}

variable "db_multi_az" {
  description = "Run a standby in a second AZ. Roughly doubles cost; the price of surviving an AZ failure."
  type        = bool
  default     = true
}

variable "db_backup_retention_period" {
  description = "Days of automated backups. Also the point-in-time recovery window."
  type        = number
  default     = 30
}

variable "db_deletion_protection" {
  description = "Block deletion. Leave true; disabling it is a deliberate, reviewable change."
  type        = bool
  default     = true
}

variable "db_skip_final_snapshot" {
  description = "Skip the final snapshot on delete. Never true in production."
  type        = bool
  default     = false
}

variable "db_apply_immediately" {
  description = "Apply RDS changes at once. False in production: changes wait for the maintenance window."
  type        = bool
  default     = false
}

variable "db_performance_insights_enabled" {
  description = "Enable Performance Insights. Free at 7 days of retention."
  type        = bool
  default     = true
}
