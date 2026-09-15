output "state_bucket" {
  description = "S3 bucket for Terraform remote state. Put this in live/backend.hcl."
  value       = aws_s3_bucket.tfstate.bucket
}

output "lock_table" {
  description = "DynamoDB table for state locking. Put this in live/backend.hcl."
  value       = aws_dynamodb_table.locks.name
}

output "aws_region" {
  value = var.aws_region
}

output "backend_hcl" {
  description = "Copy into terraform/live/backend.hcl then terraform init -backend-config=backend.hcl"
  value       = <<-EOT
    bucket         = "${aws_s3_bucket.tfstate.bucket}"
    key            = "live/terraform.tfstate"
    region         = "${var.aws_region}"
    dynamodb_table = "${aws_dynamodb_table.locks.name}"
    encrypt        = true
  EOT
}
