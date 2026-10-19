# Ride Matching Service (Quarkus)

In-memory Quarkus implementation of the ride matching API. Driver and ride state is lost when the application restarts.

## Local Development

From the repository root, you need Java 21, Docker Compose v2, and Windows PowerShell. This is an alternative API implementation; the default manual demo uses Spring Boot.

1. Start the local identity provider:

   ```powershell
   docker compose up -d mock-idp
   ```

2. Start the API:

   ```powershell
   .\ride-matching-quarkus\mvnw.cmd quarkus:dev
   ```

The API starts on `http://localhost:8080`. It validates JWTs from the workspace mock issuer and accepts frontend origins at `http://localhost:4200` and `http://localhost:4201` by default.

Run the test suite from the repository root:

```powershell
.\ride-matching-quarkus\mvnw.cmd -f .\ride-matching-quarkus\pom.xml test
```

Stop the API with `Ctrl+C`, then stop the local issuer when finished:

```powershell
docker compose stop mock-idp
```

## Configuration

```properties
ride.gps.pickup-radius-metres=50
ride.offer-timeout=30s
ride.penalty-duration=30m
JWT_JWK_SET_URI=http://localhost:8090/ride/jwks
JWT_ISSUER_URI=http://localhost:8090/ride
CORS_ALLOWED_ORIGINS=http://localhost:4200,http://localhost:4201
```

The API contract is `../ride-matching-springboot/openapi.yaml` while the implementations remain in parallel.
