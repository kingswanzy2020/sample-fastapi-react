# ---------------------------------------------------------------------------
# dev environment values
#
# NO SECRETS IN THIS FILE. It is committed, and everything in it also lands in
# Terraform state in plaintext. The application secret and the database password
# both live in Secrets Manager and are never seen by Terraform.
#
# Before the first apply:
#   1. cd ../../bootstrap && terraform init && terraform apply
#   2. terraform output -raw dev_backend_config > ../environments/dev/backend.hcl
#   3. cd ../environments/dev && terraform init -backend-config=backend.hcl
# ---------------------------------------------------------------------------

project        = "fastapi-react"
environment    = "dev"
aws_region     = "us-east-1"
repository_url = "https://github.com/kingswanzy2020/sample-fastapi-react"

# --- network ---------------------------------------------------------------
vpc_cidr             = "10.20.0.0/16"
availability_zones   = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs  = ["10.20.1.0/24", "10.20.2.0/24"]
private_subnet_cidrs = ["10.20.11.0/24", "10.20.12.0/24"]

# Nothing runs in a private subnet that needs outbound internet. ~$32/mo saved.
enable_nat_gateway = false

# --- compute ---------------------------------------------------------------
instance_type    = "t3.small"
root_volume_size = 30

# Access is via SSM Session Manager: no open port 22, no key to distribute, and
# every session logged to CloudTrail.
#
# To use SSH instead, set BOTH:
#   key_name          = "my-keypair"
#   ssh_allowed_cidrs = ["203.0.113.4/32"]   # curl -s https://checkip.amazonaws.com
#
# 0.0.0.0/0 here is rejected by a validation rule in the compute module.
key_name          = null
ssh_allowed_cidrs = []

app_allowed_cidrs = ["0.0.0.0/0"]
enable_https      = false # nothing terminates TLS on the box yet

# --- application deployment ------------------------------------------------
# The instance clones this repository on first boot to get the compose files.
# Images come from ECR, not from this clone.
#
# The ref MUST already contain the Dockerfiles, docker-compose.prod.yml and
# .env.example. Push the containerization work before applying.
app_repository_url = "https://github.com/kingswanzy2020/sample-fastapi-react.git"
app_repository_ref = "main"

# Tag deployed on first boot. Switch to a git SHA once CI is pushing images;
# redeploys after that are `sudo app-deploy <sha>` and need no Terraform run.
image_tag = "latest"

# MUTABLE while pushing "latest" by hand. Flip to IMMUTABLE once CI tags by SHA,
# which is what makes the tag a real guarantee of what is running.
ecr_image_tag_mutability = "MUTABLE"
ecr_keep_last_n_images   = 20

# 0 = a destroyed secret is purged immediately, so destroy/apply cycles work.
secret_recovery_window_days = 0

# --- database --------------------------------------------------------------
# true  -> RDS. The deploy script generates a compose overlay that removes the
#          postgres container and the dependencies on it.
# false -> the Postgres container from docker-compose.yml, password from the
#          same application secret. Saves ~$15/mo; no backups, no failover.
create_database = true

db_engine_version        = "16"
db_instance_class        = "db.t4g.micro"
db_allocated_storage     = 20
db_max_allocated_storage = 100
db_name                  = "app"
db_username              = "appuser" # "postgres" is reserved by RDS
db_port                  = 5432

db_multi_az                = false
db_backup_retention_period = 7
db_deletion_protection     = false # dev is disposable; prod is not
db_skip_final_snapshot     = true
db_apply_immediately       = true
