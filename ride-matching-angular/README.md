# Ride Matching Angular Demo

Leaflet/OSM dashboard for the Spring Boot ride-matching API. It uses the workspace mock OIDC issuer and the API contract in `../ride-matching-springboot/openapi.yaml`.

## Start

1. Start the mock issuer from the workspace root:

   ```powershell
   docker compose up -d mock-idp
   ```

2. Start the Spring Boot API with its `local` profile:

   ```powershell
   cd ..\ride-matching-springboot
   .\mvnw.cmd "-Dspring-boot.run.profiles=local" spring-boot:run
   ```

3. Start the passenger application:

   ```powershell
   npm run start:passenger
   ```

4. In a second terminal, start the driver application:

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

## Notes

- OpenStreetMap tiles are used only for the local visual demo.
- The backend permits Angular's `http://localhost:4200` origin by default. Restart it after pulling backend CORS changes.
- The mock OIDC service is local-test infrastructure, not a production identity provider.
