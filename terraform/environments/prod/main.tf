# ---------------------------------------------------------------------------
# prod environment
#
# Identical module wiring to dev. Everything that differs between the two lives
# in terraform.tfvars.
#
# The duplication is deliberate: separate directories give each environment its
# own state file and let them diverge without the `count = var.env == "prod" ?
# 2 : 1` conditionals that workspaces inevitably grow.
# ---------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region

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
# Application secret -- container only, never the value. See the dev
# environment's main.tf for why.
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "app" {
  name        = "${var.project}/${var.environment}/app"
  description = "Application secrets for ${var.project} ${var.environment}: SECRET_KEY, POSTGRES_PASSWORD"

  # 30 days in production: a secret deleted by mistake can be restored.
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

  enable_nat_gateway = var.enable_nat_gateway
}

module "ecr" {
  source = "../../modules/ecr"

  project     = var.project
  environment = var.environment

  repositories         = ["backend", "frontend"]
  image_tag_mutability = var.ecr_image_tag_mutability
  keep_last_n_images   = var.ecr_keep_last_n_images

  # Never let a destroy silently delete production images.
  force_delete = false
}

module "database" {
  source = "../../modules/database"
  count  = var.create_database ? 1 : 0

  project     = var.project
  environment = var.environment

  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.private_subnet_ids

  allowed_security_group_ids = [module.compute.web_security_group_id]

  engine_version        = var.db_engine_version
  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  db_name               = var.db_name
  username              = var.db_username

  multi_az                     = var.db_multi_az
  backup_retention_period      = var.db_backup_retention_period
  deletion_protection          = var.db_deletion_protection
  skip_final_snapshot          = var.db_skip_final_snapshot
  apply_immediately            = var.db_apply_immediately
  performance_insights_enabled = var.db_performance_insights_enabled
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
