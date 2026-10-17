package pw.pingu.ride_matching_springboot.ride.domain.model;

public enum RideStatus {
	MATCHING,
	OFFERED,
	DRIVER_EN_ROUTE,
	WAITING_AT_PICKUP,
	IN_PROGRESS,
	COMPLETED,
	CANCELLED
}
