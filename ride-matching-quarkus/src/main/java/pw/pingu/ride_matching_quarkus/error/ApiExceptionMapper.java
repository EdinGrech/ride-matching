package pw.pingu.ride_matching_quarkus.error;

import jakarta.validation.ConstraintViolationException;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.jboss.resteasy.reactive.server.ServerExceptionMapper;

import pw.pingu.ride_matching_quarkus.ride.domain.RideException;

public class ApiExceptionMapper {

    @ServerExceptionMapper
    Response rideException(RideException exception) {
        Response.Status status = switch (exception) {
            case RideException.BadRequest ignored -> Response.Status.BAD_REQUEST;
            case RideException.NotFound ignored -> Response.Status.NOT_FOUND;
            case RideException.Forbidden ignored -> Response.Status.FORBIDDEN;
            case RideException.Conflict ignored -> Response.Status.CONFLICT;
            default -> Response.Status.INTERNAL_SERVER_ERROR;
        };
        return error(status, exception.getMessage());
    }

    @ServerExceptionMapper
    Response validation(ConstraintViolationException exception) {
        String message = exception.getConstraintViolations().stream()
                .findFirst()
                .map(violation -> violation.getMessage())
                .orElse("Invalid request");
        return error(Response.Status.BAD_REQUEST, message);
    }

    private static Response error(Response.Status status, String message) {
        return Response.status(status).type(MediaType.APPLICATION_JSON).entity(new ApiError(message)).build();
    }
}
