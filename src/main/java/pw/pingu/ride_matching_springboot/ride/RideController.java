package pw.pingu.ride_matching_springboot.ride;

import java.util.List;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping
public class RideController {

	private final RideMatchingService rideMatchingService;

	public RideController(RideMatchingService rideMatchingService) {
		this.rideMatchingService = rideMatchingService;
	}

	@PutMapping("/drivers/me/availability")
	@PreAuthorize("hasRole('DRIVER')")
	public RideMatchingService.DriverView setAvailability(Authentication authentication,
			@Valid @RequestBody AvailabilityRequest request) {
		return rideMatchingService.setAvailability(authentication.getName(), request.available(), request.location().toLocation());
	}

	@PutMapping("/drivers/me/location")
	@PreAuthorize("hasRole('DRIVER')")
	public RideMatchingService.DriverView updateLocation(Authentication authentication, @Valid @RequestBody LocationRequest request) {
		return rideMatchingService.updateLocation(authentication.getName(), request.location().toLocation());
	}

	@GetMapping("/drivers/me")
	@PreAuthorize("hasRole('DRIVER')")
	public RideMatchingService.DriverView currentDriver(Authentication authentication) {
		return rideMatchingService.currentDriver(authentication.getName());
	}

	@GetMapping("/drivers/me/ride")
	@PreAuthorize("hasRole('DRIVER')")
	public ResponseEntity<RideMatchingService.DriverRideView> currentDriverRide(Authentication authentication) {
		return rideMatchingService.currentRideForDriver(authentication.getName())
				.map(ResponseEntity::ok)
				.orElseGet(() -> ResponseEntity.noContent().build());
	}

	@GetMapping("/riders/me/ride")
	@PreAuthorize("hasRole('RIDER')")
	public ResponseEntity<RideMatchingService.RiderRideView> currentRiderRide(Authentication authentication) {
		return rideMatchingService.currentRideForRider(authentication.getName())
				.map(ResponseEntity::ok)
				.orElseGet(() -> ResponseEntity.noContent().build());
	}

	@PostMapping("/rides")
	@PreAuthorize("hasRole('RIDER')")
	public ResponseEntity<RideMatchingService.RiderRideView> requestRide(Authentication authentication, @Valid @RequestBody RideRequest request) {
		return ResponseEntity.status(HttpStatus.CREATED)
				.body(rideMatchingService.requestRide(authentication.getName(), request.pickup().toLocation(), request.destination().toLocation()));
	}

	@PostMapping("/rides/{rideId}/accept")
	@PreAuthorize("hasRole('DRIVER')")
	public RideMatchingService.DriverRideView accept(Authentication authentication, @PathVariable UUID rideId) {
		return rideMatchingService.accept(authentication.getName(), rideId);
	}

	@PostMapping("/rides/{rideId}/decline")
	@PreAuthorize("hasRole('DRIVER')")
	public RideMatchingService.DriverRideView decline(Authentication authentication, @PathVariable UUID rideId) {
		return rideMatchingService.decline(authentication.getName(), rideId);
	}

	@PostMapping("/rides/{rideId}/arrive")
	@PreAuthorize("hasRole('DRIVER')")
	public RideMatchingService.DriverRideView arrive(Authentication authentication, @PathVariable UUID rideId) {
		return rideMatchingService.arrive(authentication.getName(), rideId);
	}

	@PostMapping("/rides/{rideId}/pickup")
	@PreAuthorize("hasRole('DRIVER')")
	public RideMatchingService.DriverRideView pickup(Authentication authentication, @PathVariable UUID rideId) {
		return rideMatchingService.pickup(authentication.getName(), rideId);
	}

	@PostMapping("/rides/{rideId}/complete")
	@PreAuthorize("hasRole('DRIVER')")
	public RideMatchingService.DriverRideView complete(Authentication authentication, @PathVariable UUID rideId) {
		return rideMatchingService.complete(authentication.getName(), rideId);
	}

	@PostMapping("/rides/{rideId}/cancel")
	@PreAuthorize("hasRole('DRIVER')")
	public RideMatchingService.DriverRideView cancel(Authentication authentication, @PathVariable UUID rideId) {
		return rideMatchingService.cancel(authentication.getName(), rideId);
	}

	@GetMapping("/drivers/available")
	@PreAuthorize("hasRole('ADMIN')")
	public List<RideMatchingService.NearbyDriver> availableDrivers(@RequestParam double latitude,
			@RequestParam double longitude, @RequestParam int limit) {
		return rideMatchingService.availableDrivers(new Location(latitude, longitude), limit);
	}

	public record AvailabilityRequest(@NotNull(message = "available is required") Boolean available,
			@NotNull(message = "location is required") @Valid LocationInput location) {
	}

	public record LocationRequest(@NotNull(message = "location is required") @Valid LocationInput location) {
	}

	public record RideRequest(@NotNull(message = "pickup is required") @Valid LocationInput pickup,
			@NotNull(message = "destination is required") @Valid LocationInput destination) {
	}

	public record LocationInput(@NotNull(message = "latitude is required") Double latitude,
			@NotNull(message = "longitude is required") Double longitude) {
		Location toLocation() {
			return new Location(latitude, longitude);
		}
	}

}
