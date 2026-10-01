variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for Cloud SQL, Cloud Run, secrets, and SA names"
  type        = string
}

variable "artifact_registry_repo" {
  description = "Artifact registry repository URL"
  type        = string
}

variable "vpc_id" {
  description = "VPC network ID for Cloud SQL private IP and Cloud Run Direct VPC egress"
  type        = string
}

variable "subnet_id" {
  description = "Application subnet ID for Cloud Run Direct VPC egress"
  type        = string
}

variable "private_vpc_connection_id" {
  description = "Private Services Access connection ID (Cloud SQL depends on this)"
  type        = string
}

variable "nat_id" {
  description = "Cloud NAT id — Direct VPC ALL_TRAFFIC must wait for this"
  type        = string
}

# Cloud SQL (private IP via VPC + PSA)
variable "db_name" {
  description = "Cloud SQL database name"
  type        = string
  default     = "app_db"
}

variable "db_tier" {
  description = "Cloud SQL machine tier"
  type        = string
  default     = "db-custom-1-3840"
}

variable "db_disk_size_gb" {
  description = "Cloud SQL disk size in GB"
  type        = number
  default     = 10
}

variable "db_backup_retention_days" {
  description = "Days to keep Cloud SQL export objects in the db-backups bucket."
  type        = number
  default     = 30
}

variable "db_backup_schedule" {
  description = "Cron schedule for Cloud SQL daily backup export"
  type        = string
  default     = "0 4 * * *"
}

variable "db_backup_timezone" {
  description = "Timezone for the backup export cron schedule"
  type        = string
  default     = "UTC"
}

# GCS
variable "gcs_bucket_name" {
  description = "GCS bucket name for application uploads"
  type        = string
}

variable "gcs_bucket_location" {
  description = "GCS bucket location"
  type        = string
}

# Environment Configuration
variable "app_env" {
  description = "APP_ENV value stored in Secret Manager"
  type        = string
  default     = "production"
}

variable "debug" {
  description = "DEBUG flag stored in Secret Manager"
  type        = bool
  default     = false
}

variable "cors_origins" {
  description = "Comma-separated CORS origins. Empty = use frontend_url only."
  type        = string
  default     = ""
}

variable "frontend_url" {
  description = "Frontend service URL, used for CORS_ORIGINS fallback"
  type        = string
  default     = ""
}

variable "custom_domain" {
  description = "Custom domain hostname mapped to this service (empty = skip)"
  type        = string
  default     = ""
}

# Generic App Environment Variables and Secrets (Secret Manager backed)
variable "app_env_vars" {
  description = "Map of non-sensitive application environment variables stored in Secret Manager"
  type        = map(string)
  default     = {}
}

variable "app_secrets" {
  description = "Map of sensitive secret names to placeholder values created in Secret Manager"
  type        = map(string)
  default = {
    JWT_SECRET = "REPLACE_ME"
  }
}

# Jobs Configuration
variable "enable_migration_job" {
  description = "Enable Cloud Run migration job"
  type        = bool
  default     = true
}

variable "migration_command" {
  description = "Command array for the migration Cloud Run Job"
  type        = list(string)
  default     = ["alembic", "upgrade", "head"]
}

variable "enable_seed_job" {
  description = "Enable Cloud Run seed job"
  type        = bool
  default     = false
}

variable "seed_command" {
  description = "Command array for the database seed Cloud Run Job"
  type        = list(string)
  default     = []
}

variable "enable_ai_integration" {
  description = "Enable Vertex AI service identity and GCS bucket access for AI services"
  type        = bool
  default     = false
}
