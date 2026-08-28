output "state_bucket" {
  description = "Name of the Terraform state bucket."
  value       = aws_s3_bucket.state.id
}

output "account_id" {
  description = "AWS account the bucket was created in."
  value       = data.aws_caller_identity.current.account_id
}

# ---------------------------------------------------------------------------
# Ready-to-write backend configuration.
#
# These are emitted rather than committed because they contain the account ID.
# Write them with:
#   terraform output -raw dev_backend_config  > ../environments/dev/backend.hcl
#   terraform output -raw prod_backend_config > ../environments/prod/backend.hcl
#
# backend.hcl is gitignored; backend.hcl.example is the committed template.
# ---------------------------------------------------------------------------

output "dev_backend_config" {
  description = "Contents for environments/dev/backend.hcl."
  value       = <<-EOT
    bucket       = "${aws_s3_bucket.state.id}"
    key          = "dev/terraform.tfstate"
    region       = "${var.aws_region}"
    encrypt      = true
    use_lockfile = true
  EOT
}

output "prod_backend_config" {
  description = "Contents for environments/prod/backend.hcl."
  value       = <<-EOT
    bucket       = "${aws_s3_bucket.state.id}"
    key          = "prod/terraform.tfstate"
    region       = "${var.aws_region}"
    encrypt      = true
    use_lockfile = true
  EOT
}
