# GCP Load Test

This directory provisions a disposable, test-only Cloud Run benchmark matrix. It builds Spring Boot and Quarkus JVM images, deploys four single-instance API cells, starts their k6 jobs, and exposes Grafana and Prometheus for the run.

## Prerequisites

Run commands from the repository root on Windows PowerShell. You need:

- `gcloud` authenticated for both the CLI and Application Default Credentials.
- `terraform.exe` 1.6 or later.
- A billing-enabled GCP project and permission to enable APIs and create Cloud Run, Cloud Build, Artifact Registry, IAM, Secret Manager, and monitoring resources.

Use an isolated project and Artifact Registry repository. The stack is public and test-only: the APIs, mock OIDC issuer, Prometheus, and anonymous-admin Grafana allow unauthenticated invocation or access where required by the benchmark.

## Run A Benchmark

`quick` is the default profile. Run a clean full matrix with:

```powershell
.\infra\gcp\run-loadtest.ps1 -Project "your-gcp-project-id" -Region "europe-west1" -Full -Reset
```

The matrix runs Spring and Quarkus at one and two vCPU concurrently. Each API remains one fixed `512 MiB` Cloud Run instance because the benchmarked implementations use in-memory ride state. Each k6 generator has `2 vCPU` and `2 GiB` so it is not the test bottleneck.

The script prints a Grafana URL when the jobs finish. Cloud Monitoring can take several minutes to publish platform samples.

## Export Evidence Before Cleanup

Copy the run ID from the Grafana URL printed by the runner, then export the raw Prometheus, Cloud Monitoring, Cloud Run, Cloud Logging, and Grafana evidence:

```powershell
.\infra\gcp\export-loadtest-evidence.ps1 -Project "your-gcp-project-id" -Region "europe-west1" -RunId "run-..."
```

The default archive path is `results\gcp\<run-id>`. Open a completed archive with the [offline evidence viewer](evidence/README.md).

## Destroy The Stack

Destroy the Cloud Run benchmark resources without starting a new run:

```powershell
.\infra\gcp\run-loadtest.ps1 -Project "your-gcp-project-id" -Region "europe-west1" -Destroy
```

`-Reset` and `-Destroy` run Terraform destruction first. If Terraform cannot remove a non-empty Artifact Registry repository, the runner deletes its packages and retries. Do not reuse that repository for non-test images.
