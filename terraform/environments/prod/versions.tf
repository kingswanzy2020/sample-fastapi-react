terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # Partial backend configuration -- values come from backend.hcl, which is
  # gitignored because the bucket name embeds the AWS account ID.
  #
  #   terraform init -backend-config=backend.hcl
  #
  # Note the state key differs from dev. A separate state file per environment
  # is the isolation that stops a mistake in dev from touching production.
  backend "s3" {}
}
