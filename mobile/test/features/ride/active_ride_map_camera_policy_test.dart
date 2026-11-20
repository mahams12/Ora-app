import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ora/features/ride/presentation/utils/active_ride_map_camera_policy.dart';

void main() {
  const pickup = LatLng(31.52, 74.35);
  const destination = LatLng(31.51, 74.34);
  const driver = LatLng(31.525, 74.355);
  const driverMoved = LatLng(31.530, 74.360);
  const driverMovedFar = LatLng(31.540, 74.370);

  group('ActiveRideMapCameraPolicy — tick-stable identity', () {
    test('same phase + driver moves → identity identical', () {
      final a = ActiveRideMapCameraPolicy.fitIdentity(
        rideState: 'DRIVER_EN_ROUTE',
        pickup: pickup,
        destination: destination,
        driver: driver,
      );
      final b = ActiveRideMapCameraPolicy.fitIdentity(
        rideState: 'DRIVER_EN_ROUTE',
        pickup: pickup,
        destination: destination,
        driver: driverMoved,
      );
      final c = ActiveRideMapCameraPolicy.fitIdentity(
        rideState: 'DRIVER_EN_ROUTE',
        pickup: pickup,
        destination: destination,
        driver: driverMovedFar,
      );
      expect(a, b);
      expect(b, c);
      expect(a.contains('driverPresent'), isTrue);
      expect(a.contains('31.525'), isFalse);
    });

    test('driver first appears → identity changes', () {
      final before = ActiveRideMapCameraPolicy.fitIdentity(
        rideState: 'DRIVER_ASSIGNED',
        pickup: pickup,
        destination: destination,
        driver: null,
      );
      final after = ActiveRideMapCameraPolicy.fitIdentity(
        rideState: 'DRIVER_ASSIGNED',
        pickup: pickup,
        destination: destination,
        driver: driver,
      );
      expect(before, isNot(after));
      expect(before.contains('driverAbsent'), isTrue);
      expect(after.contains('driverPresent'), isTrue);
    });

    test('driver disappears → identity changes', () {
      final withDriver = ActiveRideMapCameraPolicy.fitIdentity(
        rideState: 'DRIVER_ASSIGNED',
        pickup: pickup,
        destination: destination,
        driver: driver,
      );
      final without = ActiveRideMapCameraPolicy.fitIdentity(
        rideState: 'DRIVER_ASSIGNED',
        pickup: pickup,
        destination: destination,
        driver: null,
      );
      expect(withDriver, isNot(without));
    });

    test('RIDE_STARTED flips to_pickup → to_dest', () {
      final assigned = ActiveRideMapCameraPolicy.fitIdentity(
        rideState: 'DRIVER_ASSIGNED',
        pickup: pickup,
        destination: destination,
        driver: driver,
      );
      final started = ActiveRideMapCameraPolicy.fitIdentity(
        rideState: 'RIDE_STARTED',
        pickup: pickup,
        destination: destination,
        driver: driver,
      );
      expect(assigned.startsWith('to_pickup'), isTrue);
      expect(started.startsWith('to_dest'), isTrue);
      expect(assigned, isNot(started));
    });

    test('same phase + heading/speed/seq irrelevant — identity uses presence only', () {
      // Identity API does not take heading/speed/seq; moving driver alone is the proxy.
      final a = ActiveRideMapCameraPolicy.fitIdentity(
        rideState: 'DRIVER_ARRIVED',
        pickup: pickup,
        destination: destination,
        driver: driver,
      );
      final b = ActiveRideMapCameraPolicy.fitIdentity(
        rideState: 'DRIVER_ARRIVED',
        pickup: pickup,
        destination: destination,
        driver: LatLng(driver.latitude + 0.001, driver.longitude + 0.001),
      );
      expect(a, b);
    });

    test('expired/missing driver → anchors-only (null driver)', () {
      final expired = ActiveRideMapCameraPolicy.fitIdentity(
        rideState: 'DRIVER_EN_ROUTE',
        pickup: pickup,
        destination: destination,
        driver: null,
      );
      expect(expired.contains('driverAbsent'), isTrue);
      expect(expired.startsWith('to_pickup'), isTrue);
    });

    test('pickup change → identity changes', () {
      final a = ActiveRideMapCameraPolicy.fitIdentity(
        rideState: 'DRIVER_ASSIGNED',
        pickup: pickup,
        destination: destination,
        driver: driver,
      );
      final b = ActiveRideMapCameraPolicy.fitIdentity(
        rideState: 'DRIVER_ASSIGNED',
        pickup: const LatLng(31.53, 74.36),
        destination: destination,
        driver: driver,
      );
      expect(a, isNot(b));
    });

    test('destination change → identity changes', () {
      final a = ActiveRideMapCameraPolicy.fitIdentity(
        rideState: 'DRIVER_ASSIGNED',
        pickup: pickup,
        destination: destination,
        driver: driver,
      );
      final b = ActiveRideMapCameraPolicy.fitIdentity(
        rideState: 'DRIVER_ASSIGNED',
        pickup: pickup,
        destination: const LatLng(31.50, 74.33),
        driver: driver,
      );
      expect(a, isNot(b));
    });

    test('EN_ROUTE and ARRIVED share to_pickup phase', () {
      final enRoute = ActiveRideMapCameraPolicy.fitIdentity(
        rideState: 'DRIVER_EN_ROUTE',
        pickup: pickup,
        destination: destination,
        driver: driver,
      );
      final arrived = ActiveRideMapCameraPolicy.fitIdentity(
        rideState: 'DRIVER_ARRIVED',
        pickup: pickup,
        destination: destination,
        driver: driver,
      );
      expect(enRoute, arrived);
    });
  });

  group('ActiveRideMapCameraPolicy — composition', () {
    test('no driver → pickup+destination update', () {
      final update = ActiveRideMapCameraPolicy.cameraUpdate(
        rideState: 'DRIVER_ASSIGNED',
        pickup: pickup,
        destination: destination,
        driver: null,
      );
      expect(update, isNotNull);
    });

    test('to_pickup prefers driver+pickup (produces update)', () {
      expect(
        ActiveRideMapCameraPolicy.anchorPhase('DRIVER_EN_ROUTE'),
        'to_pickup',
      );
      final update = ActiveRideMapCameraPolicy.cameraUpdate(
        rideState: 'DRIVER_EN_ROUTE',
        pickup: pickup,
        destination: destination,
        driver: driver,
      );
      expect(update, isNotNull);
    });

    test('to_dest prefers driver+destination', () {
      expect(
        ActiveRideMapCameraPolicy.anchorPhase('RIDE_STARTED'),
        'to_dest',
      );
      final update = ActiveRideMapCameraPolicy.cameraUpdate(
        rideState: 'RIDE_STARTED',
        pickup: pickup,
        destination: destination,
        driver: driver,
      );
      expect(update, isNotNull);
    });

    test('close-point camera fallback', () {
      const a = LatLng(31.5200, 74.3587);
      const b = LatLng(31.52005, 74.35872);
      expect(ActiveRideMapCameraPolicy.areExtremelyClose(a, b), isTrue);
      final update = ActiveRideMapCameraPolicy.cameraUpdate(
        rideState: 'DRIVER_ASSIGNED',
        pickup: a,
        destination: b,
        driver: null,
      );
      expect(update, isNotNull);
    });

    test('no points returns null', () {
      expect(
        ActiveRideMapCameraPolicy.cameraUpdate(
          rideState: 'DRIVER_ASSIGNED',
          pickup: null,
          destination: null,
          driver: null,
        ),
        isNull,
      );
    });

    test('nearby triple may include third anchor without exploding', () {
      // Liberty–Gulberg scale — third point should be includable.
      final update = ActiveRideMapCameraPolicy.cameraUpdate(
        rideState: 'DRIVER_ASSIGNED',
        pickup: pickup,
        destination: destination,
        driver: driver,
      );
      expect(update, isNotNull);
    });
  });
}
