package pw.pingu.ride_matching_quarkus.ride.domain.model;

import pw.pingu.ride_matching_quarkus.ride.domain.RideException;

public record Location(double latitude, double longitude) {

    private static final double METRES_PER_LATITUDE_DEGREE = 111_320;

    public Location {
        if (!Double.isFinite(latitude) || latitude < -90 || latitude > 90
                || !Double.isFinite(longitude) || longitude < -180 || longitude > 180) {
            throw new RideException.BadRequest("latitude must be between -90 and 90 and longitude between -180 and 180");
        }
    }

    public double distanceMetresTo(Location other) {
        double latitudeMetres = (latitude - other.latitude) * METRES_PER_LATITUDE_DEGREE;
        double longitudeMetres = (longitude - other.longitude) * METRES_PER_LATITUDE_DEGREE
                * Math.cos(Math.toRadians((latitude + other.latitude) / 2));
        return Math.hypot(latitudeMetres, longitudeMetres);
    }
}
