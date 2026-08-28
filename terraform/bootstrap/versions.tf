terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # No backend block here, on purpose.
  #
  # This configuration creates the bucket that every other configuration stores
  # its state in, so it cannot store its own state there -- the bucket does not
  # exist when it runs. It uses local state, runs once per account, and the
  # resulting terraform.tfstate is disposable: everything here can be recovered
  # with `terraform import` if it is ever lost.
}
