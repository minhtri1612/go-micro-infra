module "vpc" {
  source             = "../../modules/vpc"
  project_name       = var.project_name
  vpc_cidr           = var.vpc_cidr
  public_subnet_cidr = var.public_subnet_cidr
}

module "ec2_ssm" {
  source       = "../../modules/ec2-ssm"
  project_name = var.project_name
}

module "kind_host" {
  source = "../../modules/ubuntu-host"

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

# Jenkins lives on this EC2. First apply is local (Jenkins does not exist yet).
# Later Jenkins jobs apply THIS same stack — do not replace/destroy this instance
# or close SG :8080 without a local-apply fallback (see terraform/README.md).
# :8080 must be world-open so GitHub Cloud webhooks can hit generic-webhook-trigger
# (admin_ingress_cidr is only the laptop; GitHub IPs are not that /32).
module "jenkins_host" {
  source = "../../modules/ubuntu-host"

  name                 = "jenkins-host"
  project_name         = var.project_name
  instance_type        = var.jenkins_instance_type
  ami_arch             = "arm64"
  use_spot             = true
  subnet_id            = module.vpc.public_subnet_id
  vpc_id               = module.vpc.vpc_id
  iam_instance_profile = module.ec2_ssm.instance_profile_name
  ingress_cidr         = "0.0.0.0/0"
  allowed_tcp_ports    = [8080]
  root_volume_size     = var.jenkins_root_volume_size
  user_data            = file("${path.module}/cloud-init-jenkins.sh")
}

module "app_credentials" {
  source   = "../../modules/app-credentials"
  for_each = var.environments

  project_name                = var.project_name
  environment                 = each.value
  db_user                     = var.db_user
  db_password                 = var.db_password
  stripe_secret_key           = var.stripe_secret_key
  app_credentials_name_suffix = lookup(var.app_credentials_name_suffix_by_env, each.value, "")
  recovery_window_in_days     = var.secret_recovery_window_in_days
}

module "eso_iam" {
  source              = "../../modules/eso-iam"
  project_name        = var.project_name
  eso_iam_user_suffix = var.eso_iam_user_suffix
}
