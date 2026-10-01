variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for all resources"
  type        = string
  default     = "us-central1"
}

variable "name_prefix" {
  description = "Prefix for resource names (Cloud Run, SQL, secrets, etc.)"
  type        = string
}

# ---------- Feature Toggles ----------

variable "enable_frontend" {
  description = "Whether to provision the frontend Cloud Run service"
  type        = bool
  default     = true
}

variable "enable_ai_apis" {
  description = "Whether to enable Vertex AI and Speech-to-Text APIs"
  type        = bool
  default     = false
}

variable "additional_apis" {
  description = "Additional GCP APIs to enable"
  type        = list(string)
  default     = []
}

variable "enable_migration_job" {
  description = "Whether to provision the database migration Cloud Run Job"
  type        = bool
  default     = true
}

variable "migration_command" {
  description = "Command array for the migration Cloud Run Job"
  type        = list(string)
  default     = ["alembic", "upgrade", "head"]
}

variable "enable_seed_job" {
  description = "Whether to provision the database seed Cloud Run Job"
  type        = bool
  default     = false
}

variable "seed_command" {
  description = "Command array for the seed Cloud Run Job"
  type        = list(string)
  default     = []
}

# ---------- Network CIDRs ----------

variable "app_subnet_cidr" {
  description = "Application subnet CIDR for Cloud Run Direct VPC egress"
  type        = string
  default     = "10.0.1.0/24"
}

variable "psa_range_cidr" {
  description = "Allocated range for Private Services Access / Cloud SQL private IP"
  type        = string
  default     = "10.0.2.0/23"
}

variable "nat_ip_count" {
  description = "Reserved PREMIUM regional IPs for Cloud NAT"
  type        = number
  default     = 1

  validation {
    condition     = var.nat_ip_count >= 1
    error_message = "nat_ip_count must be at least 1."
  }
}

variable "iap_ssh_source_cidrs" {
  description = "Source CIDRs allowed to SSH to the bastion (Default: Google IAP)"
  type        = list(string)
  default     = ["35.235.240.0/20"]
}

# ---------- Bastion VM ----------

variable "bastion_operator_members" {
  description = "IAM members allowed to IAP-SSH to the bastion for private DB tunnels (user:email, group:email, or serviceAccount:email)"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for m in var.bastion_operator_members :
      can(regex("^(user|group|serviceAccount|domain):.+$", m))
    ])
    error_message = "Each bastion_operator_members entry must look like \"user:you@example.com\" (include user: / group: / serviceAccount: prefix)."
  }
}

variable "bastion_zone" {
  description = "Zone for the IAP bastion VM. Empty = region-a"
  type        = string
  default     = ""
}

# ---------- Cloud SQL Database ----------

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

# ---------- Storage (GCS) ----------

variable "gcs_bucket_name" {
  description = "GCS bucket for uploads. Empty = \"{name_prefix}-uploads\""
  type        = string
  default     = ""
}

variable "gcs_bucket_location" {
  description = "GCS bucket location (e.g. us-central1)"
  type        = string
  default     = "us-central1"
}

# ---------- Application Environment & Secrets ----------

variable "app_env" {
  description = "Application environment name (development, staging, production)"
  type        = string
  default     = "production"
}

variable "debug" {
  description = "DEBUG flag stored in Secret Manager"
  type        = bool
  default     = false
}

variable "cors_origins" {
  description = "Comma-separated allowed CORS origins for the API"
  type        = string
  default     = ""
}

variable "app_env_vars" {
  description = "Key-value map of arbitrary environment variables to store in Secret Manager"
  type        = map(string)
  default     = {}
}

variable "app_secrets" {
  description = "Key-value map of sensitive secret names to placeholder values created in Secret Manager"
  type        = map(string)
  default = {
    JWT_SECRET = "REPLACE_ME"
  }
}

# ---------- Custom Domains & Load Balancer ----------

variable "frontend_domain" {
  description = "Public hostname for frontend or unified domain (A record -> web_lb_ip). Empty = HTTP IP only."
  type        = string
  default     = ""

  validation {
    condition     = var.frontend_domain == "" || can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", var.frontend_domain))
    error_message = "frontend_domain must be a valid DNS hostname (lowercase letters, digits, '-' and '.')."
  }
}

variable "backend_domain" {
  description = "Optional separate public hostname for API (e.g. api.example.com). Empty = route API via /api/* on frontend_domain."
  type        = string
  default     = ""

  validation {
    condition     = var.backend_domain == "" || can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", var.backend_domain))
    error_message = "backend_domain must be a valid DNS hostname (lowercase letters, digits, '-' and '.')."
  }
}

variable "cloud_armor_allow_rules" {
  description = "Cloud Armor source allow rules (description + up to 10 CIDRs each). Empty = public with WAF & rate limit."
  type = list(object({
    description = string
    cidrs       = list(string)
  }))
  default = []

  validation {
    condition = alltrue([
      for rule in var.cloud_armor_allow_rules : length(rule.cidrs) >= 1 && length(rule.cidrs) <= 10
    ])
    error_message = "Each Cloud Armor allow rule must list 1 to 10 CIDRs."
  }
}

# ---------- CI/CD & Workload Identity Federation ----------

variable "ci_service_account_id" {
  description = "CI service account ID (pipeline impersonates this via WIF)"
  type        = string
  default     = "github-actions-deployer"
}

variable "project_number" {
  description = "Numeric GCP project number for WIF audience."
  type        = string
  default     = ""
}

variable "wif_pool_id" {
  description = "Workload Identity Federation pool ID"
  type        = string
  default     = "github-actions-pool"
}

variable "wif_provider_id" {
  description = "Workload Identity Federation provider ID"
  type        = string
  default     = "github-provider"
}
