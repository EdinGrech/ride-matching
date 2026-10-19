# Ride Matching Angular Demo

Leaflet and OpenStreetMap passenger and driver applications for the Spring Boot ride-matching API. They use the workspace mock OIDC issuer and [the API contract](../ride-matching-springboot/openapi.yaml).

## Start

You need Node.js, npm, the local mock issuer, and the Spring Boot API. Start the issuer and API from the repository root as described in the [root README](../README.md), then run these commands from `ride-matching-angular`:

```powershell
npm ci
```

Start the passenger application:

```powershell
npm run start:passenger
```

In a second terminal in the same directory, start the driver application:

```powershell
npm run start:driver
```

Open `http://localhost:4200` for passengers and `http://localhost:4201` for drivers.

## Demo Flow

1. In the driver application, select **Sign in as driver**. Enter `driver-1` on the mock OAuth page, leave optional claims empty, and select **Sign-in**. Choose a map location and select **Go available**.
2. In the passenger application, select **Sign in as passenger**. Enter `rider-1`, leave optional claims empty, and select **Sign-in**. Choose the pickup and select **Request nearest driver**.
3. The driver application polls for its assignment every five seconds. Select **Arrived at pickup**.
4. In the passenger application, select **Start ride** and then **Complete ride**.

The mock issuer login and token debugger are at `http://localhost:8090/ride/debugger`. The browser login uses Authorization Code with PKCE and is the intended local flow.

## Build And Test

Run these commands from `ride-matching-angular`:

```powershell
npm run build:passenger
npm run build:driver
npm run test -- --watch=false
```

## Notes

- OpenStreetMap tiles are used only for the local visual demo.
- The backend permits both `http://localhost:4200` and `http://localhost:4201` by default. Restart it after pulling backend CORS changes.
- The mock OIDC service is local-test infrastructure, not a production identity provider.
