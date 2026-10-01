#!/usr/bin/env bash
# =============================================================================
# IAP SSH Tunnel for Local Database Access (psql / DBeaver / DataGrip)
# =============================================================================
# Forwards: 127.0.0.1:LOCAL_PORT -> Cloud SQL private IP:5432 via IAP Bastion.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$ROOT/terraform"
LOCAL_PORT="${LOCAL_PORT:-5433}"

if ! command -v gcloud >/dev/null 2>&1; then
  echo "Error: gcloud CLI not found. Install Google Cloud SDK first." >&2
  exit 1
fi

if ! command -v terraform >/dev/null 2>&1; then
  echo "Error: terraform CLI not found." >&2
  exit 1
fi

PROJECT="$(cd "$TF_DIR" && terraform output -raw project_id 2>/dev/null || true)"
BASTION="$(cd "$TF_DIR" && terraform output -raw bastion_instance_name 2>/dev/null || true)"
ZONE="$(cd "$TF_DIR" && terraform output -raw bastion_zone 2>/dev/null || true)"
SQL_IP="$(cd "$TF_DIR" && terraform output -raw cloud_sql_private_ip 2>/dev/null || true)"

if [ -z "$PROJECT" ] || [ -z "$BASTION" ] || [ -z "$ZONE" ] || [ -z "$SQL_IP" ]; then
  echo "Error: Could not retrieve outputs from Terraform." >&2
  echo "Make sure you have run 'terraform init' and 'terraform apply' first." >&2
  exit 1
fi

echo "Opening IAP tunnel → 127.0.0.1:${LOCAL_PORT} => ${SQL_IP}:5432 via ${BASTION} (${ZONE})"
echo "Note: Your GCP user must be listed in 'bastion_operator_members' in your tfvars."
echo "Connect with: postgresql://USER:PASSWORD@127.0.0.1:${LOCAL_PORT}/app_db?sslmode=require"
echo

exec gcloud compute ssh "$BASTION" \
  --project="$PROJECT" \
  --zone="$ZONE" \
  --tunnel-through-iap \
  -- -N -L "${LOCAL_PORT}:${SQL_IP}:5432"
