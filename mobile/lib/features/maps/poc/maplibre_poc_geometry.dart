import 'package:maplibre_gl/maplibre_gl.dart';

/// Fixed Lahore PoC geometry — DISPLAY-ONLY, not ride-authoritative.
///
/// Not connected to Google Routes, pricing, RTDB, or live driver publish.
class MapLibrePoCGeometry {
  MapLibrePoCGeometry._();

  /// Gulberg / Liberty corridor (Lahore) — not device GPS.
  static const LatLng lahoreCenter = LatLng(31.5128, 74.3452);

  static const CameraPosition initialCamera = CameraPosition(
    target: lahoreCenter,
    zoom: 15.4,
    tilt: 52,
    bearing: 28,
  );

  static const LatLng pickup = LatLng(31.5098, 74.3418);
  static const LatLng destination = LatLng(31.5206, 74.3512);
  static const LatLng driver = LatLng(31.5142, 74.3458);

  /// Heading degrees for driver icon rotation demo (fixed).
  static const double driverHeadingDeg = 42;

  /// DISPLAY-ONLY PoC route polyline (static sample geometry).
  static const List<LatLng> displayOnlyRoute = [
    LatLng(31.5098, 74.3418),
    LatLng(31.5106, 74.3432),
    LatLng(31.5118, 74.3445),
    LatLng(31.5130, 74.3455),
    LatLng(31.5142, 74.3458),
    LatLng(31.5156, 74.3466),
    LatLng(31.5170, 74.3478),
    LatLng(31.5184, 74.3490),
    LatLng(31.5196, 74.3502),
    LatLng(31.5206, 74.3512),
  ];

  /// Showcase camera after style+overlays ready.
  static const CameraPosition showcaseCamera = CameraPosition(
    target: LatLng(31.5145, 74.3455),
    zoom: 16.1,
    tilt: 58,
    bearing: 48,
  );

  /// Approved Ora map accent blue (route).
  static const String routeBlue = '#4FA3D9';
  static const String routeGlow = '#7CC8F5';
}
