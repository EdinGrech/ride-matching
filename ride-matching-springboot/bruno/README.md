# Bruno Collection

Use this collection to call the local API without the Angular applications.

1. Start `mock-idp` and the Spring Boot application as described in the [root README](../README.md).
2. Install the free [Bruno desktop app](https://www.usebruno.com/downloads/) and select **Open Collection**, then choose this `bruno` directory.
3. Obtain a driver and rider access token from `http://localhost:8090/ride/debugger`. Sign in with unique subjects such as `driver-alex` and `rider-sam`, then copy each access token.
4. In the collection's **Vars** tab, set `driverToken` and `passengerToken`. Set `adminToken` only to call the optional nearby-driver request.
5. Run **Driver goes available**, **Passenger requests ride**, **Driver accepts offer**, **Driver arrives**, **Driver picks up rider**, and **Driver completes ride**.

The passenger request stores its response ID as `rideId`, which the driver requests reuse. Decline and cancellation are alternative flows, not part of the happy path.

Tokens are for the local mock provider only. Do not use this token-generation approach with a production identity provider.
