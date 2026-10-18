package pw.pingu.ride_matching_quarkus.ride.application;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import com.fasterxml.jackson.annotation.JsonInclude;
import io.quarkus.scheduler.Scheduled;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import org.eclipse.microprofile.config.inject.ConfigProperty;

import pw.pingu.ride_matching_quarkus.ride.domain.RideException;
import pw.pingu.ride_matching_quarkus.ride.domain.model.DriverStatus;
import pw.pingu.ride_matching_quarkus.ride.domain.model.Location;
import pw.pingu.ride_matching_quarkus.ride.domain.model.RideStatus;

@ApplicationScoped
public class RideMatchingService {

    private final Map<String, Driver> drivers = new HashMap<>();
    private final Map<UUID, Ride> rides = new HashMap<>();
    private final Clock clock;
    private final double pickupRadiusMetres;
    private final Duration offerTimeout;
    private final Duration penaltyDuration;

    @Inject
    RideMatchingService(@ConfigProperty(name = "ride.gps.pickup-radius-metres", defaultValue = "50") double pickupRadiusMetres,
            @ConfigProperty(name = "ride.offer-timeout", defaultValue = "30s") Duration offerTimeout,
            @ConfigProperty(name = "ride.penalty-duration", defaultValue = "30m") Duration penaltyDuration) {
        this(Clock.systemUTC(), pickupRadiusMetres, offerTimeout, penaltyDuration);
    }

    RideMatchingService(Clock clock, double pickupRadiusMetres, Duration offerTimeout, Duration penaltyDuration) {
        this.clock = clock;
        this.pickupRadiusMetres = pickupRadiusMetres;
        this.offerTimeout = offerTimeout;
        this.penaltyDuration = penaltyDuration;
    }

    public synchronized DriverView setAvailability(String driverId, boolean available, Location location) {
        Instant now = clock.instant();
        expire(now);
        requireId(driverId, "driver ID");
        requireLocation(location);
        Driver driver = drivers.get(driverId);
        if (driver == null) {
            driver = new Driver(driverId, location, available ? DriverStatus.AVAILABLE : DriverStatus.OFFLINE);
            drivers.put(driverId, driver);
        } else {
            if (driver.status == DriverStatus.PENALIZED) {
                throw new RideException.Conflict("driver is penalized until " + driver.penaltyEndsAt);
            }
            if (isBusy(driver.status)) {
                throw new RideException.Conflict("an active driver must finish or cancel the ride before changing availability");
            }
            driver.location = location;
            driver.status = available ? DriverStatus.AVAILABLE : DriverStatus.OFFLINE;
        }
        if (available) {
            matchPendingRides(now);
        }
        return view(driver);
    }

    public synchronized DriverView updateLocation(String driverId, Location location) {
        expire(clock.instant());
        requireLocation(location);
        Driver driver = driver(driverId);
        driver.location = location;
        return view(driver);
    }

    @Scheduled(every = "1s")
    synchronized void expireOffers() {
        expire(clock.instant());
    }

    public synchronized DriverView currentDriver(String driverId) {
        expire(clock.instant());
        return view(driver(driverId));
    }

    public synchronized DriverStateView currentDriverState(String driverId) {
        expire(clock.instant());
        Driver driver = drivers.get(driverId);
        if (driver == null) {
            return new DriverStateView(null, null);
        }
        Ride ride = driver.activeRideId == null ? null : rides.get(driver.activeRideId);
        return new DriverStateView(view(driver), ride != null && isActive(ride.status) ? driverView(ride) : null);
    }

    public synchronized RiderRideView requestRide(String riderId, Location pickup, Location destination) {
        Instant now = clock.instant();
        expire(now);
        requireId(riderId, "rider ID");
        requireLocation(pickup);
        requireLocation(destination);
        if (activeRideForRider(riderId).isPresent()) {
            throw new RideException.Conflict("rider already has an active ride");
        }
        Ride ride = new Ride(UUID.randomUUID(), riderId, pickup, destination, now);
        rides.put(ride.id, ride);
        offerNext(ride, now);
        return riderView(ride);
    }

