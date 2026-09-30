output "master_ids" {
  value = aws_instance.master[*].id
}

output "master_private_ips" {
  value = aws_instance.master[*].private_ip
}

output "worker_ids" {
  value = aws_instance.worker[*].id
}

output "worker_private_ips" {
  value = aws_instance.worker[*].private_ip
}
