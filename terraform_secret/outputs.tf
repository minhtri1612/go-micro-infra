output "app_credentials_secret_names" {
  value = {
    for env, m in module.app_credentials : env => m.app_credentials_secret_name
  }
  description = "AWS secret names by environment"
}

output "app_credentials_secret_arns" {
  value = {
    for env, m in module.app_credentials : env => m.app_credentials_secret_arn
  }
}

output "eso_iam_user_name" {
  value       = aws_iam_user.eso.name
  description = "IAM user for External Secrets Operator"
}

output "eso_access_key_id" {
  value       = aws_iam_access_key.eso.id
  sensitive   = true
  description = "Use for aws-credentials secret key access-key-id"
}

output "eso_secret_access_key" {
  value       = aws_iam_access_key.eso.secret
  sensitive   = true
  description = "Use for aws-credentials secret key secret-access-key"
}
