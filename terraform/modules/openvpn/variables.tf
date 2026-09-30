variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "ami_id" {
  type    = string
  default = null
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "subnet_id" {
  description = "Public subnet in the management VPC"
  type        = string
}

variable "security_group_id" {
  type = string
}

variable "iam_instance_profile" {
  type = string
}

variable "root_volume_size" {
  type    = number
  default = 20
}
