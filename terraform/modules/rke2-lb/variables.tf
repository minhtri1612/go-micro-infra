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
