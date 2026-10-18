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

The k6 Compose profile remote-writes its request metrics to Prometheus once per second. Grafana preloads **Ride Matching / Ride Load Test** for totals and **Ride Matching / Ride Load Test Timeline** for request/error rates, p95 and maximum latency, assertion results, and lifecycle outcomes. Select one `testid` at a time in the timeline dashboard. Actuator metrics remain secured until Prometheus authentication is added.
