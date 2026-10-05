/// One GPS sample used by the driver location pipeline.
///
/// Units match the server location contract in
/// `backend/auth-service/src/location/validation.ts`:
/// accuracy in meters, speed in kilometers per hour.
///
/// This type does not depend on a location plugin. The foreground source
/// converts plugin samples into this model before they reach the classifier.
class DriverLocationFix {
  const DriverLocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.speedKmh,
    required this.timestamp,
    this.headingDegrees,
    this.altitudeMeters,
  });

  final double latitude;
  final double longitude;

  /// Horizontal accuracy in meters. Negative and non-finite values are invalid.
  final double accuracyMeters;

  /// Speed in kilometers per hour. Negative and non-finite values are invalid.
  final double speedKmh;

  /// Degrees clockwise from north, when the platform provided one.
  final double? headingDegrees;

  /// Meters above the platform's altitude datum, when available.
  final double? altitudeMeters;

  final DateTime timestamp;

  /// Same instant and same coordinates as [other].
  ///
  /// Accuracy, speed, heading, and altitude are not part of the duplicate key.
  bool isDuplicateOf(DriverLocationFix other) {
    return timestamp.isAtSameMomentAs(other.timestamp) &&
        latitude == other.latitude &&
        longitude == other.longitude;
  }
}

/// Metres per second → kilometers per hour. No clamping.
double driverLocationSpeedKmhFromMetersPerSecond(double metersPerSecond) {
  return metersPerSecond * 3.6;
}

/// Platform heading. Negative means the plugin has no heading yet.
double? driverLocationHeadingDegrees(double heading) {
  if (!heading.isFinite || heading < 0) return null;
  return heading;
}

/// Platform altitude. Non-finite values are dropped.
double? driverLocationAltitudeMeters(double altitude) {
  if (!altitude.isFinite) return null;
  return altitude;
}
