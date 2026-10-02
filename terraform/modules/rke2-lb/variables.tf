variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "internal_web" {
  description = "true = Argo/Grafana NLB stays private (VPN). false = public Traefik NLB for dest/prod apps."
  type        = bool
  default     = false
}

variable "web_nlb_sg_id" {
  type = string
}

variable "http_node_port" {
  type    = number
  default = 32080
}

variable "https_node_port" {
  type    = number
  default = 32443
}

variable "extra_listeners" {
  description = "NLB listen port => instance NodePort (Grafana 32000, Prometheus 32090)"
  type        = map(number)
  default     = {}
}
