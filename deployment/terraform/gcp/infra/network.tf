locals {
  required_apis = toset([
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "redis.googleapis.com",
    "secretmanager.googleapis.com",
    "servicenetworking.googleapis.com",
    "sqladmin.googleapis.com",
  ])
}

# Existing project: never disable a shared API when tearing down staging.
resource "google_project_service" "required" {
  for_each           = local.required_apis
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# Separate from the legacy API set: adding an entry to that for_each defers the
# pinned PSA module's network data lookup and plans to replace live SQL peering.
resource "google_project_service" "vertex_ai" {
  project            = var.project_id
  service            = "aiplatform.googleapis.com"
  disable_on_destroy = false
}

resource "google_compute_network" "onyx" {
  project                 = var.project_id
  name                    = "onyx-staging-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  depends_on              = [google_project_service.required["compute.googleapis.com"]]
}

# Dedicated global VIP for the GKE external HTTPS load balancer; DNS lives
# outside this project and must point at this output for certificate issuance.
resource "google_compute_global_address" "chat" {
  project = var.project_id
  name    = "onyx-staging-chat-ip"
}

resource "google_compute_subnetwork" "private" {
  project                  = var.project_id
  name                     = "onyx-staging-private"
  region                   = var.region
  network                  = google_compute_network.onyx.id
  ip_cidr_range            = var.network_cidr
  private_ip_google_access = true
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
  secondary_ip_range {
    range_name    = "onyx-staging-pods"
    ip_cidr_range = var.pods_cidr
  }
  secondary_ip_range {
    range_name    = "onyx-staging-services"
    ip_cidr_range = var.services_cidr
  }
}

resource "google_compute_router" "egress" {
  project = var.project_id
  name    = "onyx-staging-router"
  region  = var.region
  network = google_compute_network.onyx.id
}

resource "google_compute_router_nat" "egress" {
  project                            = var.project_id
  name                               = "onyx-staging-nat"
  region                             = var.region
  router                             = google_compute_router.egress.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# XLSMART's public PSA module handles the VPC peering used by SQL + Redis.
# This is NOT a project-services module; APIs above stay Terraform-native.
module "private_service_access" {
  source = "git::https://github.com/xlsmartenterprise/tfmodule-google-private-services-access.git?ref=b8f47c9eed605fa3cc61cf586bbfebafb0633109"

  project_id    = var.project_id
  vpc_network   = google_compute_network.onyx.name
  name          = "onyx-staging-managed-services"
  address       = var.private_services_cidr
  prefix_length = 16

  depends_on = [google_project_service.required["servicenetworking.googleapis.com"], google_compute_network.onyx]
}
