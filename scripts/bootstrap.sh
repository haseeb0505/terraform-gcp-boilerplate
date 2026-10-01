#!/usr/bin/env bash
# =============================================================================
# Google Cloud Platform & GitHub Actions Bootstrap Script
# =============================================================================
# This script sets up everything required to use this boilerplate:
#   1. Enables Google Cloud APIs required for Terraform and Workload Identity
#   2. Creates a Google Cloud Storage bucket for Terraform remote state
#   3. Configures Workload Identity Federation (WIF) for GitHub Actions
#   4. Creates the deployment Service Account with appropriate IAM bindings
#   5. Outputs the exact GitHub Secrets & Variables needed in your repository
# =============================================================================

set -euo pipefail

# ANSI Color Codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Check Prerequisites
# -----------------------------------------------------------------------------
if ! command -v gcloud >/dev/null 2>&1; then
  error "gcloud CLI is not installed. Please install the Google Cloud SDK first."
fi

# -----------------------------------------------------------------------------
# Gather Configuration Inputs
# -----------------------------------------------------------------------------
echo -e "${GREEN}=================================================================${NC}"
echo -e "${GREEN}    GCP & GitHub Actions Bootstrap Setup for Terraform          ${NC}"
echo -e "${GREEN}=================================================================${NC}"
echo

PROJECT_ID="${1:-}"
if [ -z "$PROJECT_ID" ]; then
  CURRENT_PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
  read -r -p "Enter your Google Cloud Project ID [${CURRENT_PROJECT}]: " INPUT_PROJECT
  PROJECT_ID="${INPUT_PROJECT:-$CURRENT_PROJECT}"
fi
[ -n "$PROJECT_ID" ] || error "Project ID cannot be empty."

GITHUB_REPO="${2:-}"
if [ -z "$GITHUB_REPO" ]; then
  read -r -p "Enter your GitHub repository (owner/repo, e.g. myorg/infra): " GITHUB_REPO
fi
[ -n "$GITHUB_REPO" ] || error "GitHub repository cannot be empty."

REGION="${3:-us-central1}"

STATE_BUCKET="${PROJECT_ID}-tfstate"
POOL_ID="github-actions-pool"
PROVIDER_ID="github-provider"
SA_NAME="github-actions-deployer"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

info "Setting active project to: $PROJECT_ID"
gcloud config set project "$PROJECT_ID" --quiet

info "Retrieving GCP project number..."
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
[ -n "$PROJECT_NUMBER" ] || error "Failed to retrieve project number for $PROJECT_ID."
success "Project Number: $PROJECT_NUMBER"

# -----------------------------------------------------------------------------
# Step 1: Enable Core GCP APIs
# -----------------------------------------------------------------------------
info "Step 1: Enabling required bootstrap GCP APIs..."
gcloud services enable \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  storage.googleapis.com \
  serviceusage.googleapis.com \
  --project="$PROJECT_ID" --quiet
success "Bootstrap APIs enabled."

# -----------------------------------------------------------------------------
# Step 2: Create Terraform Remote State Bucket
# -----------------------------------------------------------------------------
info "Step 2: Checking Terraform remote state bucket (gs://${STATE_BUCKET})..."
if ! gcloud storage buckets describe "gs://${STATE_BUCKET}" >/dev/null 2>&1; then
  info "Creating GCS bucket: gs://${STATE_BUCKET}..."
  gcloud storage buckets create "gs://${STATE_BUCKET}" \
    --project="$PROJECT_ID" \
    --location="$REGION" \
    --uniform-bucket-level-access --quiet
  gcloud storage buckets update "gs://${STATE_BUCKET}" --versioning --quiet
  success "Remote state bucket created and versioning enabled."
else
  success "Remote state bucket gs://${STATE_BUCKET} already exists."
fi

# -----------------------------------------------------------------------------
# Step 3: Workload Identity Federation (WIF) Pool & Provider
# -----------------------------------------------------------------------------
info "Step 3: Configuring Workload Identity Federation..."

