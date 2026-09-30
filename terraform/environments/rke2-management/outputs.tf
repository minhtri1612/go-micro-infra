output "vpc_id" {
  value = module.network.vpc_id
}

output "master_instance_ids" {
  description = "SSM targets for kubeconfig export and node debugging"
  value       = module.nodes.master_ids
}

output "master_private_ips" {
  value = module.nodes.master_private_ips
}

output "worker_instance_ids" {
  value = module.nodes.worker_ids
}

output "api_dns_name" {
  description = "Internal NLB for the Kubernetes API (reachable over VPN / peering)"
  value       = module.lb.api_dns_name
}

output "web_dns_name" {
  description = "Public NLB in front of the Traefik NodePorts"
  value       = module.lb.web_dns_name
}

output "openvpn_public_ip" {
  value = module.openvpn.public_ip
}

output "openvpn_instance_id" {
  description = "SSH jump / Ansible target for the OpenVPN gateway"
  value       = module.openvpn.instance_id
}

output "jenkins_public_ip" {
  value = module.jenkins.public_ip
}

output "jenkins_instance_id" {
  value = module.jenkins.instance_id
}

output "jenkins_url" {
  value = "http://${module.jenkins.public_ip}:8080"
}

output "ssh_private_key_path" {
  description = "Ansible / SSH key written by Terraform (gitignored)"
  value       = module.keys.private_key_filename
}
