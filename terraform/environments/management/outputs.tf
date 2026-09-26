output "admin_ingress_cidr" {
  value = local.admin_ingress_cidr
}

output "kind_instance_id" {
  value = module.kind_host.instance_id
}

output "kind_public_ip" {
  value = module.kind_host.public_ip
}

output "kind_ssm_command" {
  value = "aws ssm start-session --target ${module.kind_host.instance_id} --region ${var.aws_region}"
}

output "argo_url" {
  description = "Argo CD after port-forward on the Kind host (18080)."
  value       = "http://${module.kind_host.public_ip}:18080"
}

output "jenkins_instance_id" {
  value = module.jenkins_host.instance_id
}

output "jenkins_public_ip" {
  value = module.jenkins_host.public_ip
}

output "jenkins_ssm_command" {
  value = "aws ssm start-session --target ${module.jenkins_host.instance_id} --region ${var.aws_region}"
}

output "jenkins_url" {
  description = "Jenkins UI (GitHub webhooks need this reachable)."
  value       = "http://${module.jenkins_host.public_ip}:8080"
}

output "app_credentials_secret_names" {
  description = "AWS Secrets Manager names ESO remoteRef.key (go-micro/{env}/app-credentials)."
  value       = { for env, m in module.app_credentials : env => m.app_credentials_secret_name }
}

output "eso_iam_user_name" {
  value = module.eso_iam.eso_iam_user_name
}

output "eso_access_key_id" {
  value     = module.eso_iam.eso_access_key_id
  sensitive = true
}

output "eso_secret_access_key" {
  value     = module.eso_iam.eso_secret_access_key
  sensitive = true
}

output "hello_lambda_function_name" {
  value = aws_lambda_function.hello.function_name
}

output "hello_lambda_arn" {
  value = aws_lambda_function.hello.arn
}

output "tf_plan_iam_user" {
  value = aws_iam_user.tf_plan.name
}

output "tf_apply_iam_user" {
  value = aws_iam_user.tf_apply.name
}

output "tf_plan_access_key_id" {
  value     = aws_iam_access_key.tf_plan.id
  sensitive = true
}

output "tf_plan_secret_access_key" {
  value     = aws_iam_access_key.tf_plan.secret
  sensitive = true
}

output "tf_apply_access_key_id" {
  value     = aws_iam_access_key.tf_apply.id
  sensitive = true
}

output "tf_apply_secret_access_key" {
  value     = aws_iam_access_key.tf_apply.secret
  sensitive = true
}
