# ---------------------------------------------------------------------------
# IAP bastion — no public IP; laptop DB access via SSH LocalForward
# ---------------------------------------------------------------------------
resource "google_service_account" "bastion" {
  account_id   = "${var.name_prefix}-bastion"
  display_name = "${var.name_prefix} IAP bastion"
  project      = var.project_id
}

resource "google_compute_instance" "bastion" {
  name         = "${var.name_prefix}-bastion"
  project      = var.project_id
  zone         = var.zone
  machine_type = "e2-micro"

  tags = ["iap-bastion"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = var.subnet_id
    # No access_config => no external IP
  }

  service_account {
    email  = google_service_account.bastion.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  allow_stopping_for_update = true
}

# IAP TCP forwarding to SSH only (not 0.0.0.0/0)
resource "google_compute_firewall" "iap_ssh" {
  name    = "${var.name_prefix}-allow-iap-ssh"
  project = var.project_id
  network = var.network_name

  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.iap_ssh_source_cidrs
  target_tags   = ["iap-bastion"]
}

resource "google_project_iam_member" "iap_tunnel" {
  for_each = toset(var.operator_members)
  project  = var.project_id
  role     = "roles/iap.tunnelResourceAccessor"
  member   = each.value
}

resource "google_project_iam_member" "os_login" {
  for_each = toset(var.operator_members)
  project  = var.project_id
  role     = "roles/compute.osLogin"
  member   = each.value
}

# Allow OS Login users to act as the bastion SA (required for OS Login SSH)
resource "google_service_account_iam_member" "bastion_sa_user" {
  for_each           = toset(var.operator_members)
  service_account_id = google_service_account.bastion.name
  role               = "roles/iam.serviceAccountUser"
  member             = each.value
}
