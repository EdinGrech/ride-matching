# Ride Matching

Ride matching demo with a Spring Boot API and Angular passenger and driver applications.

## Run the Demo

Requires Java 21, Docker, and Node.js with npm.

1. Start the local identity provider:

   ```powershell
   docker compose up -d mock-idp
   ```

2. Start the API:

   ```powershell
   .\ride-matching-springboot\mvnw.cmd "-Dspring-boot.run.profiles=local" spring-boot:run
   ```

3. In `ride-matching-angular`, install dependencies and start the passenger and driver applications in separate terminals:

   ```powershell
   npm ci
   npm run start:passenger
   npm run start:driver
   ```

Open `http://localhost:4200` for the passenger application and `http://localhost:4201` for the driver application.

See the project READMEs for the demo flow and implementation details.

`ride-matching-quarkus` is an independent Quarkus starter and is not part of the Spring Boot and Angular demo path.
