# Variable & Configuration Inventory

This document details every configuration input in this boilerplate, explaining what it controls, where it belongs, and default values.

---

## 📍 Where Each Variable Lives

| Location | Purpose | Examples | How to Update |
| :--- | :--- | :--- | :--- |
| **GitHub Repository Secrets** | GCP project identifiers and OIDC credentials | `GCP_PROJECT_ID`, `GCP_PROJECT_NUMBER`, `GCP_WORKLOAD_IDENTITY_PROVIDER` | Repo Settings → Secrets and variables → Actions |
| **`terraform/envs/{dev,prod}.tfvars`** | Environment-specific stack settings | `region`, `db_tier`, `frontend_domain`, `enable_frontend` | Commit & push to `dev` or `main` |
| **`terraform/backends/{dev,prod}.hcl`** | GCS bucket for remote Terraform state | `bucket = "PROJECT_ID-tfstate"` | Set during bootstrap |
| **GCP Secret Manager** | Sensitive runtime credentials | Database passwords, JWT signing keys, 3rd party API keys | Update via GCP Console or `gcloud` CLI |
| **`terraform/variables.tf`** | Variable types, validations, and defaults | Sane defaults for optional variables | Source code |

---

## 🗂 Terraform Variables Index

### 1. Project & Core Identification

| Variable | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `project_id` | `string` | *(Required)* | Google Cloud Project ID (set via GitHub Actions `GCP_PROJECT_ID` or tfvars). |
| `project_number` | `string` | `""` | Numeric GCP project number (required for WIF audience in CI/CD). |
| `region` | `string` | `"us-central1"` | Target Google Cloud region for all resources. |
| `name_prefix` | `string` | *(Required)* | Unique prefix for resource names (e.g. `myapp-dev`, `myapp-prod`). |
| `app_env` | `string` | `"production"` | Environment label (`development`, `staging`, `production`). |
| `debug` | `bool` | `false` | Application debug mode flag (injected into Secret Manager). |

---

### 2. Feature Toggles & Modularity

| Variable | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `enable_frontend` | `bool` | `true` | When `true`, provisions the frontend Cloud Run service and wires it to the Load Balancer. When `false`, provisions an API-only architecture. |
| `enable_ai_apis` | `bool` | `false` | Enables Google Vertex AI and Speech-to-Text APIs, and grants service agent access to uploads bucket. |
| `additional_apis` | `list(string)` | `[]` | List of additional GCP APIs to enable on the project. |
| `enable_migration_job` | `bool` | `true` | Provisions a Cloud Run Job for running database schema migrations. |
| `migration_command` | `list(string)` | `["alembic", "upgrade", "head"]` | Command array executed by the database migration job. |
| `enable_seed_job` | `bool` | `false` | Provisions a Cloud Run Job for database seeding. |
| `seed_command` | `list(string)` | `[]` | Command array executed by the seed job. |

---

### 3. Networking & Perimeter Security

| Variable | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `app_subnet_cidr` | `string` | `"10.0.1.0/24"` | Application subnet CIDR block for Cloud Run Direct VPC egress. |
| `psa_range_cidr` | `string` | `"10.0.2.0/23"` | Allocated CIDR block for Private Services Access / Cloud SQL private IP. |
| `nat_ip_count` | `number` | `1` | Number of reserved PREMIUM external IP addresses for Cloud NAT outbound traffic. |
| `iap_ssh_source_cidrs` | `list(string)` | `["35.235.240.0/20"]` | Allowed CIDR ranges for SSH to the bastion (defaults strictly to Google Cloud IAP). |
| `cloud_armor_allow_rules` | `list(object)` | `[]` | List of IP allow rules for Cloud Armor. When empty, site is public with WAF & rate limiting. When non-empty, traffic is restricted to listed CIDRs. |

---

### 4. Cloud SQL (PostgreSQL)

| Variable | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `db_name` | `string` | `"app_db"` | Primary application database name. |
| `db_tier` | `string` | `"db-custom-1-3840"` | Cloud SQL machine tier (e.g. `db-custom-1-3840`, `db-custom-2-7680`). |
| `db_disk_size_gb` | `number` | `10` | Storage capacity allocated for Cloud SQL in gigabytes (autoresize enabled). |
| `db_backup_retention_days`| `number` | `30` | Days to retain daily exported SQL dumps in the Cloud Storage backup bucket. |
| `db_backup_schedule` | `string` | `"0 4 * * *"` | Daily cron schedule for running Cloud SQL export workflow. |
| `db_backup_timezone` | `string` | `"UTC"` | Timezone for the backup export cron schedule. |

---

### 5. Developer DB Access (IAP Bastion)

| Variable | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `bastion_operator_members`| `list(string)` | `[]` | IAM members granted IAP tunnel and OS Login permissions to access the database locally via SSH (e.g. `["user:dev@example.com"]`). |
| `bastion_zone` | `string` | `""` | GCP zone for the bastion VM. Defaults to `{region}-a`. |

---

### 6. Storage (Google Cloud Storage)

| Variable | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `gcs_bucket_name` | `string` | `""` | Name of uploads GCS bucket. Defaults to `{name_prefix}-uploads`. |
| `gcs_bucket_location` | `string` | `"us-central1"` | Regional location for the uploads bucket. |

---

### 7. Custom Domains & Routing

| Variable | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `frontend_domain` | `string` | `""` | Hostname for the frontend or unified domain (e.g. `app.example.com`). When empty, stack operates in HTTP-only mode on the Load Balancer IP. |
| `backend_domain` | `string` | `""` | Optional separate hostname for API (e.g. `api.example.com`). If empty, API routes via `/api/*` on `frontend_domain`. |
| `cors_origins` | `string` | `""` | Comma-separated list of allowed browser origins for API and direct GCS uploads. |

---

### 8. Custom Application Configuration & Secrets

| Variable | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `app_env_vars` | `map(string)` | `{}` | Map of non-sensitive environment variables stored in Secret Manager. |
| `app_secrets` | `map(string)` | `{"JWT_SECRET": "REPLACE_ME"}` | Map of sensitive secrets initialized in Secret Manager with placeholders for console update. |

---

## 🔐 Secret Manager Keys

Terraform creates secrets with the naming convention `${name_prefix}-${secret_name}`:
- `${name_prefix}-database-url`: Initialized with placeholder `postgresql://USER:PASSWORD@<private-ip>:5432/<db>?ssl=require`. Replace `USER` and `PASSWORD` in the GCP Console.
- `${name_prefix}-jwt-secret`: Initialized with `REPLACE_ME`.
- Custom secrets defined in `var.app_secrets`.
