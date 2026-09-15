variable "name" {
  type        = string
  description = "Name tag suffix, e.g. kind-host or jenkins-host."
}

variable "project_name" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "iam_instance_profile" {
  type = string
}

variable "ingress_cidr" {
  type = string
}

variable "allowed_tcp_ports" {
  type = list(number)
}

variable "root_volume_size" {
  type = number
}

variable "user_data" {
  type = string
}

variable "allocate_eip" {
  type    = bool
  default = true
}
