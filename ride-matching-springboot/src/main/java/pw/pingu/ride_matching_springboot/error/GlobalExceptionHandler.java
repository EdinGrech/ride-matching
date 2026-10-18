package pw.pingu.ride_matching_springboot.error;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.authorization.AuthorizationDeniedException;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;

import pw.pingu.ride_matching_springboot.ride.domain.RideException;

@RestControllerAdvice
public class GlobalExceptionHandler {

	private static final Logger logger = LoggerFactory.getLogger(GlobalExceptionHandler.class);

	@ExceptionHandler(RideException.class)
	ResponseEntity<ApiError> rideException(RideException exception) {
		HttpStatus status = switch (exception) {
			case RideException.BadRequest ignored -> HttpStatus.BAD_REQUEST;
			case RideException.NotFound ignored -> HttpStatus.NOT_FOUND;
			case RideException.Forbidden ignored -> HttpStatus.FORBIDDEN;
			case RideException.Conflict ignored -> HttpStatus.CONFLICT;
			default -> HttpStatus.INTERNAL_SERVER_ERROR;
		};
		return error(status, exception.getMessage());
	}

	@ExceptionHandler(MethodArgumentNotValidException.class)
	ResponseEntity<ApiError> validation(MethodArgumentNotValidException exception) {
		String message = exception.getBindingResult().getFieldErrors().stream().findFirst()
				.map(FieldError::getDefaultMessage)
				.orElse("Invalid request");
		return error(HttpStatus.BAD_REQUEST, message);
	}

	@ExceptionHandler({HttpMessageNotReadableException.class, MissingServletRequestParameterException.class,
			MethodArgumentTypeMismatchException.class})
	ResponseEntity<ApiError> malformedRequest(Exception exception) {
		return error(HttpStatus.BAD_REQUEST, "Malformed request");
	}

	@ExceptionHandler(AuthorizationDeniedException.class)
	ResponseEntity<ApiError> accessDenied(AuthorizationDeniedException exception) {
		return error(HttpStatus.FORBIDDEN, "Access is denied");
	}

	@ExceptionHandler(Exception.class)
	ResponseEntity<ApiError> unexpected(Exception exception) {
		logger.error("Unhandled request error", exception);
		return error(HttpStatus.INTERNAL_SERVER_ERROR, "An unexpected error occurred");
	}

	private static ResponseEntity<ApiError> error(HttpStatus status, String message) {
		return ResponseEntity.status(status).body(new ApiError(message));
	}

}
