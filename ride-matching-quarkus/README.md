# Ride Matching Service (Quarkus)

In-memory Quarkus implementation of the ride matching API. Driver and ride state is lost when the application restarts.

## Local Development

Requires Java 21 and Docker.

1. From the workspace root, start the local identity provider:

   ```powershell
   docker compose up -d mock-idp
   ```

2. Start the API:

   ```powershell
   .\mvnw.cmd quarkus:dev
   ```

The API starts on `http://localhost:8080`. It validates JWTs from the workspace mock issuer and accepts frontend origins at `http://localhost:4200` and `http://localhost:4201` by default.

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
