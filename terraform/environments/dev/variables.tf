# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

variable "project" {
  description = "Project name, used as a prefix for every resource."
  type        = string
  default     = "fastapi-react"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"
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
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for subnets. Two minimum -- RDS subnet groups require it."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets."
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = <<-EOT
    CIDR blocks for private subnets. /24 is plenty for RDS. If these subnets
    will later host EKS nodes, resize to /20 or larger first -- the AWS VPC CNI
    gives every pod a real VPC IP, so subnets must be sized for pods, not nodes.
  EOT
  type        = list(string)
  default     = ["10.20.11.0/24", "10.20.12.0/24"]
}

variable "enable_nat_gateway" {
  description = "Create a NAT Gateway. ~$32/month; nothing in this environment needs it."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Compute
# ---------------------------------------------------------------------------

variable "instance_type" {
  description = "EC2 instance type. t3.micro's 1 GB will OOM this container stack."
  type        = string
  default     = "t3.small"
}

variable "ami_id" {
  description = "Pin a specific AMI, or null to use the latest Ubuntu 22.04 LTS."
  type        = string
  default     = null
}

variable "root_volume_size" {
  description = "Root volume size in GB."
  type        = number
  default     = 30
}

variable "key_name" {
  description = "Existing EC2 key pair name for SSH, or null for SSM-only access."
  type        = string
  default     = null
}

variable "ssh_allowed_cidrs" {
  description = <<-EOT
    CIDRs allowed on port 22. Default is empty: SSM Session Manager needs no
    open port and no key, and the instance profile already permits it.

    To use SSH, set this to your own address:
      curl -s https://checkip.amazonaws.com
  EOT
  type        = list(string)
  default     = []
}

variable "app_allowed_cidrs" {
  description = "CIDRs allowed to reach the application on 80/443."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_https" {
  description = "Open port 443. Turn on once TLS actually terminates on the instance."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Application deployment
# ---------------------------------------------------------------------------

variable "image_tag" {
  description = <<-EOT
    Image tag deployed on first boot. Redeploys afterwards are
    `sudo app-deploy <tag>` on the instance and need no Terraform run.

    Use a git SHA once CI is pushing images. "latest" tells you nothing about
    what is actually running.
  EOT
  type        = string
  default     = "latest"
}

variable "app_repository_url" {
  description = <<-EOT
    HTTPS git URL cloned on first boot to get the compose files onto the box.
    Set to null to place them yourself.

    IMPORTANT: the ref below must already contain the Dockerfiles,
    docker-compose.prod.yml and .env.example. If the containerization work is
    still uncommitted locally, push it before applying.
  EOT
  type        = string
  default     = "https://github.com/kingswanzy2020/sample-fastapi-react.git"
}

variable "app_repository_ref" {
  description = "Branch or tag to clone."
  type        = string
  default     = "main"
}

variable "ecr_image_tag_mutability" {
  description = "MUTABLE while pushing 'latest' by hand; IMMUTABLE once CI tags by git SHA."
  type        = string
  default     = "MUTABLE"
}

variable "ecr_keep_last_n_images" {
  description = "Images retained per repository before the lifecycle policy expires them."
  type        = number
  default     = 20
}

variable "secret_recovery_window_days" {
  description = <<-EOT
    Days AWS holds a deleted secret before purging it. 0 deletes immediately,
    which is what a disposable environment wants -- otherwise destroying and
    rebuilding fails with "a secret with this name is scheduled for deletion".
  EOT
  type        = number
  default     = 0
}

# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------

variable "create_database" {
  description = <<-EOT
    Provision RDS and point the application at it.

    When false, the Postgres container from docker-compose.yml is used instead
    and its password comes from the same application secret. Saves roughly
    $15/month at the cost of no backups and no failover.
  EOT
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
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Initial storage in GB."
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "Storage autoscaling ceiling in GB. 0 disables autoscaling."
  type        = number
  default     = 100
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "app"
}

variable "db_username" {
  description = "Master username. 'postgres' is reserved by RDS and will be rejected."
  type        = string
  default     = "appuser"
}

variable "db_port" {
  description = "Database port."
  type        = number
  default     = 5432
}

variable "db_multi_az" {
  description = "Run a standby in a second AZ. Roughly doubles the cost."
  type        = bool
  default     = false
}

variable "db_backup_retention_period" {
  description = "Days of automated backups."
  type        = number
  default     = 7
}

variable "db_deletion_protection" {
  description = "Block deletion of the database. Off in dev so terraform destroy works."
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Skip the final snapshot on delete. Acceptable for a scratch environment."
  type        = bool
  default     = true
}

variable "db_apply_immediately" {
  description = "Apply RDS changes at once instead of in the maintenance window."
  type        = bool
  default     = true
}
