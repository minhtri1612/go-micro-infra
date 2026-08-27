variable "environment" {
  type = string
}

variable "project_name" {
  type = string
}

variable "db_user" {
  type    = string
  default = "postgres"
}

variable "db_password" {
  type        = string
  description = "Database password injected to app credentials."
  default     = "canh177"
}

variable "app_credentials_name_suffix" {
  type        = string
  default     = ""
  description = "Optional secret name suffix, e.g. -v2"
}

variable "stripe_secret_key" {
  type        = string
  sensitive   = true
  description = "Stripe API secret key injected into app-credentials JSON for this environment."
}
