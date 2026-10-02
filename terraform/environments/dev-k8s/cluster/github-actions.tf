# ---------------------------------------------------------------------------
# GitHub Actions -> AWS, with OIDC and no access keys (docs/ARCHITECTURE.md §19.2).
#
# .github/workflows/cd.yml exchanges the job's GitHub OIDC token for one of
# two roles. Two, not one, because the two jobs present different subjects:
#
#   build-push  runs on main with no GitHub environment
#               sub = repo:<owner>/<repo>:ref:refs/heads/main
#   deploy      runs in the "dev" GitHub environment -- and a job with an
#               environment gets an environment subject INSTEAD of a ref one
#               sub = repo:<owner>/<repo>:environment:dev
#
# Each role trusts exactly one subject (StringEquals, no wildcards), so a fork,
# a pull request or a feature branch cannot assume either. The deploy role's
# branch restriction lives on the GitHub side: the "dev" environment's
# deployment branch policy allows main only (github_actions_setup output).
#
# Lives in this root, not a long-lived one, because everything the roles point
# at -- ECR, the cluster -- is created and destroyed with this session. IAM is
# free, so nothing here adds to cost_per_hour.
# ---------------------------------------------------------------------------

locals {
  github_oidc_url = "https://token.actions.githubusercontent.com"

  github_oidc_provider_arn = (
    var.create_github_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : data.aws_iam_openid_connect_provider.github[0].arn
  )

  # "repo:<owner>/<repo>" unless the repository issues immutable subjects, which
  # embed the owner and repository IDs (var.github_oidc_subject_prefix).
  github_subject_prefix = coalesce(var.github_oidc_subject_prefix, "repo:${var.github_repository}")

  github_role_subjects = {
    push   = "${local.github_subject_prefix}:ref:refs/heads/main"
    deploy = "${local.github_subject_prefix}:environment:${var.github_deploy_environment}"
  }
}

# One per AWS account. If the account already has it (another project's CI),
# set create_github_oidc_provider = false and it is looked up instead. No
# thumbprint_list: AWS validates GitHub's certificate itself, and the provider
# version the eks module requires (>= 5.95) makes the argument optional.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url            = local.github_oidc_url
  client_id_list = ["sts.amazonaws.com"]

  tags = {
    Name = "github-actions"
  }
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1

  url = local.github_oidc_url
}

data "aws_iam_policy_document" "github_trust" {
  for_each = local.github_role_subjects

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [each.value]
    }
  }
}

resource "aws_iam_role" "github" {
  for_each = local.github_role_subjects

  name                 = "${var.project}-${var.environment}-github-${each.key}"
  description          = "GitHub Actions (${each.value})"
  assume_role_policy   = data.aws_iam_policy_document.github_trust[each.key].json
  max_session_duration = 3600

  tags = {
    Name = "${var.project}-${var.environment}-github-${each.key}"
  }
}

# ---------------------------------------------------------------------------
# push: write to exactly the two repositories of this environment.
# DescribeImages lets cd.yml skip a SHA that is already pushed -- tags are
# IMMUTABLE, so pushing it again would fail rather than be a no-op.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "github_push" {
  statement {
    sid       = "RegistryLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # the action has no resource-level form
  }

  statement {
    sid = "PushThisEnvironmentsImages"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = values(module.ecr.repository_arns)
  }
}

resource "aws_iam_role_policy" "github_push" {
  name   = "ecr-push"
  role   = aws_iam_role.github["push"].id
  policy = data.aws_iam_policy_document.github_push.json
}

# ---------------------------------------------------------------------------
# deploy: find the cluster (update-kubeconfig), then act inside ONE namespace.
#
# The AWS side only admits the role to the cluster as a member of a
# Kubernetes group. What that group may do is ordinary RBAC, bound by
# ../platform to the app namespace alone. A managed access policy such as
# AmazonEKSAdminPolicy is not used: it does not cover CRDs, and the chart
# creates an ExternalSecret and a SecretStore.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "github_deploy" {
  statement {
    sid       = "DescribeThisCluster"
    actions   = ["eks:DescribeCluster"]
    resources = [module.eks.cluster_arn]
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "eks-describe"
  role   = aws_iam_role.github["deploy"].id
  policy = data.aws_iam_policy_document.github_deploy.json
}

resource "aws_eks_access_entry" "github_deploy" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.github["deploy"].arn
  type          = "STANDARD"

  # Must match deployers_group in ../platform, which binds it to a Role in
  # the app namespace. No access policy association: RBAC decides.
  kubernetes_groups = [var.github_deployers_group]
}
