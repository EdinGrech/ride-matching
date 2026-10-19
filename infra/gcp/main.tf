terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.gcp_project
  region  = var.region
}

locals {
  repository_url         = "${var.region}-docker.pkg.dev/${var.gcp_project}/${var.artifact_repository_id}"
  spring_image           = "${local.repository_url}/api-spring:${var.build_id}"
  quarkus_image          = "${local.repository_url}/api-quarkus:${var.build_id}"
  grafana_image          = "${local.repository_url}/grafana:${var.build_id}"
  k6_image               = "${local.repository_url}/k6:${var.build_id}"
  mock_idp_image         = "${local.repository_url}/mock-idp:${var.build_id}"
  prometheus_image       = "${local.repository_url}/prometheus:${var.build_id}"
  service_account_prefix = substr(var.service_name, 0, 22)
  benchmark_cells = {
    "spring-jvm-1cpu"  = { cpu = "1", image = local.spring_image }
    "spring-jvm-2cpu"  = { cpu = "2", image = local.spring_image }
    "quarkus-jvm-1cpu" = { cpu = "1", image = local.quarkus_image }
    "quarkus-jvm-2cpu" = { cpu = "2", image = local.quarkus_image }
  }
  api_invokers = {
    for pair in setproduct(keys(local.benchmark_cells), var.invoker_members) :
    "${pair[0]}-${substr(sha1(pair[1]), 0, 8)}" => { cell = pair[0], member = pair[1] }
  }
}

resource "google_project_service" "required" {
  for_each = toset([
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
  ])

  project            = var.gcp_project
  service            = each.value
  disable_on_destroy = false
}

resource "google_artifact_registry_repository" "images" {
  project       = var.gcp_project
  location      = var.region
  repository_id = var.artifact_repository_id
  description   = "Immutable ride-matching service images"
  format        = "DOCKER"

  depends_on = [google_project_service.required]
}

resource "google_service_account" "runtime" {
  project      = var.gcp_project
  account_id   = var.service_account_id
  display_name = "Ride Matching Cloud Run runtime"
}

resource "google_cloud_run_v2_service" "ride_matching" {
  for_each = local.benchmark_cells

  project             = var.gcp_project
  name                = "${var.service_name}-${each.key}"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  template {
    service_account                  = google_service_account.runtime.email
    max_instance_request_concurrency = var.container_concurrency

    scaling {
      min_instance_count = var.min_instance_count
      max_instance_count = var.max_instance_count
    }

    containers {
      image = each.value.image

      ports {
        container_port = 8080
      }

      # The API requires JWTs, so use a TCP probe rather than exposing a public health route.
      startup_probe {
        failure_threshold     = 12
        initial_delay_seconds = 0
        period_seconds        = 5
        timeout_seconds       = 1

        tcp_socket {
          port = 8080
        }
      }

      resources {
        limits = {
          cpu    = each.value.cpu
          memory = "512Mi"
        }
        cpu_idle = false
      }

      env {
        name  = "JWT_ISSUER_URI"
        value = "${google_cloud_run_v2_service.mock_idp.uri}/ride"
      }

      env {
        name  = "JWT_JWK_SET_URI"
        value = "${google_cloud_run_v2_service.mock_idp.uri}/ride/jwks"
      }

      env {
        name  = "CORS_ALLOWED_ORIGINS"
        value = "*"
      }

      env {
        name  = "LOAD_TEST_RUN_ID"
        value = var.test_run_id
      }
    }
  }

  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }

  depends_on = [
    google_artifact_registry_repository.images,
    google_project_service.required,
  ]

  lifecycle {
    precondition {
      condition     = var.max_instance_count >= var.min_instance_count
      error_message = "max_instance_count must be greater than or equal to min_instance_count."
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "invoker" {
  for_each = local.api_invokers

  project  = google_cloud_run_v2_service.ride_matching[each.value.cell].project
  location = google_cloud_run_v2_service.ride_matching[each.value.cell].location
  name     = google_cloud_run_v2_service.ride_matching[each.value.cell].name
  role     = "roles/run.invoker"
  member   = each.value.member
}
