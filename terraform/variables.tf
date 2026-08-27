variable "aws_region" {
  description = "AWS region for the Kind lab."
  type        = string
  default     = "ap-southeast-2"
}

variable "project_name" {
  description = "Project name used in tags and resource names."
  type        = string
  default     = "go-micro"
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "m7i.xlarge"
}

variable "ssh_key_name" {
  description = "Name of an existing EC2 key pair in the target AWS region (created in console)."
  type        = string
  default     = "minhtri"
}

variable "ssh_ingress_cidr" {
  description = "CIDR allowed to access the instance. Leave null to auto-detect your public IP at apply time."
  type        = string
  default     = null
}

variable "allowed_tcp_ports" {
  description = "TCP ports allowed from ssh_ingress_cidr."
  type        = list(number)
  default     = [22, 18080, 18081]
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.50.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet."
  type        = string
  default     = "10.50.1.0/24"
}

variable "root_volume_size" {
  description = "Root volume size in GiB."
  type        = number
  default     = 100
}