    public synchronized Optional<RiderRideView> currentRideForRider(String riderId) {
        expire(clock.instant());
        requireId(riderId, "rider ID");
        return activeRideForRider(riderId).map(this::riderView);
    }

    public synchronized RiderRideView cancelRideForRider(String riderId) {
        expire(clock.instant());
        Ride ride = activeRideForRider(riderId).orElseThrow(() -> new RideException.NotFound("rider has no active ride"));
        if (ride.status != RideStatus.MATCHING && ride.status != RideStatus.OFFERED) {
            throw new RideException.Conflict("ride cannot be cancelled after driver acceptance");
        }
        if (ride.driverId != null) {
            Driver driver = drivers.get(ride.driverId);
            driver.activeRideId = null;
            driver.status = DriverStatus.AVAILABLE;
        }
        ride.driverId = null;
        ride.offerExpiresAt = null;
        ride.status = RideStatus.CANCELLED;
        return riderView(ride);
    }

    public synchronized Optional<DriverRideView> currentRideForDriver(String driverId) {
        expire(clock.instant());
        requireId(driverId, "driver ID");
        Driver driver = drivers.get(driverId);
        if (driver == null || driver.activeRideId == null) {
            return Optional.empty();
        }
        Ride ride = rides.get(driver.activeRideId);
        return ride != null && isActive(ride.status) ? Optional.of(driverView(ride)) : Optional.empty();
    }

    public synchronized DriverRideView accept(String driverId, UUID rideId) {
        expire(clock.instant());
        Driver driver = driver(driverId);
        Ride ride = assignedRide(driver, rideId);
        if (ride.status != RideStatus.OFFERED || driver.status != DriverStatus.OFFERED) {
            throw new RideException.Conflict("ride is not offered to driver");
        }
        ride.status = RideStatus.DRIVER_EN_ROUTE;
        ride.offerExpiresAt = null;
        driver.status = DriverStatus.DRIVING_TO_PICKUP;
        return driverView(ride);
    }

    public synchronized DriverRideView decline(String driverId, UUID rideId) {
        Instant now = clock.instant();
        expire(now);
        Driver driver = driver(driverId);
        Ride ride = assignedRide(driver, rideId);
        if (ride.status != RideStatus.OFFERED || driver.status != DriverStatus.OFFERED) {
            throw new RideException.Conflict("ride is not offered to driver");
        }
        withdrawOffer(ride, driver);
        offerNext(ride, now);
        return driverView(ride);
    }

    public synchronized DriverRideView arrive(String driverId, UUID rideId) {
        expire(clock.instant());
        Driver driver = driver(driverId);
        Ride ride = assignedRide(driver, rideId);
        if (ride.status != RideStatus.DRIVER_EN_ROUTE || driver.status != DriverStatus.DRIVING_TO_PICKUP) {
            throw new RideException.Conflict("ride is not en route to pickup");
        }
        if (driver.location.distanceMetresTo(ride.pickup) > pickupRadiusMetres) {
            throw new RideException.Conflict("driver is not within the pickup radius");
        }
        ride.status = RideStatus.WAITING_AT_PICKUP;
        driver.status = DriverStatus.WAITING_AT_PICKUP;
        return driverView(ride);
    }

    public synchronized DriverRideView pickup(String driverId, UUID rideId) {
        expire(clock.instant());
        Driver driver = driver(driverId);
        Ride ride = assignedRide(driver, rideId);
        if (ride.status != RideStatus.WAITING_AT_PICKUP || driver.status != DriverStatus.WAITING_AT_PICKUP) {
            throw new RideException.Conflict("ride is not waiting at pickup");
        }
        ride.status = RideStatus.IN_PROGRESS;
        ride.destinationRevealed = true;
        driver.status = DriverStatus.DRIVING_TO_DESTINATION;
        return driverView(ride);
    }

