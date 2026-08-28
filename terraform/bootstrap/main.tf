# ---------------------------------------------------------------------------
# Bootstrap -- the S3 bucket that holds Terraform state for every environment.
#
# Run this ONCE per AWS account, before dev or prod. It is the only
# configuration in this repository that uses local state.
#
#   cd terraform/bootstrap
#   terraform init
#   terraform apply
#   terraform output -raw dev_backend_config  > ../environments/dev/backend.hcl
#   terraform output -raw prod_backend_config > ../environments/prod/backend.hcl
#
# State locking uses S3 conditional writes (use_lockfile), available in
# Terraform 1.10+. The old DynamoDB lock table is no longer needed.
# ---------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Purpose   = "terraform-state"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  # Account ID makes the name globally unique -- S3 bucket names are a single
  # global namespace, so "tfstate-fastapi-react" is almost certainly taken.
  bucket_name = "tfstate-${var.project}-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name

  tags = {
    Name = local.bucket_name
  }

  lifecycle {
    # State is the record of everything that exists. Deleting this bucket by
    # accident means Terraform loses track of every resource in every
    # environment -- they keep running, and Terraform no longer knows about them.
    prevent_destroy = true
  }
}

# Versioning is the recovery mechanism for a corrupted or truncated state file.
# Without it, a bad apply is unrecoverable.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# State contains every resource attribute in plaintext, including RDS endpoints,
# secret ARNs and any sensitive value a provider returns.
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Old versions accumulate on every apply. Keep enough history to recover from a
# mistake, not enough to pay for indefinitely.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.state_version_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

# Refuse any request that is not over TLS. Without this, a misconfigured client
# can transmit state -- and everything in it -- in cleartext.
data "aws_iam_policy_document" "deny_insecure_transport" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.deny_insecure_transport.json

  depends_on = [aws_s3_bucket_public_access_block.state]
}
