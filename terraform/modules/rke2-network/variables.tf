variable "project_name" {
  type = string
}

variable "environment" {
  description = "management | dev | prod"
  type        = string
}

variable "vpc_cidr" {
  type = string
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_subnet_cidrs" {
  type = list(string)
}

variable "api_peer_cidrs" {
  description = "Peered VPC CIDRs allowed to reach apiserver :6443 (Argo CD, Jenkins)"
  type        = list(string)
  default     = []
}

variable "vpn_client_cidr" {
  description = "OpenVPN client pool"
  type        = string
  default     = "10.8.0.0/24"
}

variable "admin_ssh_cidr" {
  description = "Operator address allowed to SSH the OpenVPN host before the VPN is up"
  type        = string
  default     = "0.0.0.0/0"
}

variable "http_node_port" {
  type    = number
  default = 32080
}

variable "https_node_port" {
  type    = number
  default = 32443
}

variable "extra_node_ports" {
  description = "Additional NodePorts on masters/workers from the web NLB (Grafana, Prometheus, Argo)"
  type        = list(number)
  default     = []
}

variable "extra_nlb_ports" {
  description = "Additional listen ports on the public NLB security group"
  type        = list(number)
  default     = []
}
