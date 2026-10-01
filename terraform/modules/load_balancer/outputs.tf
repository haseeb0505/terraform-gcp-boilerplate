output "web_lb_ip" {
  description = "Load balancer static IP (HTTP :80 and HTTPS :443)."
  value       = google_compute_global_address.web.address
}

output "api_lb_ip" {
  description = "Load balancer IP for API traffic."
  value       = google_compute_global_address.web.address
}

output "security_policy_name" {
  description = "Cloud Armor security policy name"
  value       = google_compute_security_policy.default.name
}

output "ssl_policy_name" {
  description = "HTTPS proxy SSL policy. Null when no custom domain is configured."
  value       = local.https_enabled ? google_compute_ssl_policy.web[0].name : null
}

output "frontend_dns" {
  description = "DNS A record for frontend_domain."
  value = var.frontend_domain == "" ? null : {
    type    = "A"
    name    = var.frontend_domain
    records = [google_compute_global_address.web.address]
  }
}

output "backend_dns" {
  description = "DNS information for API endpoint."
  value = var.backend_domain != "" ? {
    type    = "A"
    name    = var.backend_domain
    records = [google_compute_global_address.web.address]
    } : (var.frontend_domain != "" ? {
      type    = "PATH"
      name    = "${var.frontend_domain}/api/v1"
      records = [google_compute_global_address.web.address]
  } : null)
}
