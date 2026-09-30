variable "project_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "kind_instance_id" {
  type        = string
  description = "Kind EC2 id. Jenkins SSM send-command is limited to this instance."
}

variable "jenkins_runtime_secret_arn" {
  type = string
}
