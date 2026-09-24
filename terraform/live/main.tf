module "vpc" {
  source             = "../modules/vpc"
  project_name       = var.project_name
  vpc_cidr           = var.vpc_cidr
  public_subnet_cidr = var.public_subnet_cidr
}

module "ec2_ssm" {
  source       = "../modules/ec2-ssm"
  project_name = var.project_name
}

module "kind_host" {
  source = "../modules/ubuntu-host"

  name                 = "kind-host"
  project_name         = var.project_name
  instance_type        = var.kind_instance_type
  ami_arch             = "amd64"
  use_spot             = true
  subnet_id            = module.vpc.public_subnet_id
  vpc_id               = module.vpc.vpc_id
  iam_instance_profile = module.ec2_ssm.instance_profile_name
  ingress_cidr         = local.admin_ingress_cidr
  allowed_tcp_ports    = [18080]
  root_volume_size     = var.kind_root_volume_size
  user_data            = file("${path.module}/cloud-init-kind.sh")
}

module "jenkins_host" {
  source = "../modules/ubuntu-host"

  name                 = "jenkins-host"
  project_name         = var.project_name
  instance_type        = var.jenkins_instance_type
  ami_arch             = "arm64"
  use_spot             = true
  subnet_id            = module.vpc.public_subnet_id
  vpc_id               = module.vpc.vpc_id
  iam_instance_profile = module.ec2_ssm.instance_profile_name
  ingress_cidr         = local.admin_ingress_cidr
  allowed_tcp_ports    = [8080]
  root_volume_size     = var.jenkins_root_volume_size
  user_data            = file("${path.module}/cloud-init-jenkins.sh")
}
