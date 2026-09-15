output "eso_iam_user_name" {
  value = aws_iam_user.eso.name
}

output "eso_access_key_id" {
  value     = aws_iam_access_key.eso.id
  sensitive = true
}

output "eso_secret_access_key" {
  value     = aws_iam_access_key.eso.secret
  sensitive = true
}
