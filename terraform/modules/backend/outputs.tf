output "service_url" {
  value = google_cloud_run_v2_service.api.uri
}

output "service_name" {
  value = google_cloud_run_v2_service.api.name
}

output "domain_records" {
  description = "DNS records to add at the DNS host (Hostinger) for the custom domain"
  value = var.custom_domain == "" ? [] : try(
    google_cloud_run_domain_mapping.api[0].status[0].resource_records,
    []
  )
}

output "cloud_sql_connection_name" {
  value = google_sql_database_instance.postgres.connection_name
}

output "cloud_sql_private_ip" {
  value = google_sql_database_instance.postgres.private_ip_address
}

output "gcs_bucket_name" {
  value = google_storage_bucket.uploads.name
}

output "db_backup_bucket" {
  description = "GCS bucket for daily Cloud SQL exports"
  value       = google_storage_bucket.db_backups.name
}

output "api_runtime_sa_email" {
  value = google_service_account.api_runtime.email
}
