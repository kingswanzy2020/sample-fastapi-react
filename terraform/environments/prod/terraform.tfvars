# ---------------------------------------------------------------------------
# prod environment values
#
# NO SECRETS IN THIS FILE. It is committed, and everything in it also lands in
# Terraform state in plaintext.
#
# Before the first apply:
#   cd ../../bootstrap && terraform apply
#   terraform output -raw prod_backend_config > ../environments/prod/backend.hcl
#   cd ../environments/prod && terraform init -backend-config=backend.hcl
# ---------------------------------------------------------------------------

project        = "fastapi-react"
environment    = "prod"
aws_region     = "us-east-1"
repository_url = "https://github.com/kingswanzy2020/sample-fastapi-react"

# --- network ---------------------------------------------------------------
# A different CIDR from dev, so the two VPCs can be peered later without
# renumbering either of them.
vpc_cidr            = "10.30.0.0/16"
availability_zones  = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs = ["10.30.1.0/24", "10.30.2.0/24"]

# /20 rather than /24: if these subnets ever host EKS nodes, the VPC CNI gives
# every pod a real VPC IP, and a /24 runs out of addresses long before it runs
# out of CPU.
private_subnet_cidrs = ["10.30.16.0/20", "10.30.32.0/20"]

# Still false: RDS makes no outbound calls. Flip to true when private-subnet
# workloads (EKS nodes) need to pull images. ~$32/mo.
enable_nat_gateway = false

# --- compute ---------------------------------------------------------------
instance_type    = "t3.medium"
root_volume_size = 50

# Pin the AMI for production. Leave null for the first apply, then set this to
# the resolved value from `terraform output ami_id` so rebuilds are reproducible.
ami_id = null

# No SSH in production. SSM Session Manager needs no open port, no key
# distribution, and logs every session to CloudTrail.
key_name          = null
ssh_allowed_cidrs = []

app_allowed_cidrs = ["0.0.0.0/0"]
enable_https      = true

# --- application deployment ------------------------------------------------
app_repository_url = "https://github.com/kingswanzy2020/sample-fastapi-react.git"

# Pin production to a tag, not a moving branch.
app_repository_ref = "main"

# ALWAYS a git SHA in production. "latest" makes "which version is running?"
# unanswerable and turns rollback into guesswork.
image_tag = "latest"

# IMMUTABLE: a tag that cannot be overwritten is what makes it a real guarantee
# of what is running.
ecr_image_tag_mutability = "IMMUTABLE"
ecr_keep_last_n_images   = 50

# 30 days: a secret deleted by mistake can be restored.
secret_recovery_window_days = 30

# --- database --------------------------------------------------------------
create_database = true

db_engine_version        = "16"
db_instance_class        = "db.t4g.small"
db_allocated_storage     = 50
db_max_allocated_storage = 500
db_name                  = "app"
db_username              = "appuser"
db_port                  = 5432

# Multi-AZ roughly doubles the database cost. It is the difference between an
# AZ failure being a failover and being an outage.
db_multi_az                     = true
db_backup_retention_period      = 30
db_deletion_protection          = true
db_skip_final_snapshot          = false
db_apply_immediately            = false # changes wait for the maintenance window
db_performance_insights_enabled = true
