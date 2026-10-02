output "admin_ingress_cidr" {
  value = local.admin_ingress_cidr
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

output "hello_java_lambda_function_name" {
  value = aws_lambda_function.hello_java.function_name
}

output "hello_java_lambda_arn" {
  value = aws_lambda_function.hello_java.arn
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
