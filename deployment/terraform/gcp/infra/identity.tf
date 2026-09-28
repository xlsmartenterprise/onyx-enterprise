resource "google_service_account" "runtime" {
  project      = var.project_id
  account_id   = "onyx-staging-runtime"
  display_name = "Onyx staging GCS file store"
  depends_on   = [google_project_service.required]
}

resource "google_service_account" "external_secrets" {
  project      = var.project_id
  account_id   = "onyx-staging-external-secrets"
  display_name = "Onyx staging External Secrets controller"
  depends_on   = [google_project_service.required]
}

resource "google_service_account_iam_member" "runtime_workload_identity" {
  service_account_id = google_service_account.runtime.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[onyx/onyx-runtime]"
}

resource "google_service_account_iam_member" "eso_workload_identity" {
  service_account_id = google_service_account.external_secrets.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[external-secrets/external-secrets]"
}

resource "google_storage_bucket_iam_member" "runtime_objects" {
  bucket = google_storage_bucket.files.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.runtime.email}"
}

# Onyx checks bucket existence in addition to reading/writing objects.
resource "google_storage_bucket_iam_member" "runtime_bucket_metadata" {
  bucket = google_storage_bucket.files.name
  role   = "roles/storage.legacyBucketReader"
  member = "serviceAccount:${google_service_account.runtime.email}"
}

locals {
  secret_ids = toset([
    "onyx-staging-postgres-password",
    "onyx-staging-redis-password",
    "onyx-staging-opensearch-password",
    "onyx-staging-user-auth-secret",
  ])
}

resource "google_secret_manager_secret" "onyx" {
  for_each  = local.secret_ids
  project   = var.project_id
  secret_id = each.key

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}

resource "random_password" "opensearch" {
  length           = 32
  special          = true
  min_upper        = 4
  min_lower        = 4
  min_numeric      = 4
  min_special      = 2
  override_special = "!@#%_-"
}

resource "random_id" "user_auth" {
  byte_length = 32
}

resource "google_secret_manager_secret_version" "postgres" {
  secret      = google_secret_manager_secret.onyx["onyx-staging-postgres-password"].id
  secret_data = random_password.postgres.result
}

resource "google_secret_manager_secret_version" "redis" {
  secret      = google_secret_manager_secret.onyx["onyx-staging-redis-password"].id
  secret_data = google_redis_instance.onyx.auth_string
}

resource "google_secret_manager_secret_version" "opensearch" {
  secret      = google_secret_manager_secret.onyx["onyx-staging-opensearch-password"].id
  secret_data = random_password.opensearch.result
}

resource "google_secret_manager_secret_version" "user_auth" {
  secret      = google_secret_manager_secret.onyx["onyx-staging-user-auth-secret"].id
  secret_data = random_id.user_auth.hex
}

resource "google_secret_manager_secret_iam_member" "eso_read" {
  for_each  = google_secret_manager_secret.onyx
  project   = var.project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.external_secrets.email}"
}
