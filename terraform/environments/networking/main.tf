# VPC peering, kept in its own state so applying a cluster stack never deletes
# the peering routes (the route tables there use ignore_changes = [route]).
#
#   management 10.0.0.0/16  <-> dev 10.1.0.0/16   (Argo CD, VPN reach)
#   management 10.0.0.0/16  <-> prod 10.2.0.0/16
#   jenkins    10.50.0.0/16 <-> dev / prod        (Jenkins talks to apiserver)
#
# dev and prod are optional: apply this right after the management stack and the
# missing legs are skipped.

data "aws_vpc" "management" {
  filter {
    name   = "tag:Name"
    values = ["${var.project_name}-vpc-management"]
  }
}

# The existing Kind/Jenkins VPC from environments/management.
data "aws_vpc" "jenkins" {
  filter {
    name   = "tag:Name"
    values = ["${var.project_name}-vpc"]
  }
}

data "aws_vpcs" "dev" {
  filter {
    name   = "tag:Name"
    values = ["${var.project_name}-vpc-dev"]
  }
}

data "aws_vpcs" "prod" {
  filter {
    name   = "tag:Name"
    values = ["${var.project_name}-vpc-prod"]
  }
}

data "aws_route_tables" "management_private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.management.id]
  }
  filter {
    name   = "tag:Name"
    values = ["${var.project_name}-private-rt-management"]
  }
}

# OpenVPN sits in a public subnet, so its route table needs the peering routes too.
data "aws_route_tables" "management_public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.management.id]
  }
  filter {
    name   = "tag:Name"
    values = ["${var.project_name}-public-rt-management"]
  }
}

data "aws_route_tables" "jenkins_public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.jenkins.id]
  }
  filter {
    name   = "tag:Name"
    values = ["${var.project_name}-public-rt"]
  }
}

data "aws_route_tables" "dev_private" {
  count = length(data.aws_vpcs.dev.ids) > 0 ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [tolist(data.aws_vpcs.dev.ids)[0]]
  }
  filter {
    name   = "tag:Name"
    values = ["${var.project_name}-private-rt-dev"]
  }
}

data "aws_route_tables" "prod_private" {
  count = length(data.aws_vpcs.prod.ids) > 0 ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [tolist(data.aws_vpcs.prod.ids)[0]]
  }
  filter {
    name   = "tag:Name"
    values = ["${var.project_name}-private-rt-prod"]
  }
}

locals {
  dev_vpc_id  = length(data.aws_vpcs.dev.ids) > 0 ? tolist(data.aws_vpcs.dev.ids)[0] : null
  prod_vpc_id = length(data.aws_vpcs.prod.ids) > 0 ? tolist(data.aws_vpcs.prod.ids)[0] : null

  mgmt_private_rt = tolist(data.aws_route_tables.management_private.ids)[0]
  mgmt_public_rt  = tolist(data.aws_route_tables.management_public.ids)[0]
  jenkins_rt      = tolist(data.aws_route_tables.jenkins_public.ids)[0]

  dev_private_rt  = local.dev_vpc_id != null ? tolist(data.aws_route_tables.dev_private[0].ids)[0] : null
  prod_private_rt = local.prod_vpc_id != null ? tolist(data.aws_route_tables.prod_private[0].ids)[0] : null

  has_dev  = local.dev_vpc_id != null ? 1 : 0
  has_prod = local.prod_vpc_id != null ? 1 : 0
}

resource "aws_vpc_peering_connection" "mgmt_dev" {
  count = local.has_dev

  vpc_id      = data.aws_vpc.management.id
  peer_vpc_id = local.dev_vpc_id
  auto_accept = true

  tags = {
    Name = "${var.project_name}-mgmt-dev"
  }
}

resource "aws_vpc_peering_connection" "mgmt_prod" {
  count = local.has_prod

  vpc_id      = data.aws_vpc.management.id
  peer_vpc_id = local.prod_vpc_id
  auto_accept = true

  tags = {
    Name = "${var.project_name}-mgmt-prod"
  }
}

resource "aws_vpc_peering_connection" "jenkins_dev" {
  count = local.has_dev

  vpc_id      = data.aws_vpc.jenkins.id
  peer_vpc_id = local.dev_vpc_id
  auto_accept = true

  tags = {
    Name = "${var.project_name}-jenkins-dev"
  }
}

resource "aws_vpc_peering_connection" "jenkins_prod" {
  count = local.has_prod

  vpc_id      = data.aws_vpc.jenkins.id
  peer_vpc_id = local.prod_vpc_id
  auto_accept = true

  tags = {
    Name = "${var.project_name}-jenkins-prod"
  }
}

# --- management -> dev / prod ---

resource "aws_route" "mgmt_private_to_dev" {
  count                     = local.has_dev
  route_table_id            = local.mgmt_private_rt
  destination_cidr_block    = var.dev_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.mgmt_dev[0].id
}

resource "aws_route" "mgmt_public_to_dev" {
  count                     = local.has_dev
  route_table_id            = local.mgmt_public_rt
  destination_cidr_block    = var.dev_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.mgmt_dev[0].id
}

resource "aws_route" "mgmt_private_to_prod" {
  count                     = local.has_prod
  route_table_id            = local.mgmt_private_rt
  destination_cidr_block    = var.prod_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.mgmt_prod[0].id
}

resource "aws_route" "mgmt_public_to_prod" {
  count                     = local.has_prod
  route_table_id            = local.mgmt_public_rt
  destination_cidr_block    = var.prod_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.mgmt_prod[0].id
}

# --- dev / prod -> management ---

resource "aws_route" "dev_to_mgmt" {
  count                     = local.has_dev
  route_table_id            = local.dev_private_rt
  destination_cidr_block    = var.management_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.mgmt_dev[0].id
}

resource "aws_route" "prod_to_mgmt" {
  count                     = local.has_prod
  route_table_id            = local.prod_private_rt
  destination_cidr_block    = var.management_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.mgmt_prod[0].id
}

# --- jenkins <-> dev / prod ---

resource "aws_route" "jenkins_to_dev" {
  count                     = local.has_dev
  route_table_id            = local.jenkins_rt
  destination_cidr_block    = var.dev_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.jenkins_dev[0].id
}

resource "aws_route" "dev_to_jenkins" {
  count                     = local.has_dev
  route_table_id            = local.dev_private_rt
  destination_cidr_block    = var.jenkins_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.jenkins_dev[0].id
}

resource "aws_route" "jenkins_to_prod" {
  count                     = local.has_prod
  route_table_id            = local.jenkins_rt
  destination_cidr_block    = var.prod_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.jenkins_prod[0].id
}

resource "aws_route" "prod_to_jenkins" {
  count                     = local.has_prod
  route_table_id            = local.prod_private_rt
  destination_cidr_block    = var.jenkins_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.jenkins_prod[0].id
}
