variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "ami_id" {
  description = "Override AMI; null = latest Ubuntu 24.04 amd64"
  type        = string
  default     = null
}

variable "rke2_version" {
  type    = string
  default = "v1.28.15+rke2r1"
}

variable "rke2_token" {
  type      = string
  sensitive = true
}

variable "master_count" {
  type    = number
  default = 1

  validation {
    condition     = var.master_count == 1
    error_message = "Only single-server RKE2 is wired up; HA server join is not implemented."
  }
}

variable "worker_count" {
  type = number
}

variable "master_instance_type" {
  type = string
}

variable "worker_instance_type" {
  type = string
}

variable "root_volume_size" {
  type    = number
  default = 30
}

variable "use_spot" {
  type    = bool
  default = false
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "node_common_sg_id" {
  type = string
}

variable "master_sg_id" {
  type = string
}

variable "worker_sg_id" {
  type = string
}

variable "iam_instance_profile" {
  type = string
}

variable "api_dns_name" {
  description = "Internal NLB DNS, added to the apiserver tls-san"
  type        = string
}

variable "api_target_group_arn" {
  type = string
}

variable "web_http_target_group_arn" {
  type = string
}

variable "web_https_target_group_arn" {
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
