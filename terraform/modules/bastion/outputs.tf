output "instance_name" {
  description = "Bastion GCE instance name"
  value       = google_compute_instance.bastion.name
}

output "zone" {
  description = "Bastion zone"
  value       = google_compute_instance.bastion.zone
}

output "internal_ip" {
  description = "Bastion internal IP"
  value       = google_compute_instance.bastion.network_interface[0].network_ip
}
