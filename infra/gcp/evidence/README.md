# Offline Evidence Viewer

Start an isolated Grafana and Prometheus pair from an exported archive:

```powershell
.\infra\gcp\start-evidence-viewer.ps1 -EvidenceDirectory .\results\gcp\run-20261019112212-evidence-verified
```

The viewer uses loopback ports `3101` and `9091`, a unique Compose project, and its own named volumes. It never stops or recreates the normal local benchmark stack on ports `3000` and `9090`.
