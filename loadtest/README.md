# Ride Lifecycle Load Test

`ride-offer-flow.js` continuously repeats a complete rider/driver lifecycle per k6 virtual user (VU) until `DURATION` expires. Each VU is sequential; VUs run concurrently.

| Behavior | Requests |
|---|---|
| Available driver | Availability update, then driver-ride polling every five seconds |
| Active passenger | Ride request, then rider-ride polling every five seconds |
| Lifecycle | Accept, location update, arrive, pickup, complete |
| Declined offer | Primary driver declines; generated fallback driver accepts |

## Local Run

The script generates a unique `driver-k6-*` and `rider-k6-*` JWT for every VU in k6's one-time `setup()` phase. No token shell script is needed. Fresh tokens are generated on every load-test run. Compose reaches the mock issuer over its internal network while keeping its public JWT issuer as `http://localhost:8090/ride`.

Start the mock issuer and dashboards from the workspace root:

```text
docker compose -f compose.yaml -f compose.observability.yaml up -d mock-idp prometheus grafana
```

Start the API from `ride-matching-springboot`:

```powershell
.\mvnw.cmd "-Dspring-boot.run.profiles=local,observability" spring-boot:run
```

Restart the API before every load-test run. Its in-memory ride state is intentionally not shared with k6 and is not reset automatically.

Run the test from the workspace root.

PowerShell:

```powershell
$env:RUN_ID = Get-Date -Format "yyyyMMdd-HHmmss"
$env:VUS = "10"
$env:DURATION = "2m"
$env:MIN_ITERATION_DURATION = "1s"
$env:DECLINE_RATE = "0"
docker compose -f compose.yaml -f compose.observability.yaml --profile load-test run --rm k6
```

Git Bash:

```bash
export RUN_ID="$(date +%Y%m%d-%H%M%S)"
VUS=10 DURATION=2m MIN_ITERATION_DURATION=1s DECLINE_RATE=0 \
  docker compose -f compose.yaml -f compose.observability.yaml --profile load-test run --rm k6
```

For an IDE run configuration, set `SPRING_PROFILES_ACTIVE=local,observability`; `spring-boot.run.profiles` is a Maven-plugin option, not a JVM profile setting.

Use `DECLINE_RATE` between `0` and `1` to include declines. The script then creates one fallback driver per VU automatically. `RUN_ID` is required and identifies generated local users and Prometheus metrics. `VUS` controls concurrent riders and drivers; `DURATION` controls how long they keep requesting rides. The default duration is one minute. `MIN_ITERATION_DURATION` defaults to one second, limiting each simulated user to one new ride per second; set it to `0s` only for maximum-throughput testing.

Prometheus is at `http://localhost:9090`; Grafana is at `http://localhost:3000`. Grafana preloads **Ride Matching / Ride Load Test** for run totals and **Ride Matching / Ride Load Test Timeline** for time-series diagnostics. Select the `Test run` value matching `RUN_ID` in the timeline dashboard. k6 publishes metrics every second so brief runs appear in the dashboard. The API's Actuator metrics require a Prometheus-authentication design before they can be scraped.

## Cloud Run

Run the same Docker k6 command locally against a deployed Cloud Run URL. The deployed API must use a reachable test/production issuer; the local mock issuer cannot issue tokens that Cloud Run trusts.

```powershell
$env:BASE_URL = "https://your-cloud-run-url"
$env:RUN_ID = Get-Date -Format "yyyyMMdd-HHmmss"
$env:GENERATE_LOCAL_TOKENS = "false"
$env:RIDER_TOKENS = '["rider-jwt-1", "rider-jwt-2"]'
$env:DRIVER_TOKENS = '["driver-jwt-1", "driver-jwt-2"]'
$env:VUS = "2"
$env:DURATION = "2m"
$env:MIN_ITERATION_DURATION = "1s"
docker compose -f compose.yaml -f compose.observability.yaml --profile load-test run --rm k6
```

Supply one unique rider and driver token per VU. Add `FALLBACK_DRIVER_TOKENS` when using a nonzero `DECLINE_RATE`.

The suite fails below 99% checks, at 1% failed requests, or when p95 ride-lifecycle request latency exceeds one second. Run 1, 10, 25, 50, and 100 VUs separately and compare request latency, errors, CPU, and memory. The API is deliberately one Cloud Run instance while ride state is in memory.
