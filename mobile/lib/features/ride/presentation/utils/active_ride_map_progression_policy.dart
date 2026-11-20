import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'active_ride_map_camera_policy.dart';

/// Kind of display-only progression guide segment (MAP-2C).
///
/// These are geometric guides — not road routes, navigation, or ETA.
enum ActiveRideMapGuideKind {
  /// Driver → pickup (to_pickup phase when driver is usable).
  driverToPickup,

  /// Driver → destination (to_dest / RIDE_STARTED when driver is usable).
  driverToDestination,

  /// Pickup → destination when no usable driver (waiting / expired).
  pickupToDestination,
}

/// One geometric guide segment between two trusted map points.
class ActiveRideMapGuideSegment {
  const ActiveRideMapGuideSegment({
    required this.kind,
    required this.start,
    required this.end,
  });

  final ActiveRideMapGuideKind kind;
  final LatLng start;
  final LatLng end;

  /// Accessibility / semantics — never implies road route or ETA.
  String get semanticsLabel {
    switch (kind) {
      case ActiveRideMapGuideKind.driverToPickup:
        return 'Guide line — not a road route. Driver to pickup.';
      case ActiveRideMapGuideKind.driverToDestination:
        return 'Guide line — not a road route. Driver to destination.';
      case ActiveRideMapGuideKind.pickupToDestination:
        return 'Guide line — not a road route. Pickup to destination.';
    }
  }
}

/// Pure MAP-2C progression policy — trusted points → display guide segments.
///
/// No controller, Firebase, networking, ETA, or road geometry.
/// Reuses [ActiveRideMapCameraPolicy.anchorPhase] for phase only.
class ActiveRideMapProgressionPolicy {
  ActiveRideMapProgressionPolicy._();

  /// Builds zero or one guide segment for the current active-ride geometry.
  ///
  /// [driver] must already be filtered by MAP-2A freshness (null when
  /// missing/expired). This policy never keeps phantom driver coordinates.
  static List<ActiveRideMapGuideSegment> segments({
    required String rideState,
    required LatLng? pickup,
    required LatLng? destination,
    required LatLng? driver,
  }) {
    final p = _sanitize(pickup);
    final d = _sanitize(destination);
    final drv = _sanitize(driver);
    final phase = ActiveRideMapCameraPolicy.anchorPhase(rideState);

    switch (phase) {
      case 'to_pickup':
        if (drv != null && p != null) {
          return [
            ActiveRideMapGuideSegment(
              kind: ActiveRideMapGuideKind.driverToPickup,
              start: drv,
              end: p,
            ),
          ];
        }
        return _anchorsOnly(p, d);
      case 'to_dest':
        if (drv != null && d != null) {
          return [
            ActiveRideMapGuideSegment(
              kind: ActiveRideMapGuideKind.driverToDestination,
              start: drv,
              end: d,
            ),
          ];
        }
        return _anchorsOnly(p, d);
      default:
        return _anchorsOnly(p, d);
    }
  }

  static List<ActiveRideMapGuideSegment> _anchorsOnly(
    LatLng? pickup,
    LatLng? destination,
  ) {
    if (pickup == null || destination == null) return const [];
    return [
      ActiveRideMapGuideSegment(
        kind: ActiveRideMapGuideKind.pickupToDestination,
        start: pickup,
        end: destination,
      ),
    ];
  }

  /// Rejects non-finite / out-of-range coordinates. Never throws.
  static LatLng? _sanitize(LatLng? point) {
    if (point == null) return null;
    final lat = point.latitude;
    final lng = point.longitude;
    if (!lat.isFinite || !lng.isFinite) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return point;
  }
}
