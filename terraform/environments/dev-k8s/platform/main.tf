# ---------------------------------------------------------------------------
# dev-k8s / platform -- root module 2 of 2 (docs/ARCHITECTURE.md §22.3).
#
# Installs the cluster add-ons the chart depends on:
#   - AWS Load Balancer Controller  (Ingress class "alb" -> an ALB)
#   - External Secrets Operator     (Secrets Manager -> Kubernetes Secret)
#
# A separate root module because the helm provider needs a cluster that
# already exists (see modules/eks/main.tf). It finds the cluster and the IRSA
# roles by NAME, with data sources, rather than reading ../cluster's state:
# that keeps the state bucket name -- and so the account ID -- out of every
# committed file. The consequence: `terraform plan` here only works once
# ../cluster has been applied. Before that, `terraform validate` is the check.
#
# The application itself is not installed here; that is Helm's job (§17).
# ---------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

locals {
  cluster_name = "${var.project}-${var.environment}"
}

data "aws_eks_cluster" "this" {
  name = local.cluster_name
}

data "aws_iam_role" "lb_controller" {
  name = "${local.cluster_name}-lb-controller"
}

data "aws_iam_role" "external_secrets" {
  name = "${local.cluster_name}-external-secrets"
}

# Tokens from `aws eks get-token` are short-lived; exec fetches a fresh one per
# run instead of baking one into the plan.
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", var.aws_region]
    }
  }
}

# ---------------------------------------------------------------------------
# AWS Load Balancer Controller
#
# Its IAM policy (modules/eks/lb-controller-iam-policy.json) is the upstream
# file for THIS chart version. Bump them together.
# ---------------------------------------------------------------------------

resource "helm_release" "lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.lb_controller_chart_version
  namespace  = "kube-system"

  values = [yamlencode({
    clusterName = local.cluster_name
    region      = var.aws_region
    vpcId       = data.aws_eks_cluster.this.vpc_config[0].vpc_id
    # Two replicas: the controller also runs the admission webhook, and a
    # single replica mid-restart rejects every Service/Ingress change.
    replicaCount = 2
    serviceAccount = {
      create = true
      # Must match the IRSA trust policy in modules/eks/main.tf.
      name = "aws-load-balancer-controller"
      annotations = {
        "eks.amazonaws.com/role-arn" = data.aws_iam_role.lb_controller.arn
      }
    }
  })]

  wait    = true
  timeout = 600
}

# ---------------------------------------------------------------------------
# External Secrets Operator
#
# The chart's SecretStore has no auth block, so the operator uses these IRSA
# credentials -- read-only, on exactly the two secrets the app needs.
# ---------------------------------------------------------------------------

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.external_secrets_chart_version
  namespace        = "external-secrets"
  create_namespace = true

  values = [yamlencode({
    installCRDs = true
    serviceAccount = {
      create = true
      # Must match the IRSA trust policy in modules/eks/main.tf.
      name = "external-secrets"
      annotations = {
        "eks.amazonaws.com/role-arn" = data.aws_iam_role.external_secrets.arn
      }
    }
  })]

  wait    = true
  timeout = 600

  # The controller's webhook must be serving before the operator's own
  # webhook Services are created.
  depends_on = [helm_release.lb_controller]
}
