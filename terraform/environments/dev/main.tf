# ---------------------------------------------------------------------------
# dev environment
#
# Wires the four modules together plus the application secret. Module arguments
# referencing another module's outputs are what build the dependency graph --
# Terraform infers the ordering, so no explicit depends_on is needed here.
# ---------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region

  # Set once here rather than repeated on every resource. These tags are also
  # what a dynamic Ansible inventory would filter on later, so the same labels
  # do double duty as cost allocation and as service discovery.
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = var.repository_url
    }
  }
}

# ---------------------------------------------------------------------------
# Application secret
#
# Terraform creates the CONTAINER and never the VALUE.
#
# This is the whole point: Terraform state is plaintext, so any secret passed
# through a variable, a .tfvars file or a random_password resource ends up
# readable by anyone who can read state. Creating an empty secret means
# Terraform owns its existence, its name and who may read it -- while the value
# is written once, out of band, and never enters state at all.
#
# Set it before the first deploy:
#   aws secretsmanager put-secret-value \
#     --secret-id fastapi-react/dev/app --region us-east-1 \
#     --secret-string "{\"SECRET_KEY\":\"$(openssl rand -hex 32)\",\"POSTGRES_PASSWORD\":\"$(openssl rand -base64 32 | tr -d '/+=')\"}"
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "app" {
  name        = "${var.project}/${var.environment}/app"
  description = "Application secrets for ${var.project} ${var.environment}: SECRET_KEY, POSTGRES_PASSWORD"

  # 0 means a destroyed secret is deleted immediately rather than held for 30
  # days. Without this, tearing down and rebuilding dev fails with "a secret
  # with this name is scheduled for deletion".
  recovery_window_in_days = var.secret_recovery_window_days

  tags = {
    Name = "${var.project}-${var.environment}-app"
  }
}

# ---------------------------------------------------------------------------
# Modules
# ---------------------------------------------------------------------------

module "network" {
  source = "../../modules/network"

  project     = var.project
  environment = var.environment

  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  # Nothing in a private subnet needs outbound internet access: RDS never makes
  # outbound calls. ~$32/month saved.
  enable_nat_gateway = var.enable_nat_gateway
}

module "ecr" {
  source = "../../modules/ecr"

  project     = var.project
  environment = var.environment

  repositories         = ["backend", "frontend"]
  image_tag_mutability = var.ecr_image_tag_mutability
  keep_last_n_images   = var.ecr_keep_last_n_images

  # Let `terraform destroy` remove repositories that still hold images. Fine for
  # a scratch environment; never in production.
  force_delete = true
}

module "database" {
  source = "../../modules/database"
  count  = var.create_database ? 1 : 0

  project     = var.project
  environment = var.environment

  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.private_subnet_ids

  # Reference the app's security group, not a CIDR: the rule stays correct when
  # the instance is replaced and its IP changes.
  allowed_security_group_ids = [module.compute.web_security_group_id]

  engine_version        = var.db_engine_version
  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  db_name               = var.db_name
  username              = var.db_username

  multi_az                = var.db_multi_az
  backup_retention_period = var.db_backup_retention_period
  deletion_protection     = var.db_deletion_protection
  skip_final_snapshot     = var.db_skip_final_snapshot
  apply_immediately       = var.db_apply_immediately
}

module "compute" {
  source = "../../modules/compute"

  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region

  vpc_id    = module.network.vpc_id
  subnet_id = module.network.public_subnet_ids[0]

  instance_type    = var.instance_type
  ami_id           = var.ami_id
  root_volume_size = var.root_volume_size
  key_name         = var.key_name

  ssh_allowed_cidrs = var.ssh_allowed_cidrs
  app_allowed_cidrs = var.app_allowed_cidrs
  enable_https      = var.enable_https

  # --- deployment ---
  registry_prefix = module.ecr.registry_prefix
  image_tag       = var.image_tag
  repository_url  = var.app_repository_url
  repository_ref  = var.app_repository_ref

  # --- secrets and database ---
  app_secret_arn = aws_secretsmanager_secret.app.arn
  use_rds        = var.create_database

  db_secret_arn = var.create_database ? module.database[0].master_user_secret_arn : ""
  db_host       = var.create_database ? module.database[0].address : ""
  db_port       = var.db_port
  db_name       = var.db_name
  db_user       = var.db_username
}
