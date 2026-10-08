import 'package:flutter_test/flutter_test.dart';
import 'package:ora/features/ride/domain/models/trip_location_latest.dart';

Map<String, Object?> _valid({
  Object? lat = 31.52,
  Object? lng = 74.35,
  Object? accuracy = 12.0,
  Object? heading = 90.0,
  Object? speed = 20.0,
  Object? ts,
  Object? acceptedAt = '2026-10-08T06:00:00.000Z',
  Object? driverId = 'driver-1',
  Object? locationSeq = 3,
  Object? locationStreamId = 'stream-a',
}) {
  return {
    'lat': lat,
    'lng': lng,
    'accuracy': accuracy,
    'heading': heading,
    'speed': speed,
    'ts': ts ?? DateTime.parse('2026-10-08T06:00:00.000Z').millisecondsSinceEpoch,
    'acceptedAt': acceptedAt,
    'driverId': driverId,
    'locationSeq': locationSeq,
    'locationStreamId': locationStreamId,
  };
}

void main() {
  group('TripLocationLatest.tryParse', () {
    test('parses valid payload', () {
      final parsed = TripLocationLatest.tryParse(_valid());
      expect(parsed, isNotNull);
      expect(parsed!.lat, 31.52);
      expect(parsed.lng, 74.35);
      expect(parsed.locationSeq, 3);
      expect(parsed.driverId, 'driver-1');
      expect(parsed.hasValidCoordinates, isTrue);
    });

    test('rejects null / non-map', () {
      expect(TripLocationLatest.tryParse(null), isNull);
      expect(TripLocationLatest.tryParse('x'), isNull);
      expect(TripLocationLatest.tryParse(42), isNull);
    });

    test('rejects non-finite / out-of-range coordinates', () {
      expect(TripLocationLatest.tryParse(_valid(lat: double.nan)), isNull);
      expect(TripLocationLatest.tryParse(_valid(lng: double.infinity)), isNull);
      expect(TripLocationLatest.tryParse(_valid(lat: 91)), isNull);
      expect(TripLocationLatest.tryParse(_valid(lng: -181)), isNull);
    });

    test('rejects missing required fields', () {
      final missingDriver = _valid()..remove('driverId');
      expect(TripLocationLatest.tryParse(missingDriver), isNull);
      final missingSeq = _valid()..remove('locationSeq');
      expect(TripLocationLatest.tryParse(missingSeq), isNull);
      expect(TripLocationLatest.tryParse(_valid(locationSeq: 0)), isNull);
      expect(TripLocationLatest.tryParse(_valid(locationSeq: -1)), isNull);
      expect(
        TripLocationLatest.tryParse(_valid(acceptedAt: 'not-a-date')),
        isNull,
      );
      expect(TripLocationLatest.tryParse(_valid(acceptedAt: '')), isNull);
      expect(TripLocationLatest.tryParse(_valid(driverId: '  ')), isNull);
    });

    test('rejects negative accuracy', () {
      expect(TripLocationLatest.tryParse(_valid(accuracy: -1)), isNull);
    });

    test('accepts int numeric fields from RTDB', () {
      final parsed = TripLocationLatest.tryParse(
        _valid(lat: 31, lng: 74, accuracy: 10, heading: 0, speed: 5),
      );
      expect(parsed, isNotNull);
      expect(parsed!.lat, 31);
    });

    test('malformed never throws', () {
      expect(
        () => TripLocationLatest.tryParse({
          'lat': 'nope',
          'lng': true,
          'nested': {'x': 1},
        }),
        returnsNormally,
      );
      expect(
        TripLocationLatest.tryParse({
          'lat': 'nope',
          'lng': true,
        }),
        isNull,
      );
    });
  });
}
