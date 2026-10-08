/// Validated passenger-facing projection of RTDB `tripLocations/{rideId}/latest`.
///
/// Display-only. Never used as ride-state or fare authority.
class TripLocationLatest {
  const TripLocationLatest({
    required this.lat,
    required this.lng,
    required this.accuracy,
    required this.heading,
    required this.speed,
    required this.ts,
    required this.acceptedAt,
    required this.driverId,
    required this.locationSeq,
    required this.locationStreamId,
  });

  final double lat;
  final double lng;
  final double accuracy;
  final double heading;
  final double speed;

  /// Client fix timestamp (ms epoch), server-validated on write.
  final int ts;

  /// Server accept time (ISO-8601).
  final String acceptedAt;

  final String driverId;
  final int locationSeq;
  final String locationStreamId;

  bool get hasValidCoordinates =>
      lat.isFinite &&
      lng.isFinite &&
      lat >= -90 &&
      lat <= 90 &&
      lng >= -180 &&
      lng <= 180;

  /// Parses a RTDB map. Returns null for malformed / unusable payloads (never throws).
  static TripLocationLatest? tryParse(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map) return null;

    final map = <String, Object?>{};
    for (final entry in raw.entries) {
      map['${entry.key}'] = entry.value;
    }

    final lat = _asFiniteDouble(map['lat']);
    final lng = _asFiniteDouble(map['lng']);
    if (lat == null || lng == null) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;

    final accuracy = _asFiniteDouble(map['accuracy']);
    final heading = _asFiniteDouble(map['heading']);
    final speed = _asFiniteDouble(map['speed']);
    if (accuracy == null || heading == null || speed == null) return null;
    if (accuracy < 0) return null;

    final ts = _asPositiveInt(map['ts']);
    if (ts == null) return null;

    final acceptedAt = _asNonEmptyString(map['acceptedAt']);
    final driverId = _asNonEmptyString(map['driverId']);
    final locationStreamId = _asNonEmptyString(map['locationStreamId']);
    if (acceptedAt == null || driverId == null || locationStreamId == null) {
      return null;
    }
    // acceptedAt must be parseable ISO time (clock-safe handling elsewhere).
    if (DateTime.tryParse(acceptedAt) == null) return null;

    final locationSeq = _asPositiveInt(map['locationSeq']);
    if (locationSeq == null || locationSeq < 1) return null;

    return TripLocationLatest(
      lat: lat,
      lng: lng,
      accuracy: accuracy,
      heading: heading,
      speed: speed,
      ts: ts,
      acceptedAt: acceptedAt,
      driverId: driverId,
      locationSeq: locationSeq,
      locationStreamId: locationStreamId,
    );
  }

  static double? _asFiniteDouble(Object? value) {
    if (value is double) return value.isFinite ? value : null;
    if (value is int) return value.toDouble();
    if (value is num) {
      final d = value.toDouble();
      return d.isFinite ? d : null;
    }
    if (value is String) {
      final d = double.tryParse(value.trim());
      if (d == null || !d.isFinite) return null;
      return d;
    }
    return null;
  }

  static int? _asPositiveInt(Object? value) {
    if (value is int) return value;
    if (value is double) {
      if (!value.isFinite || value != value.roundToDouble()) return null;
      return value.toInt();
    }
    if (value is num) {
      final d = value.toDouble();
      if (!d.isFinite || d != d.roundToDouble()) return null;
      return d.toInt();
    }
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static String? _asNonEmptyString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
