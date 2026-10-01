# ---------------------------------------------------------------------------
# Frontend service account (minimal — no DB, no GCS)
# ---------------------------------------------------------------------------
resource "google_service_account" "frontend_runtime" {
  account_id   = "${var.name_prefix}-frontend-rt"
  display_name = "${var.name_prefix} Frontend Cloud Run runtime"
  project      = var.project_id
}

# ---------------------------------------------------------------------------
# Cloud Run service — React SPA served by nginx
# ---------------------------------------------------------------------------
locals {
  # Public placeholder so Cloud Run can be created before first app image push.
  # CI replaces this; lifecycle ignore_changes keeps Terraform from reverting it.
  initial_image = "us-docker.pkg.dev/cloudrun/container/hello"
}

resource "google_cloud_run_v2_service" "frontend" {
  name     = "${var.name_prefix}-web"
  project  = var.project_id
  location = var.region
  # Public path is the HTTPS LB + Cloud Armor only (not *.run.app).
  ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  template {
    service_account = google_service_account.frontend_runtime.email

    scaling {
      min_instance_count = 1
      max_instance_count = 3
    }

    containers {
      image = local.initial_image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
    ]
  }
}

# Custom domain → this Cloud Run service (CNAME records are in terraform output).
# Domain must already be verified in Search Console: gcloud domains verify example.com
resource "google_cloud_run_domain_mapping" "frontend" {
  count    = var.custom_domain != "" ? 1 : 0
  name     = var.custom_domain
  location = var.region
  project  = var.project_id

  metadata {
    namespace = var.project_id
  }

  spec {
    route_name = google_cloud_run_v2_service.frontend.name
  }
}

# Allow unauthenticated access (public frontend)
resource "google_cloud_run_v2_service_iam_member" "frontend_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.frontend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
