# Dev cluster: own VPC, private nodes only. No OpenVPN here — humans come in
# through the management VPN and VPC peering, Argo CD and Jenkins over peering.

module "network" {
  source = "../../modules/rke2-network"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  api_peer_cidrs       = var.api_peer_cidrs
  admin_ssh_cidr       = var.admin_ssh_cidr
}

module "iam" {
  source = "../../modules/rke2-iam"

  project_name = var.project_name
  environment  = var.environment
}

module "keys" {
  source = "../../modules/keys"

  project_name = var.project_name
  environment  = var.environment
  key_filename = "${path.module}/rke2-key-${var.environment}.pem"
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
  key_name             = module.keys.key_name

  api_dns_name               = module.lb.api_dns_name
  api_target_group_arn       = module.lb.api_target_group_arn
  web_http_target_group_arn  = module.lb.web_http_target_group_arn
  web_https_target_group_arn = module.lb.web_https_target_group_arn
}
