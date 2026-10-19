# Ride Matching

Ride Matching is a Java service that assigns the nearest available driver to a rider, with Angular passenger and driver applications for the local journey. The core exercise uses in-memory state; the benchmark and GCP material are optional engineering extensions.

## Quick Start

Run these commands from the repository root. You need Java 21, Docker Desktop with Docker Compose v2, Node.js, and npm.

Start the local OIDC test issuer:

```powershell
docker compose up -d mock-idp
```

Start the Spring Boot API:

```powershell
.\ride-matching-springboot\mvnw.cmd "-Dspring-boot.run.profiles=local" spring-boot:run
```

In a second terminal, install the frontend dependencies and start the passenger application:

```powershell
Set-Location .\ride-matching-angular
npm ci
npm run start:passenger
```

In a third terminal, from `ride-matching-angular`, start the driver application:

```powershell
npm run start:driver
```

Open `http://localhost:4200` for the passenger application and `http://localhost:4201` for the driver application.

At the mock OIDC sign-in screen, use `rider-1` in the passenger application and `driver-1` in the driver application. Leave optional claims blank, then select **Sign-in**. The `rider-` and `driver-` prefixes assign the required local roles automatically.

## Documentation Map

| Guide | Use it for |
| --- | --- |
| [Spring Boot API](ride-matching-springboot/README.md) | API setup, authentication, lifecycle rules, configuration, and the full state diagram. |
| [Angular applications](ride-matching-angular/README.md) | Passenger and driver frontend setup and manual demo flow. |
| [Quarkus API](ride-matching-quarkus/README.md) | Alternative JVM implementation used by the benchmark. |
| [Local benchmark](loadtest/README.md) | Repeatable Spring or Quarkus k6 runs and local Grafana results. |
| [Local observability](infra/observability/README.md) | Prometheus, Grafana, and cAdvisor used by local benchmarks. |
| [Mock identity provider](infra/mock-idp/README.md) | Local OIDC issuer, test identities, and token debugger. |
| [Bruno collection](ride-matching-springboot/bruno/README.md) | Calling the Spring Boot API without the Angular applications. |
| [GCP load test](infra/gcp/README.md) | Disposable Cloud Run benchmark matrix, export, and teardown. |
| [Offline GCP evidence viewer](infra/gcp/evidence/README.md) | Opening an exported GCP archive locally without recreating cloud resources. |
| [Shared Angular API](ride-matching-angular/projects/shared-api/README.md) | Typed API client and shared ride and driver models. |
| [Shared Angular authentication](ride-matching-angular/projects/shared-auth/README.md) | OIDC facade, interceptor, and authentication configuration. |
| [Shared Angular map](ride-matching-angular/projects/shared-map/README.md) | Leaflet map component and map types. |

## Repository Layout

- `ride-matching-springboot`: primary Spring Boot implementation.
- `ride-matching-quarkus`: parallel Quarkus JVM implementation.
- `ride-matching-angular`: passenger, driver, and shared Angular projects.
- `loadtest`: k6 workload and local benchmark runner.
- `infra`: local OIDC, observability, and disposable GCP benchmark infrastructure.

Generated benchmark archives live under `results/` and are intentionally ignored by Git.
