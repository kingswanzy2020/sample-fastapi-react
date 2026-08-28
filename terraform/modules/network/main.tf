# ---------------------------------------------------------------------------
# Network -- VPC, public and private subnets, routing.
#
# Public subnets host the application instance and (later) a load balancer.
# Private subnets host RDS and are reserved for EKS node groups.
# ---------------------------------------------------------------------------

locals {
  name = "${var.project}-${var.environment}"

  # Zip AZs with their CIDRs so the subnet resources can use for_each with a
  # stable key. Using for_each rather than count means removing the first AZ
  # does not force the recreation of every subnet after it.
  public_subnets = {
    for idx, az in var.availability_zones : az => var.public_subnet_cidrs[idx]
  }

  private_subnets = {
    for idx, az in var.availability_zones : az => var.private_subnet_cidrs[idx]
  }
}

resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr

  # Both are required for RDS private DNS names to resolve inside the VPC.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name}-vpc"
  }
}

# ---------------------------------------------------------------------------
# Internet gateway + public routing
# ---------------------------------------------------------------------------

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name}-igw"
  }
}

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key

  # The application instance needs a public IP to be reachable without an ALB.
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name}-public-${each.key}"
    Tier = "public"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name}-public-rt"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Private subnets
#
# One route table per AZ. This looks like overkill while there is no NAT
# Gateway, but a NAT lives in a single AZ -- so the moment you enable one you
# want each AZ routing through its own (or at minimum you want the option
# without restructuring). Sharing one table across AZs is the setup that makes
# a single-AZ NAT failure take down every private subnet.
# ---------------------------------------------------------------------------

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = {
    Name = "${local.name}-private-${each.key}"
    Tier = "private"
  }
}

resource "aws_route_table" "private" {
  for_each = local.private_subnets

  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name}-private-rt-${each.key}"
  }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

# ---------------------------------------------------------------------------
# Optional NAT gateway
#
# Single NAT in the first public subnet. Cheaper than one-per-AZ and adequate
# for a non-production environment; a production setup with real availability
# requirements should create one per AZ.
# ---------------------------------------------------------------------------

resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? 1 : 0

  domain = "vpc"

  tags = {
    Name = "${local.name}-nat-eip"
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = var.enable_nat_gateway ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[var.availability_zones[0]].id

  tags = {
    Name = "${local.name}-nat"
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route" "private_nat" {
  for_each = var.enable_nat_gateway ? local.private_subnets : {}

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}
