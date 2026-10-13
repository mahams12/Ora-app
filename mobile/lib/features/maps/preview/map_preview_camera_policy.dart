import 'package:maplibre_gl/maplibre_gl.dart';

import 'map_preview_config.dart';

/// Pure camera policy for MapLibre ride preview — unit-testable.
class MapPreviewCameraPolicy {
  MapPreviewCameraPolicy._();

  /// Degrees; ~90m at equator — below this, LatLngBounds is unreliable.
  static const double closeSpanDegrees = 0.0008;

  static const double closePointsZoom = 15;
  static const double singlePointZoom = 14;

  static const CameraPosition idleCamera = CameraPosition(
    target: LatLng(31.5204, 74.3587),
    zoom: 11,
    tilt: MapPreviewConfig.flatTilt,
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

  /// Fits pickup/destination. Returns null when there is nothing to show.
  ///
  /// Note: [CameraUpdate.newLatLngBounds] resets tilt/bearing to 0 — caller
  /// re-applies 3D tilt after animate when needed.
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
        left: padding,
        top: padding,
        right: padding,
        bottom: padding,
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
