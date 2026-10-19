resource "google_service_account" "mock_idp" {
  project      = var.gcp_project
  account_id   = "${local.service_account_prefix}-idp"
  display_name = "Ride Matching disposable test identity provider"
}

resource "google_service_account" "prometheus" {
  project      = var.gcp_project
  account_id   = "${local.service_account_prefix}-prom"
  display_name = "Ride Matching disposable Prometheus"
}

resource "google_service_account" "grafana" {
  project      = var.gcp_project
  account_id   = "${local.service_account_prefix}-grafana"
  display_name = "Ride Matching disposable Grafana"
}

resource "google_service_account" "loadtest" {
  project      = var.gcp_project
  account_id   = "${local.service_account_prefix}-k6"
  display_name = "Ride Matching k6 load test"
}

resource "google_secret_manager_secret" "mock_idp_config" {
  project   = var.gcp_project
  secret_id = "${var.service_name}-mock-idp-config"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "mock_idp_config" {
  secret      = google_secret_manager_secret.mock_idp_config.id
  secret_data = file("${path.module}/../mock-idp/config.json")
}

resource "google_secret_manager_secret_iam_member" "mock_idp_config" {
  project   = var.gcp_project
  secret_id = google_secret_manager_secret.mock_idp_config.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.mock_idp.email}"
}

resource "google_cloud_run_v2_service" "mock_idp" {
  project             = var.gcp_project
  name                = "${var.service_name}-idp"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  template {
    service_account = google_service_account.mock_idp.email

    scaling {
      min_instance_count = 1
      max_instance_count = 1
    }

    volumes {
      name = "mock-idp-config"

      secret {
        secret = google_secret_manager_secret.mock_idp_config.secret_id

        items {
          version = "latest"
          path    = "config.json"
        }
      }
    }

    containers {
      image = local.mock_idp_image

      ports {
        container_port = 8080
      }

      volume_mounts {
        name       = "mock-idp-config"
        mount_path = "/config"
      }

      env {
        name  = "JSON_CONFIG_PATH"
        value = "/config/config.json"
      }
    }
  }

  depends_on = [
    google_secret_manager_secret_iam_member.mock_idp_config,
    google_secret_manager_secret_version.mock_idp_config,
    google_artifact_registry_repository.images,
  ]
}

resource "google_cloud_run_v2_service_iam_member" "mock_idp_public" {
  project  = google_cloud_run_v2_service.mock_idp.project
  location = google_cloud_run_v2_service.mock_idp.location
  name     = google_cloud_run_v2_service.mock_idp.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_secret_manager_secret" "prometheus_config" {
  project   = var.gcp_project
  secret_id = "${var.service_name}-prometheus-config"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "prometheus_config" {
  secret = google_secret_manager_secret.prometheus_config.id
  secret_data = yamlencode({
    global = {
      scrape_interval = "5s"
    }
  })
}

resource "google_secret_manager_secret_iam_member" "prometheus_config" {
  project   = var.gcp_project
  secret_id = google_secret_manager_secret.prometheus_config.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.prometheus.email}"
}

resource "google_cloud_run_v2_service" "prometheus" {
  project             = var.gcp_project
  name                = "${var.service_name}-prometheus"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  template {
    service_account = google_service_account.prometheus.email

    scaling {
      min_instance_count = 1
      max_instance_count = 1
    }

    volumes {
      name = "prometheus-config"

      secret {
        secret = google_secret_manager_secret.prometheus_config.secret_id

        items {
          version = "latest"
          path    = "prometheus.yml"
        }
      }
    }

    containers {
      image = local.prometheus_image
      args = [
        "--config.file=/etc/prometheus/prometheus.yml",
        "--storage.tsdb.retention.time=2h",
        "--web.enable-remote-write-receiver",
      ]

      ports {
        container_port = 9090
      }

      volume_mounts {
        name       = "prometheus-config"
        mount_path = "/etc/prometheus"
      }

      resources {
        limits = {
          cpu    = "2"
          memory = "2Gi"
        }
        cpu_idle = false
      }
    }
  }

  depends_on = [
    google_secret_manager_secret_iam_member.prometheus_config,
    google_secret_manager_secret_version.prometheus_config,
  ]
}

