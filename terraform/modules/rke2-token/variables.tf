variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "recovery_window_in_days" {
  description = "0 = delete immediately so the secret name can be reused after destroy"
  type        = number
  default     = 0
}
