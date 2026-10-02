output "token" {
  value     = random_password.rke2_token.result
  sensitive = true
}

output "secret_arn" {
  value = aws_secretsmanager_secret.rke2_token.arn
}
