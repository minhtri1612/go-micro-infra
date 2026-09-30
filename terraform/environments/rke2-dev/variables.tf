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
  default = "rke2-dev"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "vpc_cidr" {
  type    = string
  default = "10.1.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.1.1.0/24", "10.1.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.1.101.0/24", "10.1.102.0/24"]
}

variable "api_peer_cidrs" {
  description = "10.0.0.0/16 = Argo CD in the management VPC, 10.50.0.0/16 = Jenkins VPC"
  type        = list(string)
  default     = ["10.0.0.0/16", "10.50.0.0/16"]
}

variable "master_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "worker_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "worker_count" {
  type    = number
  default = 2
}

variable "use_spot" {
  type    = bool
  default = false
}

variable "rke2_version" {
  type    = string
  default = "v1.28.15+rke2r1"
}

variable "admin_ssh_cidr" {
  description = "Operator address /32 allowed to SSH the management OpenVPN host"
  type        = string
  default     = "0.0.0.0/0"
}
