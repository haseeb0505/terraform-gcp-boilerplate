# Operational Runbook & CLI Commands

This guide contains practical CLI recipes for operating, inspecting, and troubleshooting this GCP infrastructure stack.

---

## 🛠 Prerequisites

Ensure you have the following CLI tools installed:
- [Google Cloud SDK (`gcloud`)](https://cloud.google.com/sdk/docs/install)
- [Terraform CLI (>= 1.5)](https://developer.hashicorp.com/terraform/downloads)

Set your active GCP project:
```bash
gcloud config set project YOUR_PROJECT_ID
```

---

## 🚀 Bootstrap & CI/CD Setup

### 1. One-Command Bootstrap (GCP + GitHub WIF)
Run the automated bootstrap script:
```bash
./scripts/bootstrap.sh YOUR_PROJECT_ID YOUR_GITHUB_OWNER/YOUR_GITHUB_REPO us-central1
```

This creates:
- Remote Terraform state GCS bucket (`gs://YOUR_PROJECT_ID-tfstate`).
- Workload Identity Pool (`github-actions-pool`) and GitHub OIDC Provider.
- Deployment Service Account (`github-actions-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com`).
- Required IAM roles for keyless automated deployments.

---

## 🔍 Local Terraform Operations

### 1. Initialize Backend
```bash
cd terraform

# For Development / Staging:
terraform init -reconfigure -backend-config=backends/dev.hcl

# For Production:
terraform init -reconfigure -backend-config=backends/prod.hcl
```

### 2. Plan Infrastructure Changes
```bash
# Development:
terraform plan -var-file=envs/dev.tfvars

# Production:
terraform plan -var-file=envs/prod.tfvars
```

### 3. Read Terraform Outputs
```bash
cd terraform
terraform output
```

Key outputs to note:
```bash
terraform output web_lb_ip         # Static IP for Load Balancer DNS A record
terraform output nat_ips           # Static egress IPs for 3rd-party API allowlisting
terraform output cloud_sql_private_ip
terraform output artifact_registry_repo
```

---

## 💻 Local Database Access (IAP Bastion Tunnel)

Cloud SQL is configured with **Private IP only** (no public IP). Developers connect securely from their laptops via Google Cloud Identity-Aware Proxy (IAP).

### 1. Authorize Developer Access
In `terraform/envs/dev.tfvars`, add the developer's Google account:
```hcl
bastion_operator_members = [
  "user:developer@example.com"
]
```
Apply the change or push to your `dev` branch.

### 2. Start the Tunnel
```bash
./scripts/db-iap-tunnel.sh
```
*Leave this command running in your terminal.* It opens a local listener at `127.0.0.1:5433` forwarded directly to the private Cloud SQL instance.

### 3. Connect via psql or GUI (DBeaver / DataGrip)
```bash
# Terminal connection:
psql "postgresql://USER:PASSWORD@127.0.0.1:5433/app_db?sslmode=require"
```
- **Host**: `127.0.0.1`
- **Port**: `5433`
- **Database**: `app_db`
- **User / Password**: Read from Secret Manager (`{name_prefix}-database-url`)
- **SSL**: Require / Enable

---

## 🔐 Managing Secrets in Google Secret Manager

Terraform provisions secrets with `REPLACE_ME` placeholders and ignores future changes so Terraform does not overwrite live production secrets.

### 1. Update Secret via Console or CLI
```bash
# Update JWT Secret:
echo -n "super-secret-production-key" | gcloud secrets versions add myproject-prod-jwt-secret --data-file=-

# Update Database Connection URL:
echo -n "postgresql://app_user:StrongPassword123!@10.0.2.3:5432/app_db?ssl=require" | gcloud secrets versions add myproject-prod-database-url --data-file=-
```

Cloud Run automatically mounts the `latest` version on each new revision.

---

## 🗄 Cloud SQL Manual Backups & Dumps

Terraform provisions an automated Cloud Workflows job that performs daily compressed exports to Cloud Storage (`gs://{name_prefix}-db-backups/`).

### 1. Trigger Manual Backup Export Immediately
```bash
gcloud workflows execute myproject-prod-sql-export --location=us-central1
```

### 2. List Available Backup Files
```bash
BUCKET=$(cd terraform && terraform output -raw db_backup_bucket)
gcloud storage ls --recursive "gs://${BUCKET}/"
```

### 3. Restore Database from a Dump
```bash
gcloud sql import sql myproject-prod-postgres gs://YOUR_BACKUP_BUCKET/dump_file.sql.gz --database=app_db
```

---

## 🌐 Custom Domains & SSL Verification

1. Get the Load Balancer IP:
   ```bash
   LB_IP=$(cd terraform && terraform output -raw web_lb_ip)
   echo "Point your DNS A record to: $LB_IP"
   ```
2. Check Google Managed SSL Certificate Status:
   ```bash
   gcloud compute ssl-certificates list
   ```
   *Note: Provisioning a Google-managed SSL certificate typically takes 10–30 minutes after DNS propagation.*

3. Verify HTTPS Connectivity:
   ```bash
   curl -I "https://app.yourdomain.com/api/v1"
   ```

---

## 🛡 Cloud Armor WAF Testing

Check Cloud Armor security policy and active rules:
```bash
PREFIX="myproject-dev"
gcloud compute security-policies describe "${PREFIX}-armor"
```

Inspect Cloud Armor logs for blocked requests:
```bash
gcloud logging read 'resource.type="http_load_balancer" AND jsonPayload.enforcedSecurityPolicy.name="myproject-dev-armor"' --limit=20
```
