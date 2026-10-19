# Offline GCP Evidence Viewer

Open an exported GCP benchmark archive with an isolated local Prometheus and Grafana pair. You need Docker Compose v2. The viewer uses loopback ports `3101` and `9091`, a separate Compose project, and its own volumes; it never stops or recreates the normal benchmark stack on ports `3000` and `9090`.

## Start

From the repository root:

```powershell
.\infra\gcp\start-evidence-viewer.ps1 -EvidenceDirectory .\results\gcp\run-20261019112212-evidence-verified
```

The script prints the Grafana and Prometheus URLs. Use [the GCP load-test guide](../README.md) to export another archive before cloud cleanup.

## Stop

For the example run above, remove only the viewer containers and copied volumes:

```powershell
docker compose -p "ride-matching-evidence-run-20261019112212" -f .\infra\gcp\evidence\compose.yaml down -v
```

This does not modify the archived evidence under `results\`.
