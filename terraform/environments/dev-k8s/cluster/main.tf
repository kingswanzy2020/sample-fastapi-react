# ---------------------------------------------------------------------------
# dev-k8s / cluster -- root module 1 of 2 for the EKS validation run
# (docs/ARCHITECTURE.md §22).
#
# Everything AWS-side: VPC with NAT, EKS + node group, RDS, ECR, the app
# secret container, and the IRSA roles. Nothing inside the cluster -- that is
# ../platform, applied after this one, for the provider-chaining reason in
# modules/eks/main.tf.
#
# This environment is meant to exist for one session: apply, validate,
# destroy the same day. See the cost_per_hour output.
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
# Application secret -- Terraform owns the container, never the value.
# Same pattern as environments/dev: the value is set once, out of band, and
# never enters state. External Secrets Operator reads it from inside the
# cluster. See the set_app_secret_command output.
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "app" {
  name        = "${var.project}/${var.environment}/app"
  description = "Application secrets for ${var.project} ${var.environment}: SECRET_KEY"

  # Purge on destroy, so the next session's apply can recreate the same name.
  recovery_window_in_days = 0

  tags = {
    Name = "${var.project}-${var.environment}-app"
  }
}

# ---------------------------------------------------------------------------
# Modules
# ---------------------------------------------------------------------------

module "network" {
  source = "../../../modules/network"

  project     = var.project
  environment = var.environment

  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  # Required here, unlike environments/dev: the nodes sit in private subnets
  # and must reach ECR, the EKS API and Secrets Manager.
  enable_nat_gateway = true

  # How the AWS Load Balancer Controller finds where to put load balancers.
  public_subnet_tags  = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }
}

module "ecr" {
  source = "../../../modules/ecr"

  project     = var.project
  environment = var.environment

  repositories = ["backend", "frontend"]

  # Git-SHA tags only, so the registry itself forbids overwriting one (§20.1).
  image_tag_mutability = "IMMUTABLE"
  keep_last_n_images   = 30

  # Destroyed with the rest at the end of each session.
  force_delete = true
}

module "eks" {
  source = "../../../modules/eks"

  project     = var.project
  environment = var.environment

  kubernetes_version           = var.kubernetes_version
  vpc_id                       = module.network.vpc_id
  subnet_ids                   = module.network.private_subnet_ids
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  node_instance_types = var.node_instance_types
  node_min_size       = var.node_min_size
  node_desired_size   = var.node_desired_size
  node_max_size       = var.node_max_size

  external_secrets_secret_arns = [
    aws_secretsmanager_secret.app.arn,
    module.database.master_user_secret_arn,
  ]
}

module "database" {
  source = "../../../modules/database"

  project     = var.project
  environment = var.environment

  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.private_subnet_ids

  # Pods use the nodes' ENIs (VPC CNI), so the node security group is the
  # source of all pod traffic to Postgres.
  allowed_security_group_ids = [module.eks.node_security_group_id]

  engine_version    = "16"
  instance_class    = var.db_instance_class
  allocated_storage = 20
  db_name           = var.db_name
  username          = var.db_username

  # Validation run: single-AZ, disposable. A real production environment sets
  # multi_az = true and deletion_protection = true.
  multi_az                = false
  backup_retention_period = 1
  deletion_protection     = false
  skip_final_snapshot     = true
  apply_immediately       = true
}
