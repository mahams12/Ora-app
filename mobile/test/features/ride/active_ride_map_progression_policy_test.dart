import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ora/features/ride/presentation/utils/active_ride_map_progression_policy.dart';

void main() {
  const pickup = LatLng(31.52, 74.35);
  const destination = LatLng(31.51, 74.34);
  const driver = LatLng(31.525, 74.355);

  group('ActiveRideMapProgressionPolicy', () {
    test('1. to_pickup + driver → driver to pickup', () {
      final segs = ActiveRideMapProgressionPolicy.segments(
        rideState: 'DRIVER_ASSIGNED',
        pickup: pickup,
        destination: destination,
        driver: driver,
      );
      expect(segs, hasLength(1));
      expect(segs.single.kind, ActiveRideMapGuideKind.driverToPickup);
      expect(segs.single.start, driver);
      expect(segs.single.end, pickup);
    });

    test('2. to_pickup + no driver → pickup to destination fallback', () {
      final segs = ActiveRideMapProgressionPolicy.segments(
        rideState: 'DRIVER_EN_ROUTE',
        pickup: pickup,
        destination: destination,
        driver: null,
      );
      expect(segs, hasLength(1));
      expect(segs.single.kind, ActiveRideMapGuideKind.pickupToDestination);
      expect(segs.single.start, pickup);
      expect(segs.single.end, destination);
    });

    test('3. to_dest + driver → driver to destination', () {
      final segs = ActiveRideMapProgressionPolicy.segments(
        rideState: 'RIDE_STARTED',
        pickup: pickup,
        destination: destination,
        driver: driver,
      );
      expect(segs, hasLength(1));
      expect(segs.single.kind, ActiveRideMapGuideKind.driverToDestination);
      expect(segs.single.start, driver);
      expect(segs.single.end, destination);
    });

    test('4. to_dest + no driver → pickup to destination fallback', () {
      final segs = ActiveRideMapProgressionPolicy.segments(
        rideState: 'RIDE_STARTED',
        pickup: pickup,
        destination: destination,
        driver: null,
      );
      expect(segs, hasLength(1));
      expect(segs.single.kind, ActiveRideMapGuideKind.pickupToDestination);
    });

    test('5. expired/missing driver (null) omits driver endpoint', () {
      // Caller passes null when freshness says hide — policy never invents.
      final segs = ActiveRideMapProgressionPolicy.segments(
        rideState: 'DRIVER_ARRIVED',
        pickup: pickup,
        destination: destination,
        driver: null,
      );
      expect(
        segs.any((s) => s.kind == ActiveRideMapGuideKind.driverToPickup),
        isFalse,
      );
      expect(segs.single.kind, ActiveRideMapGuideKind.pickupToDestination);
    });

    test('6. missing pickup → empty when driver present (to_pickup)', () {
      final segs = ActiveRideMapProgressionPolicy.segments(
        rideState: 'DRIVER_ASSIGNED',
        pickup: null,
        destination: destination,
        driver: driver,
      );
      expect(segs, isEmpty);
    });

    test('7. missing destination → empty when driver present (to_dest)', () {
      final segs = ActiveRideMapProgressionPolicy.segments(
        rideState: 'RIDE_STARTED',
        pickup: pickup,
        destination: null,
        driver: driver,
      );
      expect(segs, isEmpty);
    });

    test('8. malformed coordinates omitted — no throw', () {
      expect(
        () => ActiveRideMapProgressionPolicy.segments(
          rideState: 'DRIVER_ASSIGNED',
          pickup: const LatLng(double.nan, 74.35),
          destination: destination,
          driver: driver,
        ),
        returnsNormally,
      );
      final nanPickup = ActiveRideMapProgressionPolicy.segments(
        rideState: 'DRIVER_ASSIGNED',
        pickup: const LatLng(double.nan, 74.35),
        destination: destination,
        driver: driver,
      );
      // Invalid pickup → no driver→pickup; anchors need valid pickup → empty.
      expect(nanPickup, isEmpty);

      final nanDriver = ActiveRideMapProgressionPolicy.segments(
        rideState: 'DRIVER_ASSIGNED',
        pickup: pickup,
        destination: destination,
        driver: const LatLng(double.nan, 74.35),
      );
      // Unusable driver → anchors fallback (pickup↔destination).
      expect(nanDriver.single.kind, ActiveRideMapGuideKind.pickupToDestination);

      final nanBothAnchors = ActiveRideMapProgressionPolicy.segments(
        rideState: 'DRIVER_ASSIGNED',
        pickup: const LatLng(double.nan, double.nan),
        destination: const LatLng(double.nan, double.nan),
        driver: null,
      );
      expect(nanBothAnchors, isEmpty);
    });

    test('9. driver coordinate changes → endpoint changes', () {
      final a = ActiveRideMapProgressionPolicy.segments(
        rideState: 'DRIVER_ASSIGNED',
        pickup: pickup,
        destination: destination,
        driver: driver,
      );
      const moved = LatLng(31.53, 74.36);
      final b = ActiveRideMapProgressionPolicy.segments(
        rideState: 'DRIVER_ASSIGNED',
        pickup: pickup,
        destination: destination,
        driver: moved,
      );
      expect(a.single.start, driver);
      expect(b.single.start, moved);
      expect(b.single.end, pickup);
      expect(a.single.start, isNot(b.single.start));
    });

    test('10. policy never creates ETA/duration/travel-time data', () {
      final segs = ActiveRideMapProgressionPolicy.segments(
        rideState: 'DRIVER_ASSIGNED',
        pickup: pickup,
        destination: destination,
        driver: driver,
      );
      final encoded = segs.toString();
      expect(encoded.toLowerCase(), isNot(contains('eta')));
      expect(encoded.toLowerCase(), isNot(contains('duration')));
      expect(encoded.toLowerCase(), isNot(contains('travel')));
      expect(segs.single.semanticsLabel.toLowerCase(), contains('not a road'));
      // Segment exposes only geometry + kind — no time fields on the type.
      expect(segs.single.runtimeType.toString(), 'ActiveRideMapGuideSegment');
    });

    test('EN_ROUTE and ARRIVED use to_pickup driver→pickup', () {
      for (final state in ['DRIVER_EN_ROUTE', 'DRIVER_ARRIVED']) {
        final segs = ActiveRideMapProgressionPolicy.segments(
          rideState: state,
          pickup: pickup,
          destination: destination,
          driver: driver,
        );
        expect(segs.single.kind, ActiveRideMapGuideKind.driverToPickup);
      }
    });
  });
}
