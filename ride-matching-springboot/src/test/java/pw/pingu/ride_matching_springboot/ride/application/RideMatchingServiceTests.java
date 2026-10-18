package pw.pingu.ride_matching_springboot.ride.application;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import org.junit.jupiter.api.Test;

import pw.pingu.ride_matching_springboot.ride.domain.RideException;
import pw.pingu.ride_matching_springboot.ride.domain.model.DriverStatus;
import pw.pingu.ride_matching_springboot.ride.domain.model.Location;
import pw.pingu.ride_matching_springboot.ride.domain.model.RideStatus;

class RideMatchingServiceTests {

	@Test
	void offersNearestDriverThenAcceptsWithoutExposingDestination() {
		RideMatchingService service = service();
		Location pickup = new Location(51.5, -0.12);
		Location destination = new Location(51.51, -0.11);
		service.setAvailability("far", true, new Location(51.5005, -0.12));
		service.setAvailability("near", true, new Location(51.5001, -0.12));

		RideMatchingService.RiderRideView ride = service.requestRide("rider", pickup, destination);

		assertEquals(RideStatus.OFFERED, ride.status());
		assertEquals("near", ride.driver().id());
		RideMatchingService.DriverRideView offered = service.currentRideForDriver("near").orElseThrow();
		assertNull(offered.destination());
		assertEquals(RideStatus.DRIVER_EN_ROUTE, service.accept("near", ride.id()).status());
	}

	@Test
	void declineAndOfferTimeoutRematchWithoutPenaltyOrRetryingDriver() {
		MutableClock clock = new MutableClock(Instant.parse("2026-01-01T00:00:00Z"));
		RideMatchingService service = service(clock);
		Location pickup = new Location(51.5, -0.12);
		service.setAvailability("first", true, pickup);
		service.setAvailability("second", true, new Location(51.5001, -0.12));
		service.setAvailability("third", true, new Location(51.5002, -0.12));
		RideMatchingService.RiderRideView ride = service.requestRide("rider", pickup, new Location(51.51, -0.11));

		service.decline("first", ride.id());
		assertEquals("second", service.currentRideForRider("rider").orElseThrow().driver().id());
		assertEquals(DriverStatus.AVAILABLE, service.currentDriver("first").status());
		clock.advance(Duration.ofSeconds(30));

		assertEquals("third", service.currentRideForRider("rider").orElseThrow().driver().id());
		assertEquals(DriverStatus.AVAILABLE, service.currentDriver("second").status());
	}

	@Test
	void unavailableRideStaysMatchingAndAvailabilityOffersIt() {
		RideMatchingService service = service();
		Location pickup = new Location(51.5, -0.12);
		RideMatchingService.RiderRideView ride = service.requestRide("rider", pickup, new Location(51.51, -0.11));

		assertEquals(RideStatus.MATCHING, ride.status());
		assertNull(ride.driver());
		assertEquals(DriverStatus.OFFERED, service.setAvailability("driver", true, pickup).status());
		assertEquals(RideStatus.OFFERED, service.currentRideForRider("rider").orElseThrow().status());
	}

	@Test
	void riderCancellationReleasesDriverWithoutRematchingWaitingRide() {
		RideMatchingService service = service();
		Location pickup = new Location(51.5, -0.12);
		assertNull(service.currentDriverState("new-driver").driver());
		service.setAvailability("driver", true, pickup);
		service.requestRide("first-rider", pickup, new Location(51.51, -0.11));
		RideMatchingService.RiderRideView waitingRide = service.requestRide("second-rider", pickup, new Location(51.51, -0.11));

		assertEquals(RideStatus.CANCELLED, service.cancelRideForRider("first-rider").status());
		assertFalse(service.currentRideForRider("first-rider").isPresent());
		assertEquals(DriverStatus.AVAILABLE, service.currentDriver("driver").status());
		assertEquals(RideStatus.MATCHING, service.currentRideForRider("second-rider").orElseThrow().status());
		assertNull(service.currentRideForRider("second-rider").orElseThrow().driver());
		assertFalse(service.currentRideForDriver("driver").isPresent());
		assertEquals(waitingRide.id(), service.currentRideForRider("second-rider").orElseThrow().id());
	}

	@Test
	void arrivalRequiresRadiusButNoStationaryDelayAndPickupRevealsDestination() {
		RideMatchingService service = service();
		Location pickup = new Location(51.5, -0.12);
		Location destination = new Location(51.51, -0.11);
		service.setAvailability("driver", true, new Location(51.501, -0.12));
		RideMatchingService.RiderRideView ride = service.requestRide("rider", pickup, destination);
		service.accept("driver", ride.id());

		assertThrows(RideException.Conflict.class, () -> service.arrive("driver", ride.id()));
		service.updateLocation("driver", pickup);
		assertEquals(RideStatus.WAITING_AT_PICKUP, service.arrive("driver", ride.id()).status());
		assertEquals(destination, service.pickup("driver", ride.id()).destination());
		assertEquals(RideStatus.COMPLETED, service.complete("driver", ride.id()).status());
	}

