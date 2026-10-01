# ---------------------------------------------------------------------------
# Core GCP APIs
# ---------------------------------------------------------------------------
locals {
  core_apis = [
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "iam.googleapis.com",
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "workflows.googleapis.com",
    "cloudscheduler.googleapis.com",
    "artifactregistry.googleapis.com",
    "containeranalysis.googleapis.com",
    "containerscanning.googleapis.com",
    "ondemandscanning.googleapis.com",
    "storage.googleapis.com",
    "secretmanager.googleapis.com",
    "iamcredentials.googleapis.com",
    "compute.googleapis.com",
    "servicenetworking.googleapis.com",
    "iap.googleapis.com",
    "sts.googleapis.com",
  ]

  ai_apis = var.enable_ai_apis ? [
    "speech.googleapis.com",
    "aiplatform.googleapis.com",
  ] : []

  apis = distinct(concat(local.core_apis, local.ai_apis, var.additional_apis))
}

resource "google_project_service" "apis" {
  for_each           = toset(local.apis)
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# Artifact Registry — automatic vulnerability scanning on push
# ---------------------------------------------------------------------------
resource "google_artifact_registry_repository" "docker" {
  location      = var.region
  project       = var.project_id
  repository_id = var.name_prefix
  format        = "DOCKER"
  description   = "Docker images for ${var.name_prefix}"

  depends_on = [google_project_service.apis]
}
