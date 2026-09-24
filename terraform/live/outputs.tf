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