    public synchronized DriverRideView complete(String driverId, UUID rideId) {
        expire(clock.instant());
        Driver driver = driver(driverId);
        Ride ride = assignedRide(driver, rideId);
        if (ride.status != RideStatus.IN_PROGRESS || driver.status != DriverStatus.DRIVING_TO_DESTINATION) {
            throw new RideException.Conflict("ride is not in progress");
        }
        ride.status = RideStatus.COMPLETED;
        driver.status = DriverStatus.AVAILABLE;
        driver.activeRideId = null;
        matchPendingRides(clock.instant());
        return driverView(ride);
    }

    public synchronized DriverRideView cancel(String driverId, UUID rideId) {
        Instant now = clock.instant();
        expire(now);
        Driver driver = driver(driverId);
        Ride ride = assignedRide(driver, rideId);
        if (ride.status != RideStatus.DRIVER_EN_ROUTE && ride.status != RideStatus.WAITING_AT_PICKUP
                && ride.status != RideStatus.IN_PROGRESS) {
            throw new RideException.Conflict("ride cannot be cancelled in its current state");
        }
        penalize(driver, now);
        if (ride.status == RideStatus.IN_PROGRESS) {
            ride.status = RideStatus.CANCELLED;
            Ride successor = new Ride(UUID.randomUUID(), ride.riderId, driver.location, ride.destination, now);
            successor.excludedDriverIds.add(driver.id);
            rides.put(successor.id, successor);
            offerNext(successor, now);
        } else {
            ride.excludedDriverIds.add(driver.id);
            ride.driverId = null;
            ride.status = RideStatus.MATCHING;
            offerNext(ride, now);
        }
        return driverView(ride);
    }

    public synchronized List<NearbyDriver> availableDrivers(Location location, int limit) {
        expire(clock.instant());
        requireLocation(location);
        if (limit < 1) {
            throw new RideException.BadRequest("limit must be positive");
        }
        return drivers.values().stream()
                .filter(driver -> driver.status == DriverStatus.AVAILABLE)
                .map(driver -> new NearbyDriver(view(driver), driver.location.distanceMetresTo(location)))
                .sorted(Comparator.comparingDouble(NearbyDriver::distanceMetres).thenComparing(nearby -> nearby.driver().id()))
                .limit(limit)
                .toList();
    }

    private void expire(Instant now) {
        drivers.values().stream()
                .filter(driver -> driver.status == DriverStatus.PENALIZED && !now.isBefore(driver.penaltyEndsAt))
                .forEach(driver -> {
                    driver.status = DriverStatus.OFFLINE;
                    driver.penaltyEndsAt = null;
                });
        rides.values().stream()
                .filter(ride -> ride.status == RideStatus.OFFERED && !now.isBefore(ride.offerExpiresAt))
                .toList()
                .forEach(ride -> {
                    Driver driver = drivers.get(ride.driverId);
                    withdrawOffer(ride, driver);
                    offerNext(ride, now);
                });
    }

    private void matchPendingRides(Instant now) {
        rides.values().stream()
                .filter(ride -> ride.status == RideStatus.MATCHING)
                .sorted(Comparator.comparing(ride -> ride.createdAt))
                .forEach(ride -> offerNext(ride, now));
    }

    private void offerNext(Ride ride, Instant now) {
        if (ride.status != RideStatus.MATCHING) {
            return;
        }
        Driver driver = drivers.values().stream()
                .filter(candidate -> candidate.status == DriverStatus.AVAILABLE && !ride.excludedDriverIds.contains(candidate.id))
                .min(Comparator.comparingDouble((Driver candidate) -> candidate.location.distanceMetresTo(ride.pickup))
                        .thenComparing(candidate -> candidate.id))
                .orElse(null);
        if (driver == null) {
            return;
        }
        ride.driverId = driver.id;
        ride.status = RideStatus.OFFERED;
        ride.offerExpiresAt = now.plus(offerTimeout);
        driver.activeRideId = ride.id;
        driver.status = DriverStatus.OFFERED;
    }

    private void withdrawOffer(Ride ride, Driver driver) {
        ride.excludedDriverIds.add(driver.id);
        ride.driverId = null;
        ride.offerExpiresAt = null;
        ride.status = RideStatus.MATCHING;
        driver.activeRideId = null;
        driver.status = DriverStatus.AVAILABLE;
    }

