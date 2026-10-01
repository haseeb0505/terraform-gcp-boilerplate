# =============================================================================
# Development / Staging Environment Configuration (envs/dev.tfvars)
# =============================================================================
# Used with: terraform plan -var-file=envs/dev.tfvars
# CI/CD: Automated on pull requests or merge to "dev" branch.
# =============================================================================

region      = "us-central1"
name_prefix = "myproject-dev"
app_env     = "development"
debug       = true

# ---------- Feature Toggles ----------
enable_frontend      = true
enable_ai_apis       = false
enable_migration_job = true
enable_seed_job      = false

# Migration command (e.g., Alembic, Prisma, Django, Knex)
migration_command = ["alembic", "upgrade", "head"]
seed_command      = []

# ---------- Cloud SQL Sizing ----------
db_name                  = "app_db"
db_tier                  = "db-custom-1-3840" # Cost-effective dev tier
db_disk_size_gb          = 10
db_backup_retention_days = 14
db_backup_schedule       = "0 4 * * *"
db_backup_timezone       = "UTC"

# ---------- Cloud Storage ----------
gcs_bucket_name     = "myproject-dev-uploads"
gcs_bucket_location = "us-central1"

# ---------- Networking CIDRs ----------
app_subnet_cidr      = "10.0.1.0/24"
psa_range_cidr       = "10.0.2.0/23"
iap_ssh_source_cidrs = ["35.235.240.0/20"] # Google Cloud IAP IP range

# ---------- Developer DB Access (IAP Bastion) ----------
# Add developers who need IAP SSH tunnel access for local database tools (psql, DBeaver)
# Format: "user:developer@example.com"
bastion_operator_members = [
  # "user:developer@example.com"
]

# ---------- Domains & Load Balancer ----------
# Leave empty for initial setup (provisions HTTP LB IP without custom domain/cert)
# When ready: set domain and point DNS A record to terraform output "web_lb_ip"
frontend_domain = ""
backend_domain  = "" # Optional separate API domain (e.g. "api-dev.example.com")
cors_origins    = "http://localhost:3000,http://localhost:5173"

# ---------- Cloud Armor Security (WAF) ----------
# Empty = Public access with OWASP Top 10 WAF inspection and rate limiting.
# Non-empty = Restrict access strictly to designated office/VPN CIDRs.
cloud_armor_allow_rules = []

# ---------- Application Environment Variables & Secrets ----------
# Non-sensitive configuration stored in Secret Manager
app_env_vars = {
  LOG_LEVEL = "DEBUG"
}

# Sensitive secrets (Terraform writes "REPLACE_ME" placeholder once; update in Secret Manager)
app_secrets = {
  JWT_SECRET = "REPLACE_ME"
}
