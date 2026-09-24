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

variable "ami_arch" {
  type        = string
  default     = "amd64"
  description = "Ubuntu AMI arch: amd64 (t3) or arm64 (t4g)."

  validation {
    condition     = contains(["amd64", "arm64"], var.ami_arch)
    error_message = "ami_arch must be amd64 or arm64."
  }
}

variable "use_spot" {
  type        = bool
  default     = false
  description = "Launch as persistent Spot; interruption stops the instance (disk kept)."
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
