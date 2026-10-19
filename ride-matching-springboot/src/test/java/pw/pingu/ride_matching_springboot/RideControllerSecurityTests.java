package pw.pingu.ride_matching_springboot;

import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.options;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
class RideControllerSecurityTests {

	@Autowired
	private MockMvc mockMvc;

	@Test
	void rejectsUnauthenticatedRequests() throws Exception {
		mockMvc.perform(get("/drivers/available").param("latitude", "51.5").param("longitude", "-0.12").param("limit", "1"))
				.andExpect(status().isUnauthorized())
				.andExpect(jsonPath("$.message").value("Authentication is required"));
	}

	@Test
	void rejectsDriverAtRiderEndpoint() throws Exception {
		mockMvc.perform(post("/rides")
				.with(jwt().jwt(token -> token.subject("driver-1").claim("roles", List.of("DRIVER")))
						.authorities(new SimpleGrantedAuthority("ROLE_DRIVER")))
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"pickup\":{\"latitude\":51.5,\"longitude\":-0.12},\"destination\":{\"latitude\":51.51,\"longitude\":-0.11}}"))
				.andExpect(status().isForbidden())
				.andExpect(jsonPath("$.message").value("Access is denied"));
	}

	@Test
	void returnsConsistentErrorsForInvalidRequests() throws Exception {
		mockMvc.perform(put("/drivers/me/availability")
				.with(jwt().jwt(token -> token.subject("invalid-driver").claim("roles", List.of("DRIVER")))
						.authorities(new SimpleGrantedAuthority("ROLE_DRIVER")))
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"location\":{\"latitude\":51.5,\"longitude\":-0.12}}"))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.message").value("available is required"));

		mockMvc.perform(post("/rides")
				.with(jwt().jwt(token -> token.subject("invalid-rider").claim("roles", List.of("RIDER")))
						.authorities(new SimpleGrantedAuthority("ROLE_RIDER")))
				.contentType(MediaType.APPLICATION_JSON)
				.content("{"))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.message").value("Malformed request"));
	}

	@Test
	void allowsTheConfiguredFrontendOrigin() throws Exception {
		for (String origin : List.of("http://localhost:4200", "http://localhost:4201")) {
			for (String method : List.of("POST", "DELETE")) {
				mockMvc.perform(options("/rides")
						.header("Origin", origin)
						.header("Access-Control-Request-Method", method))
						.andExpect(status().isOk())
						.andExpect(header().string("Access-Control-Allow-Origin", origin));
			}
		}
	}

	@Test
	void returnsNoContentWhenNoCurrentRideExists() throws Exception {
		mockMvc.perform(get("/drivers/me/ride")
				.with(jwt().jwt(token -> token.subject("driver-1").claim("roles", List.of("DRIVER")))
						.authorities(new SimpleGrantedAuthority("ROLE_DRIVER"))))
				.andExpect(status().isNoContent());
		mockMvc.perform(get("/riders/me/ride")
				.with(jwt().jwt(token -> token.subject("rider-1").claim("roles", List.of("RIDER")))
						.authorities(new SimpleGrantedAuthority("ROLE_RIDER"))))
				.andExpect(status().isNoContent());
	}

	@Test
	void restrictsDriverStatusToTheAuthenticatedDriverRole() throws Exception {
		mockMvc.perform(get("/drivers/me")
				.with(jwt().jwt(token -> token.subject("rider-1").claim("roles", List.of("RIDER")))
						.authorities(new SimpleGrantedAuthority("ROLE_RIDER"))))
				.andExpect(status().isForbidden());
	}

	@Test
	void driverControlsTheLifecycleAndDoesNotSeeDestinationBeforePickup() throws Exception {
		String driver = "mvc-driver";
		String rider = "mvc-rider";
		mockMvc.perform(put("/drivers/me/availability")
				.with(jwt().jwt(token -> token.subject(driver).claim("roles", List.of("DRIVER")))
						.authorities(new SimpleGrantedAuthority("ROLE_DRIVER")))
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"available\":true,\"location\":{\"latitude\":51.5,\"longitude\":-0.12}}"))
				.andExpect(status().isOk());
		String ride = mockMvc.perform(post("/rides")
				.with(jwt().jwt(token -> token.subject(rider).claim("roles", List.of("RIDER")))
						.authorities(new SimpleGrantedAuthority("ROLE_RIDER")))
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"pickup\":{\"latitude\":51.5,\"longitude\":-0.12},\"destination\":{\"latitude\":51.51,\"longitude\":-0.11}}"))
				.andExpect(status().isCreated())
				.andExpect(jsonPath("$.status").value("OFFERED"))
				.andReturn().getResponse().getContentAsString().replaceFirst("^\\{\\\"id\\\":\\\"([^\\\"]+)\\\".*", "$1");

		mockMvc.perform(get("/drivers/me/ride")
				.with(jwt().jwt(token -> token.subject(driver).claim("roles", List.of("DRIVER")))
						.authorities(new SimpleGrantedAuthority("ROLE_DRIVER"))))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.destination").doesNotExist());
		mockMvc.perform(post("/rides/{rideId}/accept", ride)
				.with(jwt().jwt(token -> token.subject(driver).claim("roles", List.of("DRIVER")))
						.authorities(new SimpleGrantedAuthority("ROLE_DRIVER"))))
				.andExpect(status().isOk());
		mockMvc.perform(post("/rides/{rideId}/arrive", ride)
				.with(jwt().jwt(token -> token.subject(driver).claim("roles", List.of("DRIVER")))
						.authorities(new SimpleGrantedAuthority("ROLE_DRIVER"))))
				.andExpect(status().isOk());
		mockMvc.perform(post("/rides/{rideId}/pickup", ride)
				.with(jwt().jwt(token -> token.subject(driver).claim("roles", List.of("DRIVER")))
						.authorities(new SimpleGrantedAuthority("ROLE_DRIVER"))))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.destination.latitude").value(51.51));
		mockMvc.perform(post("/rides/{rideId}/complete", ride)
				.with(jwt().jwt(token -> token.subject(rider).claim("roles", List.of("RIDER")))
						.authorities(new SimpleGrantedAuthority("ROLE_RIDER"))))
				.andExpect(status().isForbidden());
	}

}
