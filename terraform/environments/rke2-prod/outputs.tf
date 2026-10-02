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
  description = "Internal NLB for the Kubernetes API (Argo CD / Jenkins over peering)"
  value       = module.lb.api_dns_name
}

output "web_dns_name" {
  description = "Public NLB in front of the Traefik NodePorts"
  value       = module.lb.web_dns_name
}

output "ssh_private_key_path" {
  description = "Ansible / SSH key written by Terraform (gitignored)"
  value       = module.keys.private_key_filename
}

output "eso_access_key_id" {
  value     = module.eso_iam.eso_access_key_id
  sensitive = true
}

output "eso_secret_access_key" {
  value     = module.eso_iam.eso_secret_access_key
  sensitive = true
}

output "app_credentials_secret_name" {
  description = "ESO remoteRef.key (go-micro/prod/app-credentials)"
  value       = module.app_credentials.app_credentials_secret_name
}