resource "google_cloud_run_v2_service_iam_member" "prometheus_public" {
  project  = google_cloud_run_v2_service.prometheus.project
  location = google_cloud_run_v2_service.prometheus.location
  name     = google_cloud_run_v2_service.prometheus.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_project_iam_member" "grafana_observability" {
  for_each = toset([
    "roles/logging.viewer",
    "roles/monitoring.viewer",
  ])

  project = var.gcp_project
  role    = each.value
  member  = "serviceAccount:${google_service_account.grafana.email}"
}

resource "google_cloud_run_v2_service" "grafana" {
  project             = var.gcp_project
  name                = "${var.service_name}-grafana"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  template {
    service_account = google_service_account.grafana.email

    scaling {
      min_instance_count = 1
      max_instance_count = 1
    }

    containers {
      image = local.grafana_image

      ports {
        container_port = 3000
      }

      env {
        name  = "GF_AUTH_ANONYMOUS_ENABLED"
        value = "true"
      }

      env {
        name  = "GF_AUTH_ANONYMOUS_ORG_ROLE"
        value = "Admin"
      }

      env {
        name  = "PROMETHEUS_URL"
        value = google_cloud_run_v2_service.prometheus.uri
      }

      env {
        name  = "GCP_PROJECT"
        value = var.gcp_project
      }
    }
  }

  depends_on = [
    google_project_iam_member.grafana_observability,
    google_artifact_registry_repository.images,
  ]
}

resource "google_cloud_run_v2_service_iam_member" "grafana_public" {
  project  = google_cloud_run_v2_service.grafana.project
  location = google_cloud_run_v2_service.grafana.location
  name     = google_cloud_run_v2_service.grafana.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_v2_job" "loadtest" {
  for_each = local.benchmark_cells

  project             = var.gcp_project
  name                = "${var.service_name}-${each.key}-k6"
  location            = var.region
  deletion_protection = false

  template {
    template {
      service_account = google_service_account.loadtest.email
      max_retries     = 0
      timeout         = var.benchmark_profile == "full" ? "2100s" : "900s"

      containers {
        image = local.k6_image
        args = [
          "run",
          "--tag", "testid=${var.test_run_id}",
          "--tag", "implementation=${each.key}",
          "--out", "experimental-prometheus-rw",
          "/scripts/population-ramp.js",
        ]

        env {
          name  = "BASE_URL"
          value = google_cloud_run_v2_service.ride_matching[each.key].uri
        }

        env {
          name  = "TOKEN_ISSUER"
          value = "${google_cloud_run_v2_service.mock_idp.uri}/ride"
        }

        env {
          name  = "TOKEN_ISSUER_HOST"
          value = trimprefix(google_cloud_run_v2_service.mock_idp.uri, "https://")
        }

        env {
          name  = "RUN_ID"
          value = "${var.test_run_id}-${each.key}"
        }

        env {
          name  = "BENCHMARK_PROFILE"
          value = var.benchmark_profile
        }

        env {
          name  = "TIME_SCALE"
          value = "60"
        }

        env {
          name  = "K6_PROMETHEUS_RW_SERVER_URL"
          value = "${google_cloud_run_v2_service.prometheus.uri}/api/v1/write"
        }

        env {
          name  = "K6_PROMETHEUS_RW_PUSH_INTERVAL"
          value = "5s"
        }

        env {
          name  = "K6_PROMETHEUS_RW_TREND_STATS"
          value = "p(50),p(95),p(99),avg,max"
        }

        resources {
          limits = {
            cpu    = "2"
            memory = "2Gi"
          }
        }
      }
    }
  }

  depends_on = [
    google_cloud_run_v2_service_iam_member.mock_idp_public,
    google_cloud_run_v2_service_iam_member.prometheus_public,
    google_cloud_run_v2_service_iam_member.invoker,
  ]
}
