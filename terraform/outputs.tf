output "ssh_ingress_cidr" {
  description = "CIDR allowed for SSH and lab ports (auto-detected when ssh_ingress_cidr is null)."
  value       = local.ssh_ingress_cidr
}

output "instance_public_ip" {
  description = "Public IP of the EC2 instance."
  value       = aws_instance.this.public_ip
}

output "instance_public_dns" {
  description = "Public DNS name of the EC2 instance."
  value       = aws_instance.this.public_dns
}

output "ssh_command" {
  description = "SSH command for the instance."
  value       = "ssh -i ../minhtri.pem ubuntu@${aws_instance.this.public_ip}"
}

output "argo_url" {
  description = "Argo CD URL after port-forward on the host."
  value       = "http://${aws_instance.this.public_ip}:18080"
}

output "jenkins_url" {
  description = "Jenkins URL after port-forward on the host."
  value       = "http://${aws_instance.this.public_ip}:18081"
}
