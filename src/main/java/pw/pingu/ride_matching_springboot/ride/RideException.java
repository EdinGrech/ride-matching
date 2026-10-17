package pw.pingu.ride_matching_springboot.ride;

public sealed class RideException extends RuntimeException permits RideException.BadRequest, RideException.NotFound, RideException.Forbidden, RideException.Conflict {

	private RideException(String message) {
		super(message);
	}

	public static final class BadRequest extends RideException {
		public BadRequest(String message) {
			super(message);
		}
	}

	public static final class NotFound extends RideException {
		public NotFound(String message) {
			super(message);
		}
	}

	public static final class Forbidden extends RideException {
		public Forbidden(String message) {
			super(message);
		}
	}

	public static final class Conflict extends RideException {
		public Conflict(String message) {
			super(message);
		}
	}

}
