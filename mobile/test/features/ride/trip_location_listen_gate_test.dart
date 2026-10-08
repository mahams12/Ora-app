import 'package:flutter_test/flutter_test.dart';
import 'package:ora/features/ride/domain/location/trip_location_listen_gate.dart';

void main() {
  group('tripLocationShouldListen', () {
    test('allows publish states', () {
      for (final s in [
        'DRIVER_ASSIGNED',
        'DRIVER_EN_ROUTE',
        'DRIVER_ARRIVED',
        'RIDE_STARTED',
        'driver_assigned',
      ]) {
        expect(tripLocationShouldListen(s), isTrue, reason: s);
      }
    });

    test('stops on terminal and completed', () {
      for (final s in [
        'RIDE_COMPLETED',
        'CANCELLED',
        'NO_SHOW',
        'RIDE_CLOSED',
        'EXPIRED',
        'SEARCHING',
        null,
        '',
      ]) {
        expect(tripLocationShouldListen(s), isFalse, reason: '$s');
        expect(tripLocationMustStop(s), isTrue, reason: '$s');
      }
    });
  });
}
