package pw.pingu.ride_matching_quarkus.ride.api;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.is;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import org.junit.jupiter.api.Test;

@QuarkusTest
class RideResourceTest {

    @Test
    void rejectsUnauthenticatedRequests() {
        given()
                .queryParam("latitude", 51.5)
                .queryParam("longitude", -0.12)
                .queryParam("limit", 1)
                .when().get("/drivers/available")
                .then()
                .statusCode(401);
    }

    @Test
    @TestSecurity(user = "driver-1", roles = "DRIVER")
    void rejectsDriverAtRiderEndpoint() {
        given()
                .contentType("application/json")
                .body("{\"pickup\":{\"latitude\":51.5,\"longitude\":-0.12},\"destination\":{\"latitude\":51.51,\"longitude\":-0.11}}")
                .when().post("/rides")
                .then()
                .statusCode(403);
    }

    @Test
    @TestSecurity(user = "invalid-driver", roles = "DRIVER")
    void returnsValidationErrors() {
        given()
                .contentType("application/json")
                .body("{\"location\":{\"latitude\":51.5,\"longitude\":-0.12}}")
                .when().put("/drivers/me/availability")
                .then()
                .statusCode(400)
                .body("message", is("available is required"));
    }

    @Test
    @TestSecurity(user = "invalid-rider", roles = "RIDER")
    void returnsMalformedRequestErrors() {
        given()
                .contentType("application/json")
                .body("{")
                .when().post("/rides")
                .then()
                .statusCode(400);
    }

    @Test
    void allowsConfiguredFrontendOrigins() {
        given()
                .header("Origin", "http://localhost:4200")
                .header("Access-Control-Request-Method", "POST")
                .when().options("/rides")
                .then()
                .statusCode(200)
                .header("Access-Control-Allow-Origin", "http://localhost:4200");
    }

    @Test
    @TestSecurity(user = "driver-without-ride", roles = "DRIVER")
    void returnsNoContentWhenNoCurrentRideExists() {
        given()
                .when().get("/drivers/me/ride")
                .then()
                .statusCode(204);
    }
}
