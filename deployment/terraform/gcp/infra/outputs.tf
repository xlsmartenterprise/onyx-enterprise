output "project_id" {
  value = var.project_id
}

output "region" {
  value = var.region
}

output "cluster_name" {
  value = google_container_cluster.onyx.name
}

output "cluster_location" {
  value = google_container_cluster.onyx.location
}

output "artifact_registry_repository" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.onyx.repository_id}"
}

output "image_builder_gsa_email" {
  value = google_service_account.image_builder.email
}

output "build_source_bucket" {
  value = google_storage_bucket.build_sources.name
}


output "file_store_bucket" {
  value = google_storage_bucket.files.name
}

output "postgres_private_ip" {
  value = google_sql_database_instance.onyx.private_ip_address
}

output "cloud_sql_instance_name" {
  value = google_sql_database_instance.onyx.name
}

output "redis_host" {
  value = google_redis_instance.onyx.host
}

output "redis_port" {
  value = google_redis_instance.onyx.port
}

output "runtime_gsa_email" {
  value = google_service_account.runtime.email
}

output "external_secrets_gsa_email" {
  value = google_service_account.external_secrets.email
}
