resource "google_service_account" "builder" {
  project      = var.gcp_project
  account_id   = "${local.service_account_prefix}-builder"
  display_name = "Ride Matching Cloud Build test builder"
}

resource "google_project_iam_member" "builder" {
  for_each = toset([
    "roles/artifactregistry.writer",
    "roles/cloudbuild.builds.builder",
    "roles/logging.logWriter",
    "roles/storage.objectViewer",
  ])

  project = var.gcp_project
  role    = each.value
  member  = "serviceAccount:${google_service_account.builder.email}"
}
