output "project_id" {
  description = "GCP project ID"
  value       = var.project_id
}

output "region" {
  description = "GCP region"
  value       = var.region
}

output "name_prefix" {
  description = "Resource name prefix"
  value       = var.name_prefix
}

output "backend_service_url" {
  description = "Cloud Run backend API URL (*.run.app). Internal/LB only."
  value       = module.backend.service_url
}

output "frontend_service_url" {
  description = "Cloud Run frontend URL (*.run.app). Internal/LB only (null if frontend disabled)."
  value       = var.enable_frontend ? module.frontend[0].service_url : null
}

output "cloud_sql_instance_connection" {
  description = "Cloud SQL instance connection name (project:region:instance)"
  value       = module.backend.cloud_sql_connection_name
}

output "cloud_sql_private_ip" {
  description = "Cloud SQL private IP (VPC only; use IAP bastion tunnel for local access)"
  value       = module.backend.cloud_sql_private_ip
}

output "bastion_instance_name" {
  description = "IAP bastion GCE instance name"
  value       = module.bastion.instance_name
}

output "bastion_zone" {
  description = "IAP bastion zone"
  value       = module.bastion.zone
}

output "vpc_network" {
  description = "VPC network name"
  value       = module.network.network_name
}

output "app_subnet" {
  description = "Application subnet name"
  value       = module.network.subnet_name
}

output "nat_ips" {
  description = "Reserved Cloud NAT egress IPs (for allowlisting external APIs)"
  value       = module.network.nat_ips
}

output "gcs_bucket" {
  description = "GCS bucket for uploads"
  value       = module.backend.gcs_bucket_name
}

output "db_backup_bucket" {
  description = "GCS bucket for daily Cloud SQL exports"
  value       = module.backend.db_backup_bucket
}

output "artifact_registry_repo" {
  description = "Artifact Registry Docker repository URL"
  value       = module.shared.artifact_registry_repo
}

output "ci_service_account_email" {
  description = "Service account used by GitHub Actions / CI for deployments"
  value       = "${var.ci_service_account_id}@${var.project_id}.iam.gserviceaccount.com"
}

output "wif_provider" {
  description = "Workload Identity Federation provider resource name"
  value       = var.project_number != "" ? "projects/${var.project_number}/locations/global/workloadIdentityPools/${var.wif_pool_id}/providers/${var.wif_provider_id}" : ""
}

output "web_lb_ip" {
  description = "Load balancer static public IP address"
  value       = module.load_balancer.web_lb_ip
}

output "api_lb_ip" {
  description = "Load balancer static public IP address for API"
  value       = module.load_balancer.api_lb_ip
}

output "frontend_dns" {
  description = "DNS A record for frontend_domain"
  value       = module.load_balancer.frontend_dns
}

output "backend_dns" {
  description = "DNS information for API endpoint"
  value       = module.load_balancer.backend_dns
}

output "cloud_armor_policy" {
  description = "Cloud Armor security policy name"
  value       = module.load_balancer.security_policy_name
}

output "ssl_policy" {
  description = "SSL policy name on the HTTPS proxy"
  value       = module.load_balancer.ssl_policy_name
}
