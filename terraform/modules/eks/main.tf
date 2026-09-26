# ---------------------------------------------------------------------------
# EKS -- the cluster, one managed node group, and the IAM roles the two
# in-cluster AWS controllers assume. docs/ARCHITECTURE.md §22.3.
#
# The cluster itself is the community module: an EKS cluster is ~40
# interlocking resources (IAM roles, the OIDC provider, security group rules,
# launch templates, add-ons) and the module encodes their edge cases. Pinned to
# v20, the last major that supports the AWS provider 5.x this repo is on.
#
# What this module deliberately does NOT do: install anything into the cluster.
# The kubernetes/helm providers need the cluster's endpoint and a token, which
# do not exist until this has been applied -- configuring them from these
# outputs makes plan fail before the cluster exists and destroy fail after.
# In-cluster add-ons live in a second root module
# (environments/dev-k8s/platform); the application is Helm's job.
# ---------------------------------------------------------------------------

locals {
  name = "${var.project}-${var.environment}"

  # IRSA: each controller's Kubernetes service account may assume exactly one
  # IAM role, and nothing else may. The namespace and service account names
  # here must match what environments/dev-k8s/platform installs.
  service_accounts = {
    lb-controller = {
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
      policy          = file("${path.module}/lb-controller-iam-policy.json")
    }
    external-secrets = {
      namespace       = "external-secrets"
      service_account = "external-secrets"
      policy          = data.aws_iam_policy_document.external_secrets.json
    }
  }
}

module "cluster" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = local.name
  cluster_version = var.kubernetes_version

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  # Public endpoint so kubectl works from a laptop and from GitHub Actions,
  # narrowed by CIDR and always behind IAM authentication.
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  # Access entries only (no aws-auth ConfigMap). Whoever runs `apply` becomes
  # cluster admin; add more principals as access entries, not by editing YAML.
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true

  # Envelope encryption: Kubernetes Secrets are encrypted in etcd with a KMS key
  # the module creates. Short deletion window because this cluster is
  # destroyed after every validation session.
  cluster_encryption_config       = { resources = ["secrets"] }
  kms_key_deletion_window_in_days = 7

  cloudwatch_log_group_retention_in_days = var.log_retention_days

  cluster_addons = {
    # before_compute: the CNI must exist before nodes join, or they come up
    # NotReady with no pod networking.
    vpc-cni    = { before_compute = true }
    kube-proxy = {}
    coredns    = {}
    # For the HPA and `kubectl top`. Locally scripts/k8s/addons.sh installs it.
    metrics-server = {}
  }

  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = var.node_min_size
      desired_size = var.node_desired_size
      max_size     = var.node_max_size

      # Spread across every subnet passed in -- one per AZ -- so losing an AZ
      # cannot take every replica.
      subnet_ids = var.subnet_ids
    }
  }
}

# ---------------------------------------------------------------------------
# IRSA roles for the in-cluster controllers
#
# No AWS access keys ever enter the cluster. A pod running as the named service
# account exchanges its projected token with STS for this role's credentials;
# the sub condition pins the role to that one service account.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "irsa_trust" {
  for_each = local.service_accounts

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.cluster.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.cluster.oidc_provider}:sub"
      values   = ["system:serviceaccount:${each.value.namespace}:${each.value.service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.cluster.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "irsa" {
  for_each = local.service_accounts

  # Deterministic: environments/dev-k8s/platform looks these up by name.
  name               = "${local.name}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.irsa_trust[each.key].json

  tags = {
    Name = "${local.name}-${each.key}"
  }
}

resource "aws_iam_role_policy" "irsa" {
  for_each = local.service_accounts

  name   = each.key
  role   = aws_iam_role.irsa[each.key].id
  policy = each.value.policy
}

# The AWS Load Balancer Controller policy (lb-controller-iam-policy.json) is
# the upstream file for the pinned controller version, v3.5.0:
#   https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v3.5.0/docs/install/iam_policy.json
# Replace it whenever the controller chart version in platform/ is bumped.

# External Secrets Operator: read-only, on exactly the secrets it syncs.
data "aws_iam_policy_document" "external_secrets" {
  statement {
    sid = "ReadApplicationSecrets"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds",
    ]
    resources = var.external_secrets_secret_arns
  }
}