	@Test
	void prePickupCancellationPenalizesDriverAndRematchesSameRide() {
		RideMatchingService service = service();
		Location pickup = new Location(51.5, -0.12);
		service.setAvailability("first", true, pickup);
		service.setAvailability("second", true, new Location(51.5001, -0.12));
		RideMatchingService.RiderRideView ride = service.requestRide("rider", pickup, new Location(51.51, -0.11));
		service.accept("first", ride.id());

		service.cancel("first", ride.id());

		RideMatchingService.RiderRideView rematched = service.currentRideForRider("rider").orElseThrow();
		assertEquals(ride.id(), rematched.id());
		assertEquals("second", rematched.driver().id());
		assertEquals(DriverStatus.PENALIZED, service.currentDriver("first").status());
	}

	@Test
	void emergencyCancellationCreatesSuccessorFromLastDriverLocation() {
		RideMatchingService service = service();
		Location pickup = new Location(51.5, -0.12);
		Location lastLocation = new Location(51.505, -0.115);
		Location destination = new Location(51.51, -0.11);
		service.setAvailability("first", true, pickup);
		RideMatchingService.RiderRideView original = service.requestRide("rider", pickup, destination);
		service.accept("first", original.id());
		service.arrive("first", original.id());
		service.pickup("first", original.id());
		service.updateLocation("first", lastLocation);

		RideMatchingService.DriverRideView cancelled = service.cancel("first", original.id());

		RideMatchingService.RiderRideView successor = service.currentRideForRider("rider").orElseThrow();
		assertEquals(RideStatus.CANCELLED, cancelled.status());
		assertEquals(RideStatus.MATCHING, successor.status());
		assertEquals(lastLocation, successor.pickup());
		assertEquals(destination, successor.destination());
		assertEquals(DriverStatus.PENALIZED, service.currentDriver("first").status());
	}

	@Test
	void driverCannotOperateAnotherDriversRide() {
		RideMatchingService service = service();
		Location pickup = new Location(51.5, -0.12);
		service.setAvailability("driver", true, pickup);
		service.setAvailability("other", false, pickup);
		RideMatchingService.RiderRideView ride = service.requestRide("rider", pickup, new Location(51.51, -0.11));

		assertThrows(RideException.Forbidden.class, () -> service.accept("other", ride.id()));
	}

	@Test
	void concurrentAcceptsAssignAnOfferedRideOnce() throws Exception {
		RideMatchingService service = service();
		Location pickup = new Location(51.5, -0.12);
		service.setAvailability("driver", true, pickup);
		RideMatchingService.RiderRideView ride = service.requestRide("rider", pickup, new Location(51.51, -0.11));
		CountDownLatch start = new CountDownLatch(1);
		ExecutorService executor = Executors.newFixedThreadPool(2);
		try {
			Future<Boolean> first = executor.submit(() -> acceptWhenStarted(service, "driver", ride.id(), start));
			Future<Boolean> second = executor.submit(() -> acceptWhenStarted(service, "driver", ride.id(), start));
			start.countDown();

			assertTrue(first.get(5, TimeUnit.SECONDS) ^ second.get(5, TimeUnit.SECONDS));
		} finally {
			executor.shutdownNow();
		}
		assertEquals(RideStatus.DRIVER_EN_ROUTE, service.currentRideForRider("rider").orElseThrow().status());
		assertEquals(DriverStatus.DRIVING_TO_PICKUP, service.currentDriver("driver").status());
	}

	private static boolean acceptWhenStarted(RideMatchingService service, String driverId, java.util.UUID rideId, CountDownLatch start) throws InterruptedException {
		start.await();
		try {
			service.accept(driverId, rideId);
			return true;
		} catch (RideException.Conflict exception) {
			return false;
		}
	}

	private static RideMatchingService service() {
		return service(Clock.systemUTC());
	}

	private static RideMatchingService service(Clock clock) {
		return new RideMatchingService(clock, 50, Duration.ofSeconds(30), Duration.ofMinutes(30));
	}

	private static final class MutableClock extends Clock {
		private Instant instant;

		private MutableClock(Instant instant) {
			this.instant = instant;
		}

		void advance(Duration duration) {
			instant = instant.plus(duration);
		}

		@Override
		public ZoneOffset getZone() {
			return ZoneOffset.UTC;
		}

		@Override
		public Clock withZone(java.time.ZoneId zone) {
			return this;
		}

		@Override
		public Instant instant() {
			return instant;
		}
	}

}
