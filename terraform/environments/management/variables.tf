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
  default = "t3.xlarge"
}

variable "kind_ami_id" {
  type        = string
  default     = "ami-0431580b981f6110a"
  description = "Snapshot of the running Kind host (Argo/Kind on disk). Spot resize launches a new instance from this AMI. Do not use latest Ubuntu or Kind is wiped."
}

variable "jenkins_ami_id" {
  type        = string
  default     = "ami-0da8007d942cd1875"
  description = "Pin the running Jenkins AMI so dropping ignore_changes[ami] does not replace Jenkins."
}

variable "kind_root_volume_size" {
  type    = number
  default = 40
}

variable "jenkins_instance_type" {
  type    = string
  default = "t4g.small"
}

variable "jenkins_root_volume_size" {
  type    = number
  default = 20
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

variable "secret_recovery_window_in_days" {
  type        = number
  default     = 7
  description = "Passed to app-credentials. Use 0 only when you need immediate secret delete on destroy."
}
