# ---------------------------------------------------------------------------
# Compute -- EC2 instance, security groups, IAM instance profile, Elastic IP,
# and the deploy mechanism that turns the box into a running application.
#
# Division of labour:
#   user_data   runs once, installs Docker, fetches compose files, writes the
#               deploy script and a systemd unit. Cannot converge.
#   app-deploy  runs any number of times, reads secrets, pulls images, starts
#               the stack. This is the part that is actually repeatable.
# ---------------------------------------------------------------------------

locals {
  name         = "${var.project}-${var.environment}"
  service_name = "${var.project}-${var.environment}"
}

# ---------------------------------------------------------------------------
# AMI lookup
# ---------------------------------------------------------------------------

data "aws_ami" "ubuntu" {
  count = var.ami_id == null ? 1 : 0

  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  ami_id = var.ami_id != null ? var.ami_id : data.aws_ami.ubuntu[0].id
}

# ---------------------------------------------------------------------------
# Security groups
#
# Two groups rather than one, so "who can reach the app" and "who can administer
# the box" stay separately auditable. The SSH group is not created at all when
# ssh_allowed_cidrs is empty.
# ---------------------------------------------------------------------------

resource "aws_security_group" "web" {
  # name_prefix, not name: with create_before_destroy a fixed name deadlocks,
  # because AWS refuses two security groups with the same name in one VPC.
  name_prefix = "${local.name}-web-"
  description = "Inbound HTTP/HTTPS to the application"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name}-web"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  for_each = toset(var.app_allowed_cidrs)

  security_group_id = aws_security_group.web.id
  description       = "HTTP from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"

  tags = {
    Name = "${local.name}-http"
  }
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  for_each = var.enable_https ? toset(var.app_allowed_cidrs) : toset([])

  security_group_id = aws_security_group.web.id
  description       = "HTTPS from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"

  tags = {
    Name = "${local.name}-https"
  }
}

# Unrestricted egress: the instance pulls container images from ECR, OS packages
# from the internet, and talks to the AWS APIs. Tightening this means VPC
# endpoints for ECR, S3, SSM and Secrets Manager -- worth doing eventually,
# overkill for a single-instance environment.
resource "aws_vpc_security_group_egress_rule" "web_all" {
  security_group_id = aws_security_group.web.id
  description       = "All outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = {
    Name = "${local.name}-egress"
  }
}

resource "aws_security_group" "ssh" {
  count = length(var.ssh_allowed_cidrs) > 0 ? 1 : 0

  name_prefix = "${local.name}-ssh-"
  description = "Inbound SSH from a restricted set of CIDRs"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name}-ssh"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = toset(var.ssh_allowed_cidrs)

  security_group_id = aws_security_group.ssh[0].id
  description       = "SSH from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"

  tags = {
    Name = "${local.name}-ssh"
  }
}

# ---------------------------------------------------------------------------
# IAM -- instance profile
#
# SSM Session Manager means shell access with no open port, no key distribution,
# and every session logged to CloudTrail. ECR read-only lets the box pull images.
# Secrets access is scoped to the exact two secrets this application needs.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${local.name}-instance"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = {
    Name = "${local.name}-instance"
  }
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

locals {
  # Only the secrets this instance actually reads. Not a blanket
  # secretsmanager:GetSecretValue on "*".
  readable_secret_arns = compact([
    var.app_secret_arn,
    var.db_secret_arn,
  ])
}

data "aws_iam_policy_document" "read_secrets" {
  statement {
    sid    = "ReadApplicationSecrets"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]

    # The RDS-managed secret ARN carries a random 6-character suffix that can
    # change when the secret is replaced, so match it as a prefix.
    resources = [for arn in local.readable_secret_arns : "${arn}*"]
  }

  # Secrets Manager encrypts with a KMS key; reading a secret requires
  # permission to decrypt through the Secrets Manager service specifically.
  statement {
    sid       = "DecryptViaSecretsManager"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = ["*"]

    condition {
      test     = "StringLike"
      variable = "kms:ViaService"
      values   = ["secretsmanager.*.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "read_secrets" {
  name   = "${local.name}-read-secrets"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.read_secrets.json
}

resource "aws_iam_instance_profile" "this" {
  name = "${local.name}-instance"
  role = aws_iam_role.instance.name
}

# ---------------------------------------------------------------------------
# Deploy script
#
# Rendered here and embedded in user_data, so the instance is self-contained:
# every value it needs (region, secret ARNs, registry, database host) is baked
# in at creation, and re-deploying needs no Terraform run.
# ---------------------------------------------------------------------------

locals {
  deploy_script = templatefile("${path.module}/deploy.sh.tftpl", {
    aws_region      = var.aws_region
    app_directory   = var.app_directory
    app_secret_arn  = var.app_secret_arn
    db_secret_arn   = var.db_secret_arn
    registry_prefix = var.registry_prefix
    use_rds         = var.use_rds ? "true" : "false"
    db_host         = var.db_host
    db_port         = var.db_port
    db_name         = var.db_name
    db_user         = var.db_user
  })
}

# ---------------------------------------------------------------------------
# Instance
# ---------------------------------------------------------------------------

resource "aws_instance" "app" {
  ami           = local.ami_id
  instance_type = var.instance_type
  subnet_id     = var.subnet_id
  key_name      = var.key_name

  vpc_security_group_ids = compact([
    aws_security_group.web.id,
    length(var.ssh_allowed_cidrs) > 0 ? aws_security_group.ssh[0].id : "",
  ])

  iam_instance_profile = aws_iam_instance_profile.this.name

  root_block_device {
    volume_type           = "gp3" # cheaper than gp2, 3000 baseline IOPS regardless of size
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "${local.name}-root"
    }
  }

  # IMDSv2 required. Without this, any server-side request forgery in the
  # application can read the instance's IAM credentials from the metadata
  # endpoint with a plain GET -- and this role can read the application secrets.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    hostname       = local.name
    service_name   = local.service_name
    app_directory  = var.app_directory
    image_tag      = var.image_tag
    repository_url = var.repository_url
    repository_ref = var.repository_ref
    deploy_script  = local.deploy_script
  })

  # user_data only ever runs on first boot, so replacing a running instance to
  # apply a change to it is almost never what you want. The repeatable half of
  # deployment lives in app-deploy, which can simply be re-run.
  user_data_replace_on_change = false

  monitoring = false

  tags = {
    Name = "${local.name}-app"
  }

  lifecycle {
    # The AMI data source is most_recent, so Canonical publishing a new image
    # would otherwise propose destroying a running instance on an unrelated
    # apply. Replacing the box is a deliberate act: either pin var.ami_id, or
    # `terraform taint` this resource on purpose.
    #
    # user_data is ignored for the same reason -- changing the deploy script
    # should not silently rebuild the server. Re-run app-deploy instead, or
    # taint when the first-boot sequence itself genuinely changed.
    ignore_changes = [ami, user_data]
  }
}

# A static IP that survives stop/start, so DNS records and any inventory file
# stay valid across instance reboots.
resource "aws_eip" "app" {
  domain   = "vpc"
  instance = aws_instance.app.id

  tags = {
    Name = "${local.name}-app"
  }

  depends_on = [aws_instance.app]
}
