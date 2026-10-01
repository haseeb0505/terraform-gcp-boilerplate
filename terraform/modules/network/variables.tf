variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "name_prefix" {
  description = "Prefix for VPC, subnet, and PSA range names"
  type        = string
}

variable "app_subnet_cidr" {
  description = "EI application subnet CIDR for Cloud Run Direct VPC egress"
  type        = string
}

variable "psa_range_cidr" {
  description = "Allocated range for Private Services Access (Cloud SQL private IP)"
  type        = string
}

variable "nat_ip_count" {
  description = "Reserved PREMIUM regional IPs for Cloud NAT. Raise if NAT logs show allocation failures."
  type        = number
  default     = 1

  validation {
    condition     = var.nat_ip_count >= 1
    error_message = "nat_ip_count must be at least 1."
  }
}
