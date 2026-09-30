data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc-${var.environment}"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-igw-${var.environment}"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${count.index + 1}-${var.environment}"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-private-${count.index + 1}-${var.environment}"
  }
}

# Private nodes reach SSM / Secrets Manager / registries through this NAT.
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip-${var.environment}"
  }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.project_name}-nat-${var.environment}"
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.project_name}-public-rt-${var.environment}"
  }

  # environments/networking adds the VPC peering routes to this table.
  lifecycle {
    ignore_changes = [route]
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = {
    Name = "${var.project_name}-private-rt-${var.environment}"
  }

  # environments/networking adds the VPC peering routes to this table.
  lifecycle {
    ignore_changes = [route]
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# --- Security groups ---
# The OpenVPN host is the only box reachable from the internet. Nodes accept SSH
# from that host, from the VPN pool and from the peered VPCs, never from outside.

resource "aws_security_group" "openvpn" {
  name        = "${var.project_name}-openvpn-sg-${var.environment}"
  description = "OpenVPN UDP 1194 + TCP 443 fallback + admin SSH"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "OpenVPN UDP"
    from_port   = 1194
    to_port     = 1194
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "OpenVPN TCP fallback"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Ansible bootstraps this host before any VPN exists, so SSH has to come from
  # the operator address directly.
  ingress {
    description = "SSH from the operator running Ansible"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ssh_cidr]
  }

  ingress {
    description = "SSH from VPN clients"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpn_client_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-openvpn-sg-${var.environment}"
  }
}

resource "aws_security_group" "node_common" {
  name        = "${var.project_name}-node-sg-${var.environment}"
  description = "Shared RKE2 node rules (SSH via jump, kubelet, CNI)"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "SSH from the OpenVPN jump host"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.openvpn.id]
  }

  ingress {
    description = "SSH from VPN clients"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpn_client_cidr]
  }

  ingress {
    description = "SSH between nodes"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = aws_subnet.private[*].cidr_block
  }

  # Ansible and the kubeconfig export run from the peered VPCs too.
  dynamic "ingress" {
    for_each = length(var.api_peer_cidrs) > 0 ? [1] : []
    content {
      description = "SSH from peered VPCs (management jump, Jenkins)"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.api_peer_cidrs
    }
  }

  ingress {
    description = "kubelet from nodes"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = aws_subnet.private[*].cidr_block
  }

  ingress {
    description = "Canal VXLAN between nodes"
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    cidr_blocks = aws_subnet.private[*].cidr_block
  }

  ingress {
    description = "Canal health check between nodes"
    from_port   = 9099
    to_port     = 9099
    protocol    = "tcp"
    cidr_blocks = aws_subnet.private[*].cidr_block
  }

  ingress {
    description = "ICMP from VPN clients"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.vpn_client_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-node-sg-${var.environment}"
  }
}

resource "aws_security_group" "web_nlb" {
  name        = "${var.project_name}-web-nlb-sg-${var.environment}"
  description = "Public NLB for Traefik"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-web-nlb-sg-${var.environment}"
  }
}

resource "aws_security_group" "master" {
  name        = "${var.project_name}-master-sg-${var.environment}"
  description = "RKE2 server: apiserver 6443 + supervisor 9345"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "apiserver from this VPC and VPN clients"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = concat([var.vpc_cidr], [var.vpn_client_cidr])
  }

  # Jenkins (10.50.0.0/16) and Argo CD in the management VPC talk to this apiserver
  # over VPC peering, so the peer CIDRs must be allowed explicitly.
  dynamic "ingress" {
    for_each = length(var.api_peer_cidrs) > 0 ? [1] : []
    content {
      description = "apiserver from peered VPCs (Argo CD / Jenkins)"
      from_port   = 6443
      to_port     = 6443
      protocol    = "tcp"
      cidr_blocks = var.api_peer_cidrs
    }
  }

  ingress {
    description = "RKE2 supervisor (node join)"
    from_port   = 9345
    to_port     = 9345
    protocol    = "tcp"
    cidr_blocks = aws_subnet.private[*].cidr_block
  }

  ingress {
    description = "etcd peer"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = aws_subnet.private[*].cidr_block
  }

  ingress {
    description     = "Traefik HTTP NodePort from web NLB"
    from_port       = var.http_node_port
    to_port         = var.http_node_port
    protocol        = "tcp"
    security_groups = [aws_security_group.web_nlb.id]
  }

  ingress {
    description     = "Traefik HTTPS NodePort from web NLB"
    from_port       = var.https_node_port
    to_port         = var.https_node_port
    protocol        = "tcp"
    security_groups = [aws_security_group.web_nlb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-master-sg-${var.environment}"
  }
}

resource "aws_security_group" "worker" {
  name        = "${var.project_name}-worker-sg-${var.environment}"
  description = "RKE2 agent: Traefik NodePorts from web NLB"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "Traefik HTTP NodePort from web NLB"
    from_port       = var.http_node_port
    to_port         = var.http_node_port
    protocol        = "tcp"
    security_groups = [aws_security_group.web_nlb.id]
  }

  ingress {
    description     = "Traefik HTTPS NodePort from web NLB"
    from_port       = var.https_node_port
    to_port         = var.https_node_port
    protocol        = "tcp"
    security_groups = [aws_security_group.web_nlb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-worker-sg-${var.environment}"
  }
}
