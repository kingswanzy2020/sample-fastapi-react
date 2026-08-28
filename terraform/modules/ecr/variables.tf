variable "project" {
  description = "Project name."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "repositories" {
  description = <<-EOT
    Image names to create repositories for.

    Each becomes an ECR repository at "<project>-<environment>/<name>", so the
    registry prefix ends at the environment and the image name follows. That is
    what lets docker-compose.yml work unmodified: it already builds image names
    as "$${REGISTRY}/backend", so REGISTRY only has to be set to the account
    registry plus "<project>-<environment>".
  EOT
  type        = list(string)
  default     = ["backend", "frontend"]
}

variable "image_tag_mutability" {
  description = <<-EOT
    IMMUTABLE forbids overwriting an existing tag, which is what makes a git-SHA
    tag a real guarantee of what is running. Use MUTABLE while you are still
    pushing "latest" by hand.
  EOT
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "scan_on_push" {
  description = "Run ECR's basic vulnerability scan on every push. Free."
  type        = bool
  default     = true
}

variable "keep_last_n_images" {
  description = "How many tagged images to retain per repository before the lifecycle policy expires them."
  type        = number
  default     = 20
}

variable "untagged_expiry_days" {
  description = "Days before untagged images (layers orphaned by a retag) are deleted."
  type        = number
  default     = 7
}

variable "force_delete" {
  description = "Allow `terraform destroy` to delete a repository that still contains images. True is convenient in dev, dangerous in prod."
  type        = bool
  default     = false
}
