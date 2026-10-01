# =============================================================================
# Production Environment Configuration (envs/prod.tfvars)
# =============================================================================
# Used with: terraform plan -var-file=envs/prod.tfvars
# CI/CD: Automated on merge to "main" branch.
# =============================================================================

region      = "us-central1"
name_prefix = "myproject-prod"
app_env     = "production"
debug       = false

# ---------- Feature Toggles ----------
enable_frontend      = true
enable_ai_apis       = false
enable_migration_job = true
enable_seed_job      = false

migration_command = ["alembic", "upgrade", "head"]
seed_command      = []

# ---------- Cloud SQL Sizing ----------
db_name                  = "app_db"
db_tier                  = "db-custom-2-7680" # Production tier (2 vCPU, 7.5GB RAM)
db_disk_size_gb          = 20
db_backup_retention_days = 30
db_backup_schedule       = "0 4 * * *"
db_backup_timezone       = "UTC"

# ---------- Cloud Storage ----------
gcs_bucket_name     = "myproject-prod-uploads"
gcs_bucket_location = "us-central1"

# ---------- Networking CIDRs ----------
app_subnet_cidr      = "10.10.1.0/24"
psa_range_cidr       = "10.10.2.0/23"
iap_ssh_source_cidrs = ["35.235.240.0/20"]

# ---------- Developer DB Access (IAP Bastion) ----------
bastion_operator_members = [
  # "user:lead-dev@example.com"
]

# ---------- Domains & Load Balancer ----------
# Enter production domain name (e.g., "app.example.com")
frontend_domain = ""
backend_domain  = "" # Optional separate API domain (e.g., "api.example.com")
cors_origins    = ""

# ---------- Cloud Armor Security (WAF) ----------
# Leave empty for public web traffic protected by OWASP CRS 3.3 rules and rate limiting.
cloud_armor_allow_rules = []

# ---------- Application Environment Variables & Secrets ----------
app_env_vars = {
  LOG_LEVEL = "INFO"
}

app_secrets = {
  JWT_SECRET = "REPLACE_ME"
}
