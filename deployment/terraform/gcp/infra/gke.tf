resource "google_service_account" "gke_nodes" {
  project      = var.project_id
  account_id   = "onyx-staging-gke-nodes"
  display_name = "Onyx staging GKE nodes (no application data access)"
  depends_on   = [google_project_service.required]
}

resource "google_project_iam_member" "node_telemetry" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_container_cluster" "onyx" {
  project                   = var.project_id
  name                      = var.cluster_name
  location                  = var.region
  network                   = google_compute_network.onyx.id
  subnetwork                = google_compute_subnetwork.private.id
  remove_default_node_pool  = true
  initial_node_count        = 1
  deletion_protection       = true
  enable_shielded_nodes     = true
  datapath_provider         = "ADVANCED_DATAPATH"
  default_max_pods_per_node = 64

  release_channel {
    channel = "REGULAR"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "onyx-staging-pods"
    services_secondary_range_name = "onyx-staging-services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = toset(var.admin_cidrs)
      content {
        cidr_block   = cidr_blocks.value
        display_name = "approved-admin"
      }
    }
  }

  addons_config {
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
  }

  depends_on = [google_project_service.required]
}

resource "google_container_node_pool" "regional" {
  project  = var.project_id
  name     = "onyx-staging-general"
  location = var.region
  cluster  = google_container_cluster.onyx.name

  autoscaling {
    # Regional min/max counts apply PER ZONE (three zones => 3 to 6 nodes).
    min_node_count = 1
    max_node_count = 2
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type    = var.node_machine_type
    image_type      = "COS_CONTAINERD"
    disk_type       = "pd-balanced"
    disk_size_gb    = 100
    service_account = google_service_account.gke_nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    linux_node_config {
      sysctls = {
        "vm.max_map_count" = "262144"
      }
    }
  }

  depends_on = [google_compute_router_nat.egress, google_project_iam_member.node_telemetry]
}
