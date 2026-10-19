# Local Observability

The local benchmark uses Prometheus, Grafana, and cAdvisor. k6 remote-writes workload metrics to Prometheus; cAdvisor supplies CPU and working-set memory for the local Compose API container.

## Start The Stack

From the repository root, with Docker Compose v2 running:

```powershell
docker compose -f compose.yaml -f compose.observability.yaml up -d prometheus grafana
```

Open Grafana at `http://localhost:3000`. Sign in as `admin` with `GRAFANA_ADMIN_PASSWORD`; when unset, the local default is `change-me-local-only`.

Prometheus is available at `http://localhost:9090`.

## What It Collects

- Prometheus scrapes itself and cAdvisor every 15 seconds.
- k6 sends request, latency, check, and lifecycle metrics to Prometheus every two seconds during benchmark runs.
- Grafana preloads the **Ride Matching / Ride Benchmark** dashboard for run-scoped request rate, p50/p95/p99 latency, failures, lifecycle outcomes, and container CPU and memory.
- Container panels represent the current local Compose `api` container. They are not per-run historical measurements.

The current Prometheus configuration does not scrape the Spring Boot actuator endpoint. Actuator metrics remain secured unless an authenticated scrape path is added.

## Teardown

```powershell
docker compose -f compose.yaml -f compose.observability.yaml down
```

Use the [local benchmark guide](../../loadtest/README.md) to run the workload that populates these dashboards.
