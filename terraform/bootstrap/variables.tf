variable "project" {
  description = "Project name. Forms part of the state bucket name."
  type        = string
  default     = "fastapi-react"
}

variable "aws_region" {
  description = "Region to create the state bucket in. Every environment's backend must point at this same region."
  type        = string
  default     = "us-east-1"
}

variable "state_version_retention_days" {
  description = "How long to keep superseded state versions. 90 days is enough to recover from a mistake nobody noticed for a while."
  type        = number
  default     = 90
}
