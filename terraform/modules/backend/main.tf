locals {
  cors_origins = var.cors_origins != "" ? var.cors_origins : var.frontend_url
}

# ---------------------------------------------------------------------------
# Cloud SQL (PostgreSQL, private IP via VPC + PSA)
# ---------------------------------------------------------------------------
resource "google_sql_database_instance" "postgres" {
  name             = "${var.name_prefix}-postgres"
  project          = var.project_id
  region           = var.region
  database_version = "POSTGRES_16"

  deletion_protection = true

  settings {
    tier              = var.db_tier
    disk_size         = var.db_disk_size_gb
    disk_autoresize   = true
    availability_type = "ZONAL"

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = var.vpc_id
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      location                       = var.region
      point_in_time_recovery_enabled = true
      start_time                     = "03:00"
      transaction_log_retention_days = 7

      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }
  }

  depends_on = [terraform_data.psa_ready]
}

resource "terraform_data" "psa_ready" {
  input = var.private_vpc_connection_id
}

resource "terraform_data" "nat_ready" {
  input = var.nat_id
}

resource "google_sql_database" "app_db" {
  name     = var.db_name
  project  = var.project_id
  instance = google_sql_database_instance.postgres.name
}

# ---------------------------------------------------------------------------
# GCS bucket (application uploads)
# ---------------------------------------------------------------------------
resource "google_storage_bucket" "uploads" {
  name          = var.gcs_bucket_name
  project       = var.project_id
  location      = var.gcs_bucket_location
  force_destroy = false

  uniform_bucket_level_access = true

  cors {
    origin          = [for o in split(",", local.cors_origins) : trimspace(o) if trimspace(o) != ""]
    method          = ["GET", "HEAD", "PUT", "OPTIONS"]
    response_header = ["Content-Type", "Content-Length", "x-goog-resumable"]
    max_age_seconds = 3600
  }

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      days_since_noncurrent_time = 90
    }
  }
}

# ---------------------------------------------------------------------------
# GCS bucket (daily Cloud SQL SQL dumps)
# ---------------------------------------------------------------------------
resource "google_storage_bucket" "db_backups" {
  name                        = "${var.name_prefix}-db-backups"
  project                     = var.project_id
  location                    = var.gcs_bucket_location
  force_destroy               = false
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = false
  }

  soft_delete_policy {
    retention_duration_seconds = 604800
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = var.db_backup_retention_days
    }
  }
}

resource "google_storage_bucket_iam_member" "sql_export" {
  bucket = google_storage_bucket.db_backups.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_sql_database_instance.postgres.service_account_email_address}"
}

# ---------------------------------------------------------------------------
# Cloud Workflows + Scheduler for Daily Cloud SQL Export
# ---------------------------------------------------------------------------
resource "google_workflows_workflow" "sql_export" {
  name            = "${var.name_prefix}-sql-export"
  project         = var.project_id
  region          = var.region
  description     = "Daily offloaded SQL export of ${var.db_name} to Cloud Storage"
  service_account = "${var.name_prefix}-sql-export@${var.project_id}.iam.gserviceaccount.com"
  call_log_level  = "LOG_ERRORS_ONLY"
  source_contents = templatefile("${path.module}/sql_export.yaml.tftpl", {
    project  = var.project_id
    instance = google_sql_database_instance.postgres.name
    database = var.db_name
    bucket   = google_storage_bucket.db_backups.name
  })
}

resource "google_cloud_scheduler_job" "sql_export" {
  name             = "${var.name_prefix}-sql-export"
  project          = var.project_id
  region           = var.region
  description      = "Start the daily Cloud SQL export workflow"
  schedule         = var.db_backup_schedule
  time_zone        = var.db_backup_timezone
  attempt_deadline = "180s"

  http_target {
    http_method = "POST"
    uri         = "https://workflowexecutions.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/workflows/${google_workflows_workflow.sql_export.name}/executions"
    body = base64encode(jsonencode({
      callLogLevel = "LOG_ERRORS_ONLY"
    }))
    headers = {
      "Content-Type" = "application/json"
    }
    oauth_token {
      service_account_email = "${var.name_prefix}-sql-sched@${var.project_id}.iam.gserviceaccount.com"
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }
}

# ---------------------------------------------------------------------------
# Runtime service account (Cloud Run API + migrate/seed jobs)
# ---------------------------------------------------------------------------
resource "google_service_account" "api_runtime" {
  account_id   = "${var.name_prefix}-api-runtime"
  display_name = "${var.name_prefix} API Cloud Run runtime"
  project      = var.project_id
}

resource "google_storage_bucket_iam_member" "api_storage" {
  bucket = google_storage_bucket.uploads.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.api_runtime.email}"
}

