output "artifact_registry_repository" {
  value       = google_artifact_registry_repository.images.name
  description = "Artifact Registry repository resource name."
}

output "cloud_run_url" {
  value       = google_cloud_run_v2_service.ride_matching.uri
  description = "Cloud Run service URL."
}

output "runtime_service_account" {
  value       = google_service_account.runtime.email
  description = "Cloud Run runtime service account."
}
