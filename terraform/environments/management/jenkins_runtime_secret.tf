resource "aws_secretsmanager_secret" "jenkins_runtime" {
  name                    = "${var.project_name}/jenkins/runtime"
  description             = "Jenkins compose/CasC runtime. Seed JSON in the AWS console; Terraform does not store PAT/passwords in state."
  recovery_window_in_days = var.secret_recovery_window_in_days
}

module "jenkins_iam" {
  source = "../../modules/jenkins-iam"

  project_name               = var.project_name
  aws_region                 = var.aws_region
  kind_instance_id           = module.kind_host.instance_id
  jenkins_runtime_secret_arn = aws_secretsmanager_secret.jenkins_runtime.arn
}
