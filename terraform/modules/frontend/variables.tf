variable "project_id" { type = string }
variable "region" { type = string }
variable "name_prefix" { type = string }
variable "artifact_registry_repo" { type = string }

variable "custom_domain" {
  description = "Hostname to map to this Cloud Run service (e.g. app.example.com). Empty = skip mapping."
  type        = string
  default     = ""
}
