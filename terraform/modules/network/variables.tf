variable "project" {
  description = "Project name. Used as a prefix for every resource name."
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod). Used as a resource name suffix."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block, e.g. 10.20.0.0/16."
  }
}

variable "availability_zones" {
  description = <<-EOT
    Availability zones to spread subnets across. Two is the practical minimum:
    RDS subnet groups require at least two AZs even for a single-AZ instance.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "Provide at least two availability zones (RDS subnet groups require it)."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets. Must match the length of availability_zones."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private subnets. Must match the length of availability_zones."
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = <<-EOT
    Create a NAT Gateway so private subnets have outbound internet access.

    Leave this false unless something actually runs in a private subnet. A NAT
    Gateway is roughly $32/month plus data processing charges, and RDS does not
    need one -- it never makes outbound calls to the internet.
  EOT
  type        = bool
  default     = false
}
