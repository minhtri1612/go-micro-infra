variable "aws_region" {
  type    = string
  default = "ap-southeast-2"
}

variable "project_name" {
  type    = string
  default = "go-micro"
}

variable "admin_ingress_cidr" {
  type        = string
  default     = null
  description = "CIDR allowed to reach Jenkins :8080 and Argo port-forward :18080. Null = your public IP at apply time. Shell access is SSM, not SSH."
}

variable "vpc_cidr" {
  type    = string
  default = "10.50.0.0/16"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.50.1.0/24"
}

variable "kind_instance_type" {
  type    = string
  default = "m7i.xlarge"
}

variable "kind_root_volume_size" {
  type    = number
  default = 100
}

variable "jenkins_instance_type" {
  type    = string
  default = "t3.large"
}

variable "jenkins_root_volume_size" {
  type    = number
  default = 50
}

variable "environments" {
  type        = set(string)
  default     = ["dev", "prod"]
  description = "Secrets Manager envs. Kind lab uses dev+prod; add staging in tfvars if needed."
}

variable "db_user" {
  type    = string
  default = "postgres"
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "No default. Set in terraform.tfvars."
}

variable "stripe_secret_key" {
  type        = string
  sensitive   = true
  description = "Stripe sk_test_ or sk_live_. Set in terraform.tfvars."

  validation {
    condition     = can(regex("^sk_(test|live)_", var.stripe_secret_key))
    error_message = "stripe_secret_key must start with sk_test_ or sk_live_."
  }
}

variable "app_credentials_name_suffix_by_env" {
  type    = map(string)
  default = {}
}

variable "eso_iam_user_suffix" {
  type    = string
  default = "multi"
}