resource "google_service_account_iam_member" "api_token_creator" {
  service_account_id = google_service_account.api_runtime.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.api_runtime.email}"
}

# Optional Vertex AI Identity
resource "google_project_service_identity" "aiplatform" {
  count    = var.enable_ai_integration ? 1 : 0
  provider = google-beta
  project  = var.project_id
  service  = "aiplatform.googleapis.com"
}

resource "google_storage_bucket_iam_member" "vertex_gcs_reader" {
  count  = var.enable_ai_integration ? 1 : 0
  bucket = google_storage_bucket.uploads.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_project_service_identity.aiplatform[0].email}"
}

resource "google_secret_manager_secret_iam_member" "api_runtime" {
  for_each  = google_secret_manager_secret.secrets
  project   = var.project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.api_runtime.email}"
}

# ---------------------------------------------------------------------------
# Secret Manager — all app config (no plaintext Cloud Run env values)
# ---------------------------------------------------------------------------
locals {
  database_url_placeholder = "postgresql://USER:PASSWORD@${google_sql_database_instance.postgres.private_ip_address}:5432/${var.db_name}?ssl=require"

  database_url_secrets = {
    "${var.name_prefix}-database-url" = {
      env_name = "DATABASE_URL"
      value    = local.database_url_placeholder
    }
  }

  base_env_values = {
    APP_ENV        = var.app_env
    DEBUG          = tostring(var.debug)
    CORS_ORIGINS   = local.cors_origins
    GCS_BUCKET     = google_storage_bucket.uploads.name
    GCS_PROJECT_ID = var.project_id
  }

  config_env_values = merge(local.base_env_values, var.app_env_vars)

  operator_secrets = {
    for k, v in var.app_secrets :
    "${var.name_prefix}-${replace(lower(k), "_", "-")}" => {
      env_name = k
      value    = v
    }
  }

  config_secrets = {
    for env_name, value in local.config_env_values :
    "${var.name_prefix}-${replace(lower(env_name), "_", "-")}" => {
      env_name = env_name
      value    = value
    }
  }

  secrets = merge(local.config_secrets, local.operator_secrets, local.database_url_secrets)
}

resource "google_secret_manager_secret" "secrets" {
  for_each  = local.secrets
  secret_id = each.key
  project   = var.project_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "config" {
  for_each    = local.config_secrets
  secret      = google_secret_manager_secret.secrets[each.key].id
  secret_data = each.value.value

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [google_sql_database_instance.postgres]
}

resource "google_secret_manager_secret_version" "operator" {
  for_each    = local.operator_secrets
  secret      = google_secret_manager_secret.secrets[each.key].id
  secret_data = each.value.value

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [secret_data]
  }
}

resource "google_secret_manager_secret_version" "database_url" {
  for_each    = local.database_url_secrets
  secret      = google_secret_manager_secret.secrets[each.key].id
  secret_data = each.value.value

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [secret_data]
  }

  depends_on = [google_sql_database_instance.postgres]
}

locals {
  secret_version = merge(
    { for k, v in google_secret_manager_secret_version.config : k => v.version },
    { for k, v in google_secret_manager_secret_version.database_url : k => v.version },
  )

  secret_env_version = {
    for k, v in local.secrets :
    k => (
      contains(keys(local.operator_secrets), k) || v.env_name == "DATABASE_URL"
    ) ? "latest" : local.secret_version[k]
  }
}

# ---------------------------------------------------------------------------
# Cloud Run API service
# ---------------------------------------------------------------------------
locals {
  initial_image = "us-docker.pkg.dev/cloudrun/container/hello"
}

