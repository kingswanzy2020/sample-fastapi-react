# ---------------------------------------------------------------------------
# ECR -- one private repository per image.
#
# Repository names are "<project>-<environment>/<image>", e.g.
# "fastapi-react-dev/backend". The slash is deliberate: it means the registry
# prefix passed to docker-compose as REGISTRY can be
#
#   <account>.dkr.ecr.<region>.amazonaws.com/fastapi-react-dev
#
# and the existing "$${REGISTRY}/backend:$${IMAGE_TAG}" in docker-compose.yml
# resolves correctly with no change to the application repository.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  name_prefix = "${var.project}-${var.environment}"

  registry_url = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
}

resource "aws_ecr_repository" "this" {
  for_each = toset(var.repositories)

  name                 = "${local.name_prefix}/${each.value}"
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name  = "${local.name_prefix}/${each.value}"
    Image = each.value
  }
}

# Without a lifecycle policy every build is kept forever. A CI pipeline tagging
# by git SHA produces a new image on every merge, and ECR storage is billed by
# the gigabyte.
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.untagged_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_expiry_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the last ${var.keep_last_n_images} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.keep_last_n_images
        }
        action = { type = "expire" }
      },
    ]
  })
}
