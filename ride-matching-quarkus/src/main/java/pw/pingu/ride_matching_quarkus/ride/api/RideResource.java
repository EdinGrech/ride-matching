package pw.pingu.ride_matching_quarkus.ride.api;

import java.util.List;
import java.util.UUID;

import jakarta.annotation.security.RolesAllowed;
import jakarta.inject.Inject;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import io.quarkus.security.identity.SecurityIdentity;

import pw.pingu.ride_matching_quarkus.ride.application.RideMatchingService;
import pw.pingu.ride_matching_quarkus.ride.domain.model.Location;

@Path("/")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class RideResource {

    private final RideMatchingService rideMatchingService;
    private final SecurityIdentity identity;

    @Inject
    RideResource(RideMatchingService rideMatchingService, SecurityIdentity identity) {
        this.rideMatchingService = rideMatchingService;
        this.identity = identity;
    }

    @PUT
    @Path("drivers/me/availability")
    @RolesAllowed("DRIVER")
    public RideMatchingService.DriverView setAvailability(@Valid AvailabilityRequest request) {
        return rideMatchingService.setAvailability(subject(), request.available(), request.location().toLocation());
    }

    @PUT
    @Path("drivers/me/location")
    @RolesAllowed("DRIVER")
    public RideMatchingService.DriverView updateLocation(@Valid LocationRequest request) {
        return rideMatchingService.updateLocation(subject(), request.location().toLocation());
    }

    @GET
    @Path("drivers/me")
    @RolesAllowed("DRIVER")
    public RideMatchingService.DriverView currentDriver() {
        return rideMatchingService.currentDriver(subject());
    }

    @GET
    @Path("drivers/me/state")
    @RolesAllowed("DRIVER")
    public RideMatchingService.DriverStateView currentDriverState() {
        return rideMatchingService.currentDriverState(subject());
    }

    @GET
    @Path("drivers/me/ride")
    @RolesAllowed("DRIVER")
    public Response currentDriverRide() {
        return rideMatchingService.currentRideForDriver(subject())
                .map(ride -> Response.ok(ride).build())
                .orElseGet(() -> Response.noContent().build());
    }

    @GET
    @Path("riders/me/ride")
    @RolesAllowed("RIDER")
    public Response currentRiderRide() {
        return rideMatchingService.currentRideForRider(subject())
                .map(ride -> Response.ok(ride).build())
                .orElseGet(() -> Response.noContent().build());
    }

    @DELETE
    @Path("riders/me/ride")
    @RolesAllowed("RIDER")
    public RideMatchingService.RiderRideView cancelCurrentRiderRide() {
        return rideMatchingService.cancelRideForRider(subject());
    }

    @POST
    @Path("rides")
    @RolesAllowed("RIDER")
    public Response requestRide(@Valid RideRequest request) {
        return Response.status(Response.Status.CREATED)
                .entity(rideMatchingService.requestRide(subject(), request.pickup().toLocation(), request.destination().toLocation()))
                .build();
    }

    @POST
    @Path("rides/{rideId}/accept")
    @RolesAllowed("DRIVER")
    public RideMatchingService.DriverRideView accept(@PathParam("rideId") UUID rideId) {
        return rideMatchingService.accept(subject(), rideId);
    }

    @POST
    @Path("rides/{rideId}/decline")
    @RolesAllowed("DRIVER")
    public RideMatchingService.DriverRideView decline(@PathParam("rideId") UUID rideId) {
        return rideMatchingService.decline(subject(), rideId);
    }

    @POST
    @Path("rides/{rideId}/arrive")
    @RolesAllowed("DRIVER")
    public RideMatchingService.DriverRideView arrive(@PathParam("rideId") UUID rideId) {
        return rideMatchingService.arrive(subject(), rideId);
    }

    @POST
    @Path("rides/{rideId}/pickup")
    @RolesAllowed("DRIVER")
    public RideMatchingService.DriverRideView pickup(@PathParam("rideId") UUID rideId) {
        return rideMatchingService.pickup(subject(), rideId);
    }

    @POST
    @Path("rides/{rideId}/complete")
    @RolesAllowed("DRIVER")
    public RideMatchingService.DriverRideView complete(@PathParam("rideId") UUID rideId) {
        return rideMatchingService.complete(subject(), rideId);
    }

    @POST
    @Path("rides/{rideId}/cancel")
    @RolesAllowed("DRIVER")
    public RideMatchingService.DriverRideView cancel(@PathParam("rideId") UUID rideId) {
        return rideMatchingService.cancel(subject(), rideId);
    }

    @GET
    @Path("drivers/available")
    @RolesAllowed("ADMIN")
    public List<RideMatchingService.NearbyDriver> availableDrivers(
            @QueryParam("latitude") @NotNull(message = "latitude is required") Double latitude,
            @QueryParam("longitude") @NotNull(message = "longitude is required") Double longitude,
            @QueryParam("limit") @NotNull(message = "limit is required") @Min(value = 1, message = "limit must be positive") Integer limit) {
        return rideMatchingService.availableDrivers(new Location(latitude, longitude), limit);
    }

    private String subject() {
        return identity.getPrincipal().getName();
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
