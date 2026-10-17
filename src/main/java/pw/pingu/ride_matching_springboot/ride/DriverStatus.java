package pw.pingu.ride_matching_springboot.ride;

public enum DriverStatus {
	AVAILABLE,
	OFFLINE,
	OFFERED,
	DRIVING_TO_PICKUP,
	WAITING_AT_PICKUP,
	DRIVING_TO_DESTINATION,
	PENALIZED
}
