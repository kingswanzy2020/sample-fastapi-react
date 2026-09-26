terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # Partial backend configuration, as in environments/dev: the bucket name
  # embeds the AWS account ID, so it lives in the gitignored backend.hcl.
  #
  #   cp backend.hcl.example backend.hcl   # fill in the account ID
  #   terraform init -backend-config=backend.hcl
  backend "s3" {}
}
