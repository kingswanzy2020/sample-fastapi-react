# ---------------------------------------------------------------------------
# dev-k8s / cluster values -- the EKS validation run.
#
# NO SECRETS IN THIS FILE. It is committed and lands in state in plaintext.
# The app secret and the RDS password live in Secrets Manager only.
#
# Lifecycle: one session. apply -> validate (§22.5) -> destroy the same day.
# ---------------------------------------------------------------------------

project        = "fastapi-react"
environment    = "dev-k8s"
aws_region     = "us-east-1"
repository_url = "https://github.com/kingswanzy2020/sample-fastapi-react"

# --- network ---------------------------------------------------------------
vpc_cidr             = "10.30.0.0/16"
availability_zones   = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs  = ["10.30.0.0/24", "10.30.1.0/24"]
private_subnet_cidrs = ["10.30.16.0/20", "10.30.32.0/20"] # sized for pod IPs

# --- cluster ---------------------------------------------------------------
# Standard support only; check before each session:
#   aws eks describe-cluster-versions --status STANDARD_SUPPORT --query 'clusterVersions[].clusterVersion'
kubernetes_version = "1.34"

# Narrow to your own address for the session (IAM auth applies either way):
#   endpoint_public_access_cidrs = ["203.0.113.4/32"]   # curl -s https://checkip.amazonaws.com
endpoint_public_access_cidrs = ["0.0.0.0/0"]

node_instance_types = ["t3.medium"]
node_min_size       = 2
node_desired_size   = 2
node_max_size       = 4

# --- database --------------------------------------------------------------
db_instance_class = "db.t4g.micro"
db_name           = "app"     # = database.name in values-eks.yaml
db_username       = "appuser" # "postgres" is reserved by RDS
