# Partial backend: bucket/key filled at init from backend.hcl (gitignored).
# terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {}
}
