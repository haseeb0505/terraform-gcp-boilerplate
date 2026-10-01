variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for shared resource names"
  type        = string
}

variable "enable_ai_apis" {
  description = "Enable Vertex AI and Speech-to-Text APIs"
  type        = bool
  default     = false
}

variable "additional_apis" {
  description = "Additional GCP APIs to enable"
  type        = list(string)
  default     = []
}
