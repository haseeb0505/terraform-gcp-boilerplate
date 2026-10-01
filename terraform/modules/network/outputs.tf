output "network_id" {
  description = "EI VPC network ID (for Cloud SQL private_network and Cloud Run)"
  value       = google_compute_network.vpc.id
}

output "network_name" {
  value = google_compute_network.vpc.name
}

output "subnet_id" {
  description = "EI application subnet ID (Cloud Run Direct VPC egress)"
  value       = google_compute_subnetwork.app.id
}

output "subnet_name" {
  value = google_compute_subnetwork.app.name
}

output "private_vpc_connection_id" {
  description = "PSA connection ID — Cloud SQL must depend on this"
  value       = google_service_networking_connection.psa.id
}

output "nat_id" {
  description = "Cloud NAT id — Cloud Run ALL_TRAFFIC must depend on this"
  value       = google_compute_router_nat.nat.id
}

output "nat_ips" {
  description = "Reserved Cloud NAT egress IPs (give to the client for allowlists)"
  value       = google_compute_address.nat[*].address
}
