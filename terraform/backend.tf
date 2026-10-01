# Partial backend. Bucket comes from -backend-config=backends/{dev,prod}.hcl
# Terraform backends cannot read variables or *.tfvars.
terraform {
  backend "gcs" {
    prefix = "terraform/state"
  }
}
