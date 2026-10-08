import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Pure camera policy for MAP-1 — unit-testable without a map controller.
class RideMapCameraPolicy {
  RideMapCameraPolicy._();

  /// Degrees; ~90m at equator — below this, LatLngBounds is unreliable.
  static const double closeSpanDegrees = 0.0008;

  /// Fallback zoom when points are extremely close or identical.
  static const double closePointsZoom = 15;

  /// Default single-point zoom.
  static const double singlePointZoom = 14;

  /// Default idle camera (Lahore-ish) — never used as fake trip coordinates.
  static const CameraPosition idleCamera = CameraPosition(
    target: LatLng(31.5204, 74.3587),
    zoom: 11,
  );

  /// Whether pickup/destination are too close for a valid LatLngBounds fit.
  static bool areExtremelyClose(LatLng a, LatLng b) {
    return (a.latitude - b.latitude).abs() < closeSpanDegrees &&
        (a.longitude - b.longitude).abs() < closeSpanDegrees;
  }

  /// Midpoint for fallback zoom/center.
  static LatLng midpoint(LatLng a, LatLng b) {
    return LatLng(
      (a.latitude + b.latitude) / 2,
      (a.longitude + b.longitude) / 2,
    );
  }

  /// Builds the camera update for the current preview geometry.
  ///
  /// Returns null when there is nothing to show (caller keeps prior / idle).
  static CameraUpdate? cameraUpdate({
    required LatLng? pickup,
    required LatLng? destination,
    double padding = 56,
  }) {
    if (pickup != null && destination != null) {
      if (areExtremelyClose(pickup, destination)) {
        return CameraUpdate.newLatLngZoom(
          midpoint(pickup, destination),
          closePointsZoom,
        );
      }
      final southwest = LatLng(
        pickup.latitude < destination.latitude
            ? pickup.latitude
            : destination.latitude,
        pickup.longitude < destination.longitude
            ? pickup.longitude
            : destination.longitude,
      );
      final northeast = LatLng(
        pickup.latitude > destination.latitude
            ? pickup.latitude
            : destination.latitude,
        pickup.longitude > destination.longitude
            ? pickup.longitude
            : destination.longitude,
      );
      return CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: southwest, northeast: northeast),
        padding,
      );
    }
    if (pickup != null) {
      return CameraUpdate.newLatLngZoom(pickup, singlePointZoom);
    }
    if (destination != null) {
      return CameraUpdate.newLatLngZoom(destination, singlePointZoom);
    }
    return null;
  }
}
