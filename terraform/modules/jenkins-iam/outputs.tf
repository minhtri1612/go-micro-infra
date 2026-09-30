output "instance_profile_name" {
  value = aws_iam_instance_profile.jenkins.name
}

output "role_name" {
  value = aws_iam_role.jenkins.name
}
