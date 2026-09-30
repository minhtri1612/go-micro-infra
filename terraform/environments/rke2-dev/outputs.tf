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
