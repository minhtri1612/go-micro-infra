variable "aws_region" {
  type    = string
  default = "ap-southeast-2"
}

variable "project_name" {
  type    = string
  default = "go-micro"
}

variable "environments" {
  type        = set(string)
  description = "dev / staging / prod"
  default     = ["dev", "staging", "prod"]
}

variable "db_user" {
  type    = string
  default = "postgres"
}

variable "db_password" {
  type        = string
  default     = "canh177"
  description = "Database password used by services and Postgres."
}

variable "stripe_secret_key" {
  type        = string
  sensitive   = true
  description = "Stripe secret key (sk_test_... or sk_live_...). Written into each env's app-credentials secret in AWS; External Secrets syncs to the cluster. No default — set in terraform.tfvars (gitignored)."
  validation {
    condition     = can(regex("^sk_(test|live)_", var.stripe_secret_key))
    error_message = "stripe_secret_key must start with sk_test_ or sk_live_."
  }
}

variable "app_credentials_name_suffix_by_env" {
  type        = map(string)
  default     = {}
  description = "Optional suffix by env, e.g. { dev = \"-v2\" }"
}

variable "eso_iam_user_suffix" {
  type        = string
  default     = "multi"
  description = "Suffix for IAM user used by External Secrets Operator"
}
