terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    # 2.x: the 3.x provider changed the kubernetes block to an attribute and
    # the set blocks to lists. Pinned to keep one syntax.
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
  }

  # Same partial backend as ../cluster, its own key.
  #   terraform init -backend-config=backend.hcl
  backend "s3" {}
}