    private void penalize(Driver driver, Instant now) {
        driver.status = DriverStatus.PENALIZED;
        driver.penaltyEndsAt = now.plus(penaltyDuration);
        driver.activeRideId = null;
    }

    private Driver driver(String driverId) {
        requireId(driverId, "driver ID");
        Driver driver = drivers.get(driverId);
        if (driver == null) {
            throw new RideException.NotFound("driver not found");
        }
        return driver;
    }

    private Ride assignedRide(Driver driver, UUID rideId) {
        Ride ride = ride(rideId);
        if (!Objects.equals(ride.driverId, driver.id) || !Objects.equals(driver.activeRideId, rideId)) {
            throw new RideException.Forbidden("ride is not assigned to driver");
        }
        return ride;
    }

    private Optional<Ride> activeRideForRider(String riderId) {
        return rides.values().stream()
                .filter(ride -> ride.riderId.equals(riderId) && isActive(ride.status))
                .findFirst();
    }

    private Ride ride(UUID rideId) {
        Ride ride = rides.get(rideId);
        if (ride == null) {
            throw new RideException.NotFound("ride not found");
        }
        return ride;
    }

    private static boolean isBusy(DriverStatus status) {
        return status == DriverStatus.OFFERED || status == DriverStatus.DRIVING_TO_PICKUP
                || status == DriverStatus.WAITING_AT_PICKUP || status == DriverStatus.DRIVING_TO_DESTINATION;
    }

    private static boolean isActive(RideStatus status) {
        return status == RideStatus.MATCHING || status == RideStatus.OFFERED || status == RideStatus.DRIVER_EN_ROUTE
                || status == RideStatus.WAITING_AT_PICKUP || status == RideStatus.IN_PROGRESS;
    }

    private static void requireId(String id, String label) {
        if (id == null || id.isBlank()) {
            throw new RideException.BadRequest(label + " is required");
        }
    }

    private static void requireLocation(Location location) {
        if (location == null) {
            throw new RideException.BadRequest("location is required");
        }
    }

    private static DriverView view(Driver driver) {
        return new DriverView(driver.id, driver.location, driver.status);
    }

    private DriverRideView driverView(Ride ride) {
        return new DriverRideView(ride.id, ride.pickup, ride.destinationRevealed ? ride.destination : null, ride.status);
    }

    private RiderRideView riderView(Ride ride) {
        return new RiderRideView(ride.id, ride.pickup, ride.destination, ride.status,
                ride.driverId == null ? null : view(driver(ride.driverId)));
    }

    public record DriverView(String id, Location location, DriverStatus status) {
    }

    public record DriverStateView(DriverView driver, DriverRideView ride) {
    }

    @JsonInclude(JsonInclude.Include.NON_NULL)
    public record DriverRideView(UUID id, Location pickup, Location destination, RideStatus status) {
    }

    @JsonInclude(JsonInclude.Include.NON_NULL)
    public record RiderRideView(UUID id, Location pickup, Location destination, RideStatus status, DriverView driver) {
    }

    public record NearbyDriver(DriverView driver, double distanceMetres) {
    }

    private static final class Driver {
        private final String id;
        private Location location;
        private DriverStatus status;
        private UUID activeRideId;
        private Instant penaltyEndsAt;

        private Driver(String id, Location location, DriverStatus status) {
            this.id = id;
            this.location = location;
            this.status = status;
        }
    }

    private static final class Ride {
        private final UUID id;
        private final String riderId;
        private final Location pickup;
        private final Location destination;
        private final Instant createdAt;
        private final Set<String> excludedDriverIds = new HashSet<>();
        private String driverId;
        private RideStatus status = RideStatus.MATCHING;
        private Instant offerExpiresAt;
        private boolean destinationRevealed;

        private Ride(UUID id, String riderId, Location pickup, Location destination, Instant createdAt) {
            this.id = id;
            this.riderId = riderId;
            this.pickup = pickup;
            this.destination = destination;
            this.createdAt = createdAt;
        }
    }
}
