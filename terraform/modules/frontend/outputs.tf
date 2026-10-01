output "service_url" {
  value = google_cloud_run_v2_service.frontend.uri
}

output "service_name" {
  value = google_cloud_run_v2_service.frontend.name
}

output "domain_records" {
  description = "DNS records to add at the DNS host (Hostinger) for the custom domain"
  value = var.custom_domain == "" ? [] : try(
    google_cloud_run_domain_mapping.frontend[0].status[0].resource_records,
    []
  )
}
