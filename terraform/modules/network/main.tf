# ---------------------------------------------------------------------------
# EI VPC + application subnet (Cloud Run Direct VPC egress)
# ---------------------------------------------------------------------------
resource "google_compute_network" "vpc" {
  name                    = "${var.name_prefix}-vpc"
  project                 = var.project_id
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "app" {
  name          = "${var.name_prefix}-app"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.app_subnet_cidr
  # Off so *.googleapis.com (Vertex, GCS, Speech) egress via Cloud NAT.
  # PGA would keep that traffic on Google's private path.
  private_ip_google_access = false
}

# ---------------------------------------------------------------------------
# Private Services Access (Cloud SQL private IP)
# ---------------------------------------------------------------------------
resource "google_compute_global_address" "psa" {
  name          = "${var.name_prefix}-psa"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = tonumber(split("/", var.psa_range_cidr)[1])
  address       = split("/", var.psa_range_cidr)[0]
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "psa" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa.name]
}

# ---------------------------------------------------------------------------
# Cloud Router + Cloud NAT (static PREMIUM IPs) for workload internet egress
# ---------------------------------------------------------------------------
resource "google_compute_router" "nat" {
  name    = "${var.name_prefix}-router"
  project = var.project_id
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_address" "nat" {
  count        = var.nat_ip_count
  name         = var.nat_ip_count == 1 ? "${var.name_prefix}-nat-ip" : "${var.name_prefix}-nat-ip-${count.index + 1}"
  project      = var.project_id
  region       = var.region
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.name_prefix}-nat"
  project                            = var.project_id
  router                             = google_compute_router.nat.name
  region                             = var.region
  nat_ip_allocate_option             = "MANUAL_ONLY"
  nat_ips                            = google_compute_address.nat[*].self_link
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.app.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  enable_dynamic_port_allocation      = true
  enable_endpoint_independent_mapping = false
  min_ports_per_vm                    = 64

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
