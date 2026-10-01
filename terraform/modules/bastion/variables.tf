variable "project_id" {
  type = string
}

variable "zone" {
  description = "GCE zone for the bastion VM"
  type        = string
}

variable "name_prefix" {
  type = string
}

variable "network_name" {
  description = "VPC network name (for firewall rules)"
  type        = string
}

variable "subnet_id" {
  description = "Subnet self-link / ID for the bastion NIC"
  type        = string
}

variable "operator_members" {
  description = "IAM members allowed to IAP-SSH to the bastion (user:email@...)"
  type        = list(string)
  default     = []
}

variable "iap_ssh_source_cidrs" {
  description = "Source CIDRs allowed to SSH to the bastion (Google IAP range)"
  type        = list(string)
  default     = ["35.235.240.0/20"]
}