if ! gcloud iam workload-identity-pools describe "$POOL_ID" --location="global" --project="$PROJECT_ID" >/dev/null 2>&1; then
  info "Creating Workload Identity Pool: $POOL_ID..."
  gcloud iam workload-identity-pools create "$POOL_ID" \
    --project="$PROJECT_ID" \
    --location="global" \
    --display-name="GitHub Actions Pool" --quiet
  success "Workload Identity Pool created."
else
  info "Workload Identity Pool $POOL_ID already exists."
fi

if ! gcloud iam workload-identity-pools providers describe "$PROVIDER_ID" --workload-identity-pool="$POOL_ID" --location="global" --project="$PROJECT_ID" >/dev/null 2>&1; then
  info "Creating Workload Identity Provider: $PROVIDER_ID..."
  gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_ID" \
    --project="$PROJECT_ID" \
    --location="global" \
    --workload-identity-pool="$POOL_ID" \
    --display-name="GitHub Provider" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" --quiet
  success "Workload Identity Provider created."
else
  info "Workload Identity Provider $PROVIDER_ID already exists."
fi

# -----------------------------------------------------------------------------
# Step 4: Create Deployment Service Account & Bind IAM
# -----------------------------------------------------------------------------
info "Step 4: Setting up deployment service account: $SA_EMAIL..."

if ! gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$SA_NAME" \
    --project="$PROJECT_ID" \
    --display-name="GitHub Actions Deployer" --quiet
  success "Service account created."
else
  info "Service account $SA_NAME already exists."
fi

info "Granting Workload Identity User role to repository: $GITHUB_REPO..."
gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --project="$PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${GITHUB_REPO}" \
  --quiet

info "Granting necessary project IAM roles to $SA_NAME..."
ROLES=(
  "roles/editor"
  "roles/resourcemanager.projectIamAdmin"
  "roles/storage.admin"
  "roles/secretmanager.admin"
  "roles/iam.serviceAccountAdmin"
  "roles/compute.networkAdmin"
  "roles/compute.securityAdmin"
)

for role in "${ROLES[@]}"; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="$role" \
    --quiet >/dev/null
done
success "IAM roles bound successfully."

# -----------------------------------------------------------------------------
# Step 5: Update Local Backend Configurations (if present)
# -----------------------------------------------------------------------------
TF_DIR="$(cd "$(dirname "$0")/../terraform" && pwd)"
if [ -f "$TF_DIR/backends/dev.hcl" ]; then
  sed -i.bak "s/bucket = .*/bucket = \"${STATE_BUCKET}\"/" "$TF_DIR/backends/dev.hcl" 2>/dev/null || true
  rm -f "$TF_DIR/backends/dev.hcl.bak"
  info "Updated terraform/backends/dev.hcl with bucket = \"${STATE_BUCKET}\""
fi

# -----------------------------------------------------------------------------
# Summary & Next Steps
# -----------------------------------------------------------------------------
WIF_PROVIDER_PATH="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"

echo
echo -e "${GREEN}=================================================================${NC}"
echo -e "${GREEN}                    BOOTSTRAP COMPLETE!                          ${NC}"
echo -e "${GREEN}=================================================================${NC}"
echo
echo "Add the following repository secrets to your GitHub repository:"
echo -e "  URL: ${BLUE}https://github.com/${GITHUB_REPO}/settings/secrets/actions${NC}"
echo
echo -e "  ${YELLOW}GCP_PROJECT_ID${NC}                   : ${PROJECT_ID}"
echo -e "  ${YELLOW}GCP_PROJECT_NUMBER${NC}               : ${PROJECT_NUMBER}"
echo -e "  ${YELLOW}GCP_SERVICE_ACCOUNT${NC}              : ${SA_EMAIL}"
echo -e "  ${YELLOW}GCP_WORKLOAD_IDENTITY_PROVIDER${NC}   : ${WIF_PROVIDER_PATH}"
echo -e "  ${YELLOW}GCP_REGION${NC}                       : ${REGION}"
echo
echo "Next steps:"
echo "  1. Review and adjust parameters in terraform/envs/dev.tfvars"
echo "  2. Push your changes or create a Pull Request to test the CI/CD pipeline"
echo "================================================================="
