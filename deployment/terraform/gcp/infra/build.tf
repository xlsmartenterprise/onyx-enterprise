# A separate builder identity can publish immutable, reviewed images without
# granting Kubernetes nodes write access to the registry or storing JSON keys.
resource "google_service_account" "image_builder" {
  project      = var.project_id
  account_id   = "onyx-staging-image-builder"
  display_name = "Onyx staging Cloud Build image publisher"
  depends_on   = [google_project_service.required]
}

resource "google_storage_bucket" "build_sources" {
  project                     = var.project_id
  name                        = "${var.project_id}-${data.google_project.current.number}-onyx-build"
  location                    = upper(var.region)
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 7
    }
  }
}

resource "google_storage_bucket_iam_member" "builder_sources" {
  bucket = google_storage_bucket.build_sources.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.image_builder.email}"
}

resource "google_artifact_registry_repository_iam_member" "builder_push" {
  project    = var.project_id
  location   = google_artifact_registry_repository.onyx.location
  repository = google_artifact_registry_repository.onyx.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.image_builder.email}"
}

resource "google_project_iam_member" "builder_logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.image_builder.email}"
}
