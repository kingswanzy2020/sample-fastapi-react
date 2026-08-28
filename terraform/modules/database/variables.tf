variable "project" {
  description = "Project name. Used as a prefix for every resource name."
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod)."
  type        = string
}

variable "vpc_id" {
  description = "VPC to create the database security group in."
  type        = string
}

variable "subnet_ids" {
  description = <<-EOT
    Subnets for the DB subnet group. Use the private subnets. At least two, in
    different availability zones -- RDS requires this even for a single-AZ
    instance, because it needs somewhere to fail over to later.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "RDS subnet groups require at least two subnets in different availability zones."
  }
}

variable "allowed_security_group_ids" {
  description = <<-EOT
    Security groups allowed to reach Postgres. Pass the application's security
    group ID -- referencing a security group rather than a CIDR means the rule
    stays correct when instance IPs change.
  EOT
  type        = list(string)
  default     = []
}

variable "engine_version" {
  description = <<-EOT
    PostgreSQL major.minor version. Setting only the major version (e.g. "16")
    lets AWS pick the current minor release and avoids a version-drift diff on
    every plan.
  EOT
  type        = string
  default     = "16"
}

variable "instance_class" {
  description = "RDS instance class. db.t4g.micro is the cheapest Graviton option and is enough for development."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Initial storage in GB. 20 is the minimum for gp3."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = <<-EOT
    Upper bound for storage autoscaling in GB. Set to 0 to disable autoscaling.
    Leaving this on is cheap insurance against a full disk taking the database
    offline at 3am.
  EOT
  type        = number
  default     = 100
}

variable "db_name" {
  description = "Name of the initial database created inside the instance."
  type        = string
  default     = "app"
}

variable "username" {
  description = "Master username. Cannot be 'postgres', 'admin', 'rdsadmin' or other reserved words."
  type        = string
  default     = "appuser"
}

variable "multi_az" {
  description = "Run a standby in a second availability zone. Roughly doubles the cost; required for any real availability target."
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Days of automated backups to keep. 0 disables backups entirely and also disables point-in-time recovery."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 1
    error_message = "Keep at least one day of backups. Setting this to 0 disables point-in-time recovery."
  }
}

variable "deletion_protection" {
  description = <<-EOT
    Block `terraform destroy` and console deletion of this instance.

    Prefer this over a `prevent_destroy` lifecycle block: it is a variable, so
    prod can enable it and dev can leave it off without editing module code.
  EOT
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on deletion. True is fine for a scratch environment; never true for production."
  type        = bool
  default     = true
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights. Free for 7 days of retention on supported instance classes."
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = <<-EOT
    Apply modifications at once rather than in the next maintenance window.
    Convenient in development; in production it can cause an unplanned restart.
  EOT
  type        = bool
  default     = false
}

variable "log_min_duration_statement" {
  description = "Log statements slower than this many milliseconds. -1 disables. 1000 is a reasonable default for finding slow queries."
  type        = number
  default     = 1000
}
