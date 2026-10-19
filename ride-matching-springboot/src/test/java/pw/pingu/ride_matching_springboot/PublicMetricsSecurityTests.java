package pw.pingu.ride_matching_springboot;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest(properties = {
		"app.metrics.public=true",
		"management.endpoints.web.exposure.include=prometheus",
})
@AutoConfigureMockMvc
class PublicMetricsSecurityTests {

	@Autowired
	private MockMvc mockMvc;

	@Test
	void exposesPrometheusOnlyWhenTheTestFlagIsEnabled() throws Exception {
		mockMvc.perform(get("/actuator/prometheus")).andExpect(status().isOk());
	}
}
