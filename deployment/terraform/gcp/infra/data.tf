data "google_project" "current" {
  project_id = var.project_id
}

resource "google_sql_database_instance" "onyx" {
  project             = var.project_id
  name                = "onyx-staging-postgres"
  region              = var.region
  database_version    = "POSTGRES_16"
  deletion_protection = true

  settings {
    tier                        = var.sql_tier
    availability_type           = "REGIONAL"
    disk_type                   = "PD_SSD"
    disk_size                   = 100
    disk_autoresize             = true
    deletion_protection_enabled = true

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.onyx.id
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      start_time                     = "17:00"
      location                       = var.region
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 14
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = 7
      hour         = 17
      update_track = "stable"
    }
  }

  depends_on = [module.private_service_access, google_project_service.required]
}

resource "google_sql_database" "onyx" {
  project  = var.project_id
  instance = google_sql_database_instance.onyx.name
  name     = "onyx"
}

resource "random_password" "postgres" {
  length  = 40
  special = false
}

resource "google_sql_user" "onyx" {
  project  = var.project_id
  instance = google_sql_database_instance.onyx.name
  name     = "onyx"
  password = random_password.postgres.result
}

resource "google_redis_instance" "onyx" {
  project                 = var.project_id
  name                    = "onyx-staging-redis"
  region                  = var.region
  tier                    = "STANDARD_HA"
  memory_size_gb          = 5
  redis_version           = "REDIS_7_0"
  authorized_network      = google_compute_network.onyx.id
  connect_mode            = "PRIVATE_SERVICE_ACCESS"
  auth_enabled            = true
  transit_encryption_mode = "SERVER_AUTHENTICATION"

  persistence_config {
    persistence_mode    = "RDB"
    rdb_snapshot_period = "SIX_HOURS"
  }

  depends_on = [module.private_service_access, google_project_service.required]
}

resource "google_storage_bucket" "files" {
  project                     = var.project_id
  name                        = "${var.project_id}-${data.google_project.current.number}-onyx-files"
  location                    = upper(var.region)
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }

  # File deletion remains functional. Older generations provide recovery but
  # are bounded to avoid indefinite storage accumulation.
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age        = 30
      with_state = "ARCHIVED"
    }
  }
}

resource "google_artifact_registry_repository" "onyx" {
  project       = var.project_id
  location      = var.region
  repository_id = "onyx-staging"
  format        = "DOCKER"
  docker_config {
    immutable_tags = true
  }

  description = "Immutable XLSMART-branded Onyx staging images"
  depends_on  = [google_project_service.required]
}

resource "google_artifact_registry_repository_iam_member" "node_pull" {
  project    = var.project_id
  location   = google_artifact_registry_repository.onyx.location
  repository = google_artifact_registry_repository.onyx.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.gke_nodes.email}"
}
