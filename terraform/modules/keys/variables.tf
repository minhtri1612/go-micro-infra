variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "key_filename" {
  description = "Where to write the private key (gitignored *.pem)"
  type        = string
}
