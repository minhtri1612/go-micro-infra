output "state_bucket" {
  description = "S3 bucket for Terraform remote state. Put this in environments/management/backend.hcl."
  value       = aws_s3_bucket.tfstate.bucket
}

output "aws_region" {
  value = var.aws_region
}

output "backend_hcl" {
  description = "Copy into terraform/environments/management/backend.hcl then terraform init -backend-config=backend.hcl"
  value       = <<-EOT
    bucket       = "${aws_s3_bucket.tfstate.bucket}"
    key          = "management/terraform.tfstate"
    region       = "${var.aws_region}"
    encrypt      = true
    use_lockfile = true
  EOT
}
