variable "aws_region" {
  type    = string
  default = "ap-southeast-2"
}

variable "project_name" {
  type    = string
  default = "go-micro"
}

variable "stack" {
  type    = string
  default = "rke2-management"
}

variable "environment" {
  type    = string
  default = "management"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "master_instance_type" {
  type    = string
  default = "t3.large"
}

variable "worker_instance_type" {
  type    = string
  default = "t3.large"
}

variable "worker_count" {
  type    = number
  default = 1
}

variable "use_spot" {
  type    = bool
  default = false
}

variable "openvpn_instance_type" {
  type    = string
  default = "t3.small"
}

variable "rke2_version" {
  type    = string
  default = "v1.28.15+rke2r1"
}

variable "jenkins_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "jenkins_runtime_secret_name" {
  description = "Existing Secrets Manager secret used by load-runtime-env.sh"
  type        = string
  default     = "go-micro/jenkins/runtime"
}

variable "admin_ssh_cidr" {
  description = "Operator address /32 allowed to SSH the management OpenVPN host"
  type        = string
  default     = "0.0.0.0/0"
}
