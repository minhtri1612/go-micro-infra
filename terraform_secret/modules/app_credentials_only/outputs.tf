output "app_credentials_secret_name" {
  value       = aws_secretsmanager_secret.app_credentials.name
  description = "AWS secret name for ExternalSecret remoteRef.key"
}

output "app_credentials_secret_arn" {
  value       = aws_secretsmanager_secret.app_credentials.arn
  description = "ARN of app credentials secret"
}
