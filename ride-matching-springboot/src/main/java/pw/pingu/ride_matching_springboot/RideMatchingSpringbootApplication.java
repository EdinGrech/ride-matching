package pw.pingu.ride_matching_springboot;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class RideMatchingSpringbootApplication {

	public static void main(String[] args) {
		SpringApplication.run(RideMatchingSpringbootApplication.class, args);
	}

}
