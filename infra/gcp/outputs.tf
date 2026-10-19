output "artifact_registry_repository" {
  value       = google_artifact_registry_repository.images.name
  description = "Artifact Registry repository resource name."
}

output "cloud_run_urls" {
  value       = { for cell, service in google_cloud_run_v2_service.ride_matching : cell => service.uri }
  description = "Ride Matching API URLs by benchmark cell."
}

output "mock_idp_url" {
  value       = google_cloud_run_v2_service.mock_idp.uri
  description = "Disposable mock OIDC issuer service URL."
}

output "prometheus_url" {
  value       = google_cloud_run_v2_service.prometheus.uri
  description = "Disposable Prometheus URL."
}

output "grafana_url" {
  value       = google_cloud_run_v2_service.grafana.uri
  description = "Disposable Grafana URL."
}

output "loadtest_jobs" {
  value       = { for cell, job in google_cloud_run_v2_job.loadtest : cell => job.name }
  description = "Cloud Run Jobs that execute the k6 profile by benchmark cell."
}

output "cloud_build_service_account" {
  value       = google_service_account.builder.email
  description = "Service account passed to gcloud builds submit."
}
