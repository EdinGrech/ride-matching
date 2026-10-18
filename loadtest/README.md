# Ride Matching Benchmark

Prerequisites: Docker Desktop running Linux containers and JDK 21. Run commands from the workspace root.

## Run

First confirm the environment with the short smoke run:

```powershell
.\loadtest\run-benchmark.ps1 -Backend spring -Cpu 1 -Quick
```

Run the comparison matrix with the full accelerated population ramp:

```powershell
.\loadtest\run-benchmark.ps1 -Backend spring -Cpu 1
.\loadtest\run-benchmark.ps1 -Backend spring -Cpu 2
.\loadtest\run-benchmark.ps1 -Backend quarkus -Cpu 1
.\loadtest\run-benchmark.ps1 -Backend quarkus -Cpu 2
```

Each run packages one backend, recreates it with the selected CPU limit and `512 MiB` memory limit, starts the local observability stack, waits for the API, and runs the benchmark. The script prints the single benchmark URL filtered to that exact run and its exact wall-clock range.

## What It Models

`population-ramp.js` is the only benchmark profile. It runs independent rider and driver virtual users at a `2:5` ratio. Riders request and poll rides; drivers become available, poll state, accept offers, update location, arrive, pick up, and complete rides.

The full run takes about 24 minutes and ramps through 1, 5, 10, 25, and 50 cohorts. At the maximum, that is 100 rider sessions and 250 driver sessions. `TIME_SCALE=60` accelerates virtual client time: a virtual five-second poll occurs every 83 ms and virtual five-to-thirty-minute trips take five-to-thirty seconds. This is an accelerated behavioural stress test, not real-time production traffic.

The test fails on request errors, lifecycle aborts, or dropped iterations. Setup/token traffic is tagged `actor-setup`; measured application traffic is tagged `population-ramp`.

## Evidence

- Grafana: `http://localhost:3000`
- Prometheus: `http://localhost:9090`
- Dashboard: `http://localhost:3000/d/ride-benchmark/ride-benchmark`

The dashboard shows active simulated users, achieved request rate, p50/p95/p99 latency, failures, lifecycle outcomes, and cAdvisor CPU/memory for the internal `api` container. The API is intentionally a single container because ride state is in memory; benchmark population comes from k6 users, not service replicas.

Stop the local stack when finished:

```powershell
docker compose -f compose.yaml -f compose.observability.yaml -f compose.benchmark.yaml down
```
