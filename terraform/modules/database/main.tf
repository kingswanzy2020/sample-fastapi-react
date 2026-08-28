# ---------------------------------------------------------------------------
# Database -- RDS PostgreSQL in the private subnets.
#
# The master password is never handled by Terraform. `manage_master_user_password`
# tells RDS to generate it, store it in Secrets Manager, and own its rotation.
# Terraform state holds only the secret's ARN.
#
# That matters because Terraform state is plaintext: any password passed through
# a variable, a .tfvars file, or a random_password resource ends up readable by
# anyone with access to the state file.
# ---------------------------------------------------------------------------

locals {
  name = "${var.project}-${var.environment}"

  # RDS wants the family (postgres16), the engine_version variable holds the
  # major version (16). Derive one from the other so they cannot drift apart.
  parameter_group_family = "postgres${split(".", var.engine_version)[0]}"
}

# ---------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name        = "${local.name}-db"
  description = "Private subnets for ${local.name}"
  subnet_ids  = var.subnet_ids

  tags = {
    Name = "${local.name}-db"
  }
}

# ---------------------------------------------------------------------------
# Security group
#
# No CIDR rules and no public access: the only way in is from a security group
# that has been explicitly granted. There is deliberately no egress rule --
# Postgres has no reason to originate outbound connections.
# ---------------------------------------------------------------------------

resource "aws_security_group" "db" {
  # name_prefix, not name: with create_before_destroy a fixed name deadlocks,
  # because AWS refuses two security groups with the same name in one VPC.
  name_prefix = "${local.name}-db-"
  description = "PostgreSQL access for ${local.name}"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${local.name}-db"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "postgres" {
  for_each = toset(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL from ${each.value}"
  referenced_security_group_id = each.value
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"

  tags = {
    Name = "${local.name}-postgres"
  }
}

# ---------------------------------------------------------------------------
# Parameters
# ---------------------------------------------------------------------------

resource "aws_db_parameter_group" "this" {
  # name_prefix so a parameter change can create the replacement before
  # destroying the old group, which the instance is still attached to.
  name_prefix = "${local.name}-pg-"
  family      = local.parameter_group_family
  description = "Parameter group for ${local.name}"

  parameter {
    name  = "log_min_duration_statement"
    value = tostring(var.log_min_duration_statement)
  }

  # Log every connection teardown reason. Cheap, and the first thing you want
  # when the application starts reporting dropped connections.
  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  tags = {
    Name = "${local.name}-pg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Instance
# ---------------------------------------------------------------------------

resource "aws_db_instance" "this" {
  identifier = "${local.name}-postgres"

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = var.db_name
  username = var.username

  # RDS generates the password, stores it in Secrets Manager, and rotates it.
  # Do not set `password` alongside this -- the two are mutually exclusive.
  manage_master_user_password = true

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage > 0 ? var.max_allocated_storage : null
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  port                   = 5432

  multi_az                = var.multi_az
  backup_retention_period = var.backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"
  copy_tags_to_snapshot   = true

  parameter_group_name = aws_db_parameter_group.this.name

  # Minor versions are patched automatically inside the maintenance window;
  # major version upgrades stay a deliberate, reviewed change.
  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? 7 : null
  enabled_cloudwatch_logs_exports       = ["postgresql", "upgrade"]

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.name}-final-${formatdate("YYYYMMDDhhmmss", timestamp())}"

  apply_immediately = var.apply_immediately

  tags = {
    Name = "${local.name}-postgres"
  }

  lifecycle {
    ignore_changes = [
      # timestamp() re-evaluates on every plan, which would otherwise show a
      # permanent diff on this attribute.
      final_snapshot_identifier,
    ]
  }
}
