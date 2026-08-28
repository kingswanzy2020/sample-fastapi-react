variable "project" {
  description = "Project name. Used as a prefix for every resource name."
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod)."
  type        = string
}

variable "aws_region" {
  description = "Region the instance runs in. Baked into the deploy script for AWS CLI calls."
  type        = string
}

variable "vpc_id" {
  description = "VPC to create the security groups in."
  type        = string
}

variable "subnet_id" {
  description = "Public subnet to launch the instance into."
  type        = string
}

# ---------------------------------------------------------------------------
# Instance
# ---------------------------------------------------------------------------

variable "instance_type" {
  description = <<-EOT
    EC2 instance type.

    t3.small (2 GB) is the practical floor for this stack: nginx, backend,
    worker, redis and postgres containers together will OOM a t3.micro's 1 GB.
    Dropping the Postgres container by using RDS frees roughly 250 MB.
  EOT
  type        = string
  default     = "t3.small"
}

variable "ami_id" {
  description = <<-EOT
    AMI to launch. Leave null to look up the latest Ubuntu 22.04 LTS from
    Canonical. Pin this to a specific AMI ID for reproducible rebuilds.
  EOT
  type        = string
  default     = null
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB. Docker images accumulate; 30 is a sane floor."
  type        = number
  default     = 30
}

variable "key_name" {
  description = <<-EOT
    Name of an existing EC2 key pair for SSH access. Leave null to rely on SSM
    Session Manager only, which needs no key and no open port.
  EOT
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Network access
# ---------------------------------------------------------------------------

variable "ssh_allowed_cidrs" {
  description = <<-EOT
    CIDR blocks allowed to reach port 22. Set to [] to disable SSH entirely and
    use SSM Session Manager instead -- the instance profile already allows it.

    Never open this to 0.0.0.0/0; port 22 exposed to the internet is found by
    scanners within minutes.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.ssh_allowed_cidrs, "0.0.0.0/0")
    error_message = "Refusing 0.0.0.0/0 on port 22. Use your own /32, or set ssh_allowed_cidrs = [] and connect with SSM Session Manager."
  }
}

variable "app_allowed_cidrs" {
  description = "CIDR blocks allowed to reach the application on ports 80 and 443."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_https" {
  description = "Open port 443 as well as port 80. Turn on once TLS is actually terminating on the box."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Application deployment
# ---------------------------------------------------------------------------

variable "app_directory" {
  description = "Directory on the instance the application is deployed into."
  type        = string
  default     = "/opt/app"
}

variable "registry_prefix" {
  description = <<-EOT
    Registry prefix passed to docker-compose as REGISTRY, e.g.
    "123456789012.dkr.ecr.us-east-1.amazonaws.com/fastapi-react-dev".

    docker-compose.yml already builds image names as "$${REGISTRY}/backend", so
    this is the only value needed to point it at ECR.
  EOT
  type        = string
}

variable "image_tag" {
  description = <<-EOT
    Image tag to deploy on first boot. Written to <app_directory>/IMAGE_TAG,
    after which redeploys are `sudo app-deploy <tag>` and need no Terraform run.

    Use a git SHA in anything that matters. "latest" tells you nothing about
    what is actually running.
  EOT
  type        = string
  default     = "latest"
}

variable "repository_url" {
  description = <<-EOT
    HTTPS git URL to clone the application from on first boot, for the compose
    files. Set to null to skip cloning and place the files yourself.

    Only the compose files are needed -- images come from ECR -- but cloning the
    repository is the simplest way to get them onto a fresh instance.
  EOT
  type        = string
  default     = null
}

variable "repository_ref" {
  description = "Branch or tag to clone. Must contain the Dockerfiles and compose files."
  type        = string
  default     = "main"
}

# ---------------------------------------------------------------------------
# Secrets and database wiring
# ---------------------------------------------------------------------------

variable "app_secret_arn" {
  description = <<-EOT
    ARN of the Secrets Manager secret holding SECRET_KEY (and POSTGRES_PASSWORD
    when RDS is not used). Terraform creates the container but never the value.
  EOT
  type        = string
}

variable "db_secret_arn" {
  description = "ARN of the RDS-managed master password secret. Empty string when RDS is not used."
  type        = string
  default     = ""
}

variable "use_rds" {
  description = <<-EOT
    Point the application at RDS instead of the Postgres container.

    When true the deploy script generates a compose overlay that removes the
    postgres service and the dependencies on it.
  EOT
  type        = bool
  default     = true
}

variable "db_host" {
  description = "RDS hostname. Ignored when use_rds is false."
  type        = string
  default     = ""
}

variable "db_port" {
  description = "Database port."
  type        = number
  default     = 5432
}

variable "db_name" {
  description = "Database name."
  type        = string
  default     = "app"
}

variable "db_user" {
  description = "Database username."
  type        = string
  default     = "appuser"
}
