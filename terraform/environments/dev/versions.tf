terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # Partial backend configuration.
  #
  # The bucket name contains the AWS account ID, which should not be committed
  # to a repository that might become public. So the block is left empty here
  # and the values come from backend.hcl, which is gitignored:
  #
  #   terraform init -backend-config=backend.hcl
  #
  # Generate backend.hcl from the bootstrap configuration:
  #   cd ../../bootstrap && terraform output -raw dev_backend_config > ../environments/dev/backend.hcl
  #
  # See backend.hcl.example for the shape.
  backend "s3" {}
}
