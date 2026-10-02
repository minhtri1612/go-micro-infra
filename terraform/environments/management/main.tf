# RETIRED Kind lab (VPC 10.50). AWS resources were destroyed 2026-09-30.
# Do not apply this root — it would recreate that VPC. Clusters live in rke2-*.

module "vpc" {
  source             = "../../modules/vpc"
  project_name       = var.project_name
  vpc_cidr           = var.vpc_cidr
  public_subnet_cidr = var.public_subnet_cidr
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
