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
  default = "networking"
}

variable "management_vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "dev_vpc_cidr" {
  type    = string
  default = "10.1.0.0/16"
}

variable "prod_vpc_cidr" {
  type    = string
  default = "10.2.0.0/16"
}
