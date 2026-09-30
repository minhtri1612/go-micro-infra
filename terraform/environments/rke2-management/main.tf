# Management cluster: Argo CD + monitoring hub. No app workloads.
# OpenVPN lives here only; dev/prod are reached over VPC peering.

module "network" {
  source = "../../modules/rke2-network"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

module "iam" {
  source = "../../modules/rke2-iam"

  project_name = var.project_name
  environment  = var.environment
}

module "token" {
  source = "../../modules/rke2-token"

  project_name = var.project_name
  environment  = var.environment
}

module "lb" {
  source = "../../modules/rke2-lb"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.network.vpc_id
  public_subnet_ids  = module.network.public_subnet_ids
  private_subnet_ids = module.network.private_subnet_ids
  web_nlb_sg_id      = module.network.web_nlb_sg_id
}

module "nodes" {
  source = "../../modules/rke2-nodes"

  project_name         = var.project_name
  environment          = var.environment
  rke2_version         = var.rke2_version
  rke2_token           = module.token.token
  worker_count         = var.worker_count
  master_instance_type = var.master_instance_type
  worker_instance_type = var.worker_instance_type
  use_spot             = var.use_spot

  private_subnet_ids   = module.network.private_subnet_ids
  node_common_sg_id    = module.network.node_common_sg_id
  master_sg_id         = module.network.master_sg_id
  worker_sg_id         = module.network.worker_sg_id
  iam_instance_profile = module.iam.instance_profile_name

  api_dns_name               = module.lb.api_dns_name
  api_target_group_arn       = module.lb.api_target_group_arn
  web_http_target_group_arn  = module.lb.web_http_target_group_arn
  web_https_target_group_arn = module.lb.web_https_target_group_arn
}

module "openvpn" {
  source = "../../modules/openvpn"

  project_name         = var.project_name
  environment          = var.environment
  instance_type        = var.openvpn_instance_type
  subnet_id            = module.network.public_subnet_ids[0]
  security_group_id    = module.network.openvpn_sg_id
  iam_instance_profile = module.iam.instance_profile_name
}

# Reply path for VPN clients: private nodes send 10.8.0.0/24 back through the
# OpenVPN ENI instead of the NAT gateway.
resource "aws_route" "vpn_reply" {
  route_table_id         = module.network.private_route_table_id
  destination_cidr_block = "10.8.0.0/24"
  network_interface_id   = module.openvpn.primary_network_interface_id
}