resource "google_cloud_run_v2_service" "api" {
  name     = "${var.name_prefix}-api"
  project  = var.project_id
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  template {
    service_account = google_service_account.api_runtime.email

    vpc_access {
      network_interfaces {
        network    = var.vpc_id
        subnetwork = var.subnet_id
      }
      egress = "ALL_TRAFFIC"
    }

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
        cpu_idle = false
        limits = {
          cpu    = "2"
          memory = "4Gi"
        }
      }

      dynamic "env" {
        for_each = local.secrets
        content {
          name = env.value.env_name
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.secrets[env.key].secret_id
              version = local.secret_env_version[env.key]
            }
          }
        }
      }
    }
  }

  depends_on = [
    terraform_data.nat_ready,
    google_secret_manager_secret_version.database_url,
    google_secret_manager_secret_version.operator,
    google_secret_manager_secret_iam_member.api_runtime,
  ]

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
    ]
  }
}

resource "google_cloud_run_domain_mapping" "api" {
  count    = var.custom_domain != "" ? 1 : 0
  name     = var.custom_domain
  location = var.region
  project  = var.project_id

  metadata {
    namespace = var.project_id
  }

  spec {
    route_name = google_cloud_run_v2_service.api.name
  }
}

resource "google_cloud_run_v2_service_iam_member" "api_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ---------------------------------------------------------------------------
# Cloud Run Job — Database Migration (Optional)
# ---------------------------------------------------------------------------
resource "google_cloud_run_v2_job" "migrate" {
  count    = var.enable_migration_job ? 1 : 0
  name     = "${var.name_prefix}-migrate"
  project  = var.project_id
  location = var.region

  template {
    template {
      service_account = google_service_account.api_runtime.email

      vpc_access {
        network_interfaces {
          network    = var.vpc_id
          subnetwork = var.subnet_id
        }
        egress = "ALL_TRAFFIC"
      }

      containers {
        image   = local.initial_image
        command = var.migration_command

        resources {
          limits = {
            cpu    = "1"
            memory = "512Mi"
          }
        }

        dynamic "env" {
          for_each = local.secrets
          content {
            name = env.value.env_name
            value_source {
              secret_key_ref {
                secret  = google_secret_manager_secret.secrets[env.key].secret_id
                version = local.secret_env_version[env.key]
              }
            }
          }
        }
      }

      max_retries = 1
      timeout     = "300s"
    }
  }

  depends_on = [
    terraform_data.nat_ready,
    google_secret_manager_secret_version.database_url,
    google_secret_manager_secret_version.operator,
    google_secret_manager_secret_iam_member.api_runtime,
  ]

  lifecycle {
    ignore_changes = [
      template[0].template[0].containers[0].image,
    ]
  }
}

# ---------------------------------------------------------------------------
# Cloud Run Job — Database Seed (Optional)
# ---------------------------------------------------------------------------
resource "google_cloud_run_v2_job" "seed" {
  count    = var.enable_seed_job ? 1 : 0
  name     = "${var.name_prefix}-seed"
  project  = var.project_id
  location = var.region

  template {
    template {
      service_account = google_service_account.api_runtime.email

      vpc_access {
        network_interfaces {
          network    = var.vpc_id
          subnetwork = var.subnet_id
        }
        egress = "ALL_TRAFFIC"
      }

      containers {
        image   = local.initial_image
        command = var.seed_command

        resources {
          limits = {
            cpu    = "1"
            memory = "512Mi"
          }
        }

        dynamic "env" {
          for_each = local.secrets
          content {
            name = env.value.env_name
            value_source {
              secret_key_ref {
                secret  = google_secret_manager_secret.secrets[env.key].secret_id
                version = local.secret_env_version[env.key]
              }
            }
          }
        }
      }

      max_retries = 0
      timeout     = "300s"
    }
  }

  depends_on = [
    terraform_data.nat_ready,
    google_secret_manager_secret_version.database_url,
    google_secret_manager_secret_version.operator,
    google_secret_manager_secret_iam_member.api_runtime,
  ]

  lifecycle {
    ignore_changes = [
      template[0].template[0].containers[0].image,
    ]
  }
}
