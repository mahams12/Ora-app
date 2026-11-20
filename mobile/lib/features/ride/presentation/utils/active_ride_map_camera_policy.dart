import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Pure camera policy for MAP-2B active-ride map (not MAP-1).
///
/// Tick-stable: [fitIdentity] keys on phase + pickup/dest identity + driver
/// presence — never fine-grained driver lat/lng. Callers must NOT re-fit on
/// every RTDB location tick.
class ActiveRideMapCameraPolicy {
  ActiveRideMapCameraPolicy._();

  static const double closeSpanDegrees = 0.0008;
  static const double closePointsZoom = 15;
  static const double singlePointZoom = 14;

  /// Default padding for LatLngBounds fits (readable on ~200px map height).
  static const double defaultPadding = 48;

  /// Max lat/lng span (degrees) when optionally including a third anchor.
  /// ~0.08° ≈ 9 km — beyond this, stick to the phase-primary pair.
  static const double maxIncludeThirdSpanDegrees = 0.08;

  static const CameraPosition idleCamera = CameraPosition(
    target: LatLng(31.5204, 74.3587),
    zoom: 11,
  );

  static bool areExtremelyClose(LatLng a, LatLng b) {
    return (a.latitude - b.latitude).abs() < closeSpanDegrees &&
        (a.longitude - b.longitude).abs() < closeSpanDegrees;
  }

  static LatLng midpoint(LatLng a, LatLng b) {
    return LatLng(
      (a.latitude + b.latitude) / 2,
      (a.longitude + b.longitude) / 2,
    );
  }

  /// Camera phase derived from HTTP ride state (authoritative).
  static String anchorPhase(String rideState) {
    switch (rideState.toUpperCase()) {
      case 'RIDE_STARTED':
        return 'to_dest';
      case 'DRIVER_ASSIGNED':
      case 'DRIVER_EN_ROUTE':
      case 'DRIVER_ARRIVED':
        return 'to_pickup';
      default:
        return 'anchors';
    }
  }

  /// Stable identity for "should we refit?".
  ///
  /// Includes phase + rounded pickup/destination + driver presence only.
  /// Does NOT include driver lat/lng, heading, speed, accuracy, or locationSeq.
  static String fitIdentity({
    required String rideState,
    required LatLng? pickup,
    required LatLng? destination,
    required LatLng? driver,
  }) {
    final phase = anchorPhase(rideState);
    String fmt(LatLng? p) {
      if (p == null) return '-';
      return '${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)}';
    }

    final driverKey = driver != null ? 'driverPresent' : 'driverAbsent';
    return '$phase|${fmt(pickup)}|${fmt(destination)}|$driverKey';
  }

  /// Builds a camera update for the current active-ride geometry.
  ///
  /// Returns null when there is nothing to show.
  ///
  /// Composition:
  /// - no driver → pickup + destination
  /// - to_pickup + driver → driver + pickup (+ dest if span readable)
  /// - to_dest + driver → driver + destination (+ pickup if span readable)
  static CameraUpdate? cameraUpdate({
    required String rideState,
    required LatLng? pickup,
    required LatLng? destination,
    required LatLng? driver,
    double padding = defaultPadding,
  }) {
    if (driver != null) {
      final primary = _driverPrimaryAnchor(
        rideState: rideState,
        pickup: pickup,
        destination: destination,
      );
      if (primary == null) {
        return CameraUpdate.newLatLngZoom(driver, singlePointZoom);
      }

      final tertiary = _optionalThirdAnchor(
        rideState: rideState,
        pickup: pickup,
        destination: destination,
      );
      if (tertiary != null &&
          _tripleSpanReadable(driver, primary, tertiary)) {
        return _fitPoints(
          [driver, primary, tertiary],
          padding: padding,
        );
      }
      return _fitPair(driver, primary, padding: padding);
    }

    if (pickup != null && destination != null) {
      return _fitPair(pickup, destination, padding: padding);
    }
    if (pickup != null) {
      return CameraUpdate.newLatLngZoom(pickup, singlePointZoom);
    }
    if (destination != null) {
      return CameraUpdate.newLatLngZoom(destination, singlePointZoom);
    }
    return null;
  }

  /// Primary pair partner for a visible driver (phase-aware).
  static LatLng? _driverPrimaryAnchor({
    required String rideState,
    required LatLng? pickup,
    required LatLng? destination,
  }) {
    switch (anchorPhase(rideState)) {
      case 'to_dest':
        return destination ?? pickup;
      case 'to_pickup':
        return pickup ?? destination;
      default:
        return pickup ?? destination;
    }
  }

  /// Optional third point — never replaces the phase-primary pair.
  static LatLng? _optionalThirdAnchor({
    required String rideState,
    required LatLng? pickup,
    required LatLng? destination,
  }) {
    switch (anchorPhase(rideState)) {
      case 'to_pickup':
        return destination;
      case 'to_dest':
        return pickup;
      default:
        return null;
    }
  }

  static bool _tripleSpanReadable(LatLng a, LatLng b, LatLng c) {
    final lats = [a.latitude, b.latitude, c.latitude];
    final lngs = [a.longitude, b.longitude, c.longitude];
    final latSpan = lats.reduce((x, y) => x > y ? x : y) -
        lats.reduce((x, y) => x < y ? x : y);
    final lngSpan = lngs.reduce((x, y) => x > y ? x : y) -
        lngs.reduce((x, y) => x < y ? x : y);
    return latSpan <= maxIncludeThirdSpanDegrees &&
        lngSpan <= maxIncludeThirdSpanDegrees;
  }

  static CameraUpdate _fitPair(LatLng a, LatLng b, {required double padding}) {
    return _fitPoints([a, b], padding: padding);
  }

  static CameraUpdate _fitPoints(
    List<LatLng> points, {
    required double padding,
  }) {
    assert(points.isNotEmpty);
    if (points.length == 1) {
      return CameraUpdate.newLatLngZoom(points.first, singlePointZoom);
    }
    if (points.length == 2 && areExtremelyClose(points[0], points[1])) {
      return CameraUpdate.newLatLngZoom(
        midpoint(points[0], points[1]),
        closePointsZoom,
      );
    }

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final p in points.skip(1)) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    return CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      ),
      padding,
    );
  }
}
