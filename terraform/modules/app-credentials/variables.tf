variable "environment" {
  type = string
}

variable "project_name" {
  type = string
}

variable "db_user" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "app_credentials_name_suffix" {
  type    = string
  default = ""
}

variable "stripe_secret_key" {
  type      = string
  sensitive = true
}
