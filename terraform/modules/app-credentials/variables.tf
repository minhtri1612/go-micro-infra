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

variable "recovery_window_in_days" {
  type        = number
  default     = 7
  description = "Secrets Manager deletion window. 0 = immediate (lab destroy). Prefer 7–30."
}
