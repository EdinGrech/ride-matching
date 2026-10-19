# Local Observability

Start the backend with its local issuer and Prometheus endpoint:

```powershell
cd ride-matching-springboot
.\mvnw.cmd "-Dspring-boot.run.profiles=local,observability" spring-boot:run
```

From the workspace root, start Prometheus and Grafana:

```powershell
docker compose -f compose.yaml -f compose.observability.yaml up -d prometheus grafana
```

Prometheus scrapes `http://host.docker.internal:8080/actuator/prometheus` every 15 seconds. Grafana is at `http://localhost:3000` with user `admin` and `GRAFANA_ADMIN_PASSWORD` (default `change-me-local-only`).

The k6 Compose profile remote-writes its request metrics to Prometheus every two seconds. Grafana preloads **Ride Matching / Ride Load Test** for totals, **Ride Matching / Ride Load Test Timeline** for diagnostics, and **Ride Matching / Ride Benchmark** for a presentation view of request rate, p95, failure rate, lifecycle completion/abort ratio, and API container CPU and memory. Select `Flow`, `Implementation`, and `Test run` in the benchmark dashboard. The container panels are live metrics for the Compose service `api`, not per-run metrics.

The benchmark stack uses cAdvisor's Docker collector, scraped as `cadvisor`. It exposes `container_cpu_usage_seconds_total` and `container_memory_working_set_bytes`, selected by Compose's `container_label_com_docker_compose_service="api"` label. The collector has no host port, but reads Docker and cgroup paths. It works on Linux Docker hosts. Docker Desktop on Windows and macOS reports the Linux VM's container statistics and may omit or constrain cgroup fields; confirm the two metrics in Prometheus before comparing runs. Actuator metrics remain secured until Prometheus authentication is added.
