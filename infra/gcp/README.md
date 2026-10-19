# GCP Load Test

Run this from the workspace root to reset the disposable stack, build both JVM APIs on Cloud Build, deploy four isolated benchmark cells, start their k6 jobs concurrently, and print the Grafana URL:

```powershell
.\infra\gcp\run-loadtest.ps1 -Project "your-gcp-project-id" -Region "europe-west1" -Reset
```

Only replace these values:

- `Project`: the GCP project ID.
- `Region`: the GCP region.

`quick` is the default profile. Use `-Profile full` for the longer test.

Run a clean full test:

```powershell
.\infra\gcp\run-loadtest.ps1 -Project "your-gcp-project-id" -Region "europe-west1" -Full -Reset
```

The full matrix runs Spring and Quarkus at one and two vCPU concurrently. Each API remains one fixed `512Mi` Cloud Run instance because rides are held in memory. Each k6 generator has `2 vCPU` and `2Gi` so it does not become the test bottleneck.

Grafana restores the local k6 evidence and adds Cloud Run CPU, memory, instances, server latency, request rate, and 5xx telemetry from the Google Cloud datasource. Cloud Monitoring can take several minutes to publish platform samples. Raw request and container logs remain in Cloud Logging and are available from Grafana Explore through the Google Cloud datasource.

The stack is intentionally disposable and test-only: Grafana, Prometheus, and the mock OIDC issuer are public. A full matrix creates substantial request logs; capture the Grafana evidence, then destroy the stack to stop all instance charges.

Destroy the stack without starting a new run:

```powershell
.\infra\gcp\run-loadtest.ps1 -Project "your-gcp-project-id" -Region "europe-west1" -Destroy
```
