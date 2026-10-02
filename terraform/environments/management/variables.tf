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
  default = "management"
}

variable "admin_ingress_cidr" {
  type        = string
  default     = null
  description = "Unused after Kind lab teardown. Kept so leftover tfvars still init."
}

variable "vpc_cidr" {
  type    = string
  default = "10.50.0.0/16"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.50.1.0/24"
}

variable "environments" {
  type    = set(string)
  default = ["dev", "prod"]
}

variable "db_user" {
  type    = string
  default = "postgres"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "stripe_secret_key" {
  type      = string
  sensitive = true

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

variable "secret_recovery_window_in_days" {
  type    = number
  default = 7
}
