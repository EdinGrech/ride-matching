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

resource "google_project_service" "required" {
  for_each = toset([
    "artifactregistry.googleapis.com",
    "monitoring.googleapis.com",
    "run.googleapis.com",
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
  project  = var.gcp_project
  name     = var.service_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account                  = google_service_account.runtime.email
    max_instance_request_concurrency = var.container_concurrency

    scaling {
      min_instance_count = 1
      max_instance_count = 1
    }

    containers {
      image = var.image_uri

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "2"
          memory = "2Gi"
        }
      }

      env {
        name  = "JWT_ISSUER_URI"
        value = var.jwt_issuer_uri
      }

      env {
        name  = "JWT_JWK_SET_URI"
        value = var.jwt_jwk_set_uri
      }

      env {
        name  = "CORS_ALLOWED_ORIGINS"
        value = var.cors_allowed_origins
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
}

resource "google_cloud_run_v2_service_iam_member" "invoker" {
  for_each = toset(var.invoker_members)

  project  = google_cloud_run_v2_service.ride_matching.project
  location = google_cloud_run_v2_service.ride_matching.location
  name     = google_cloud_run_v2_service.ride_matching.name
  role     = "roles/run.invoker"
  member   = each.value
}

resource "google_monitoring_dashboard" "cloud_run" {
  project = var.gcp_project

  dashboard_json = jsonencode({
    displayName = "${var.service_name} Cloud Run"
    mosaicLayout = {
      columns = 12
      tiles = [
        {
          xPos   = 0
          yPos   = 0
          width  = 6
          height = 4
          widget = {
            title = "Request rate"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type = \"run.googleapis.com/request_count\" AND resource.type = \"cloud_run_revision\" AND resource.labels.service_name = \"${var.service_name}\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                    }
                  }
                }
              }]
              yAxis = {
                label = "requests/s"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          xPos   = 6
          yPos   = 0
          width  = 6
          height = 4
          widget = {
            title = "Container instances"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type = \"run.googleapis.com/container/instance_count\" AND resource.type = \"cloud_run_revision\" AND resource.labels.service_name = \"${var.service_name}\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
              }]
              yAxis = {
                label = "instances"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          xPos   = 0
          yPos   = 4
          width  = 6
          height = 4
          widget = {
            title = "P95 request latency"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type = \"run.googleapis.com/request_latencies\" AND resource.type = \"cloud_run_revision\" AND resource.labels.service_name = \"${var.service_name}\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_DELTA"
                      crossSeriesReducer = "REDUCE_PERCENTILE_95"
                    }
                  }
                }
              }]
            }
          }
        },
        {
          xPos   = 6
          yPos   = 4
          width  = 6
          height = 4
          widget = {
            title = "5xx error rate"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type = \"run.googleapis.com/request_count\" AND metric.labels.response_code_class = \"5xx\" AND resource.type = \"cloud_run_revision\" AND resource.labels.service_name = \"${var.service_name}\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                    }
                  }
                }
              }]
            }
          }
        },
        {
          xPos   = 0
          yPos   = 8
          width  = 6
          height = 4
          widget = {
            title = "CPU utilization"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type = \"run.googleapis.com/container/cpu/utilizations\" AND resource.type = \"cloud_run_revision\" AND resource.labels.service_name = \"${var.service_name}\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_MEAN"
                    }
                  }
                }
              }]
            }
          }
        },
        {
          xPos   = 6
          yPos   = 8
          width  = 6
          height = 4
          widget = {
            title = "Memory utilization"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type = \"run.googleapis.com/container/memory/utilizations\" AND resource.type = \"cloud_run_revision\" AND resource.labels.service_name = \"${var.service_name}\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_MEAN"
                    }
                  }
                }
              }]
            }
          }
        },
      ]
    }
  })

  depends_on = [google_project_service.required]
}
