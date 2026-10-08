import 'package:flutter_test/flutter_test.dart';
import 'package:ora/features/ride/domain/location/trip_location_freshness.dart';
import 'package:ora/features/ride/domain/models/trip_location_latest.dart';

TripLocationLatest _fix({required DateTime acceptedAt, int seq = 1}) {
  return TripLocationLatest(
    lat: 31.52,
    lng: 74.35,
    accuracy: 10,
    heading: 0,
    speed: 0,
    ts: acceptedAt.millisecondsSinceEpoch,
    acceptedAt: acceptedAt.toUtc().toIso8601String(),
    driverId: 'd1',
    locationSeq: seq,
    locationStreamId: 's1',
  );
}

void main() {
  const policy = TripLocationFreshnessPolicy();
  final now = DateTime.utc(2026, 10, 8, 12, 0, 0);

  group('TripLocationFreshnessPolicy', () {
    test('missing when null', () {
      expect(
        policy.classify(null, now: now),
        TripLocationFreshness.missing,
      );
    });

    test('fresh at 20s boundary inclusive', () {
      final fix = _fix(acceptedAt: now.subtract(const Duration(seconds: 20)));
      expect(policy.classify(fix, now: now), TripLocationFreshness.fresh);
    });

    test('stale just after 20s', () {
      final fix = _fix(acceptedAt: now.subtract(const Duration(seconds: 21)));
      expect(policy.classify(fix, now: now), TripLocationFreshness.stale);
    });

    test('stale at 45s boundary inclusive', () {
      final fix = _fix(acceptedAt: now.subtract(const Duration(seconds: 45)));
      expect(policy.classify(fix, now: now), TripLocationFreshness.stale);
    });

    test('degraded just after 45s', () {
      final fix = _fix(acceptedAt: now.subtract(const Duration(seconds: 46)));
      expect(policy.classify(fix, now: now), TripLocationFreshness.degraded);
    });

    test('degraded at 120s boundary inclusive', () {
      final fix = _fix(acceptedAt: now.subtract(const Duration(seconds: 120)));
      expect(policy.classify(fix, now: now), TripLocationFreshness.degraded);
    });

    test('expired just after 120s', () {
      final fix = _fix(acceptedAt: now.subtract(const Duration(seconds: 121)));
      expect(policy.classify(fix, now: now), TripLocationFreshness.expired);
    });

    test('future skew treated as fresh (zero age)', () {
      final fix = _fix(acceptedAt: now.add(const Duration(seconds: 30)));
      expect(policy.classify(fix, now: now), TripLocationFreshness.fresh);
    });

    test('shouldShowDriverMarker bands', () {
      expect(policy.shouldShowDriverMarker(TripLocationFreshness.fresh), isTrue);
      expect(policy.shouldShowDriverMarker(TripLocationFreshness.stale), isTrue);
      expect(
        policy.shouldShowDriverMarker(TripLocationFreshness.degraded),
        isTrue,
      );
      expect(
        policy.shouldShowDriverMarker(TripLocationFreshness.expired),
        isFalse,
      );
      expect(
        policy.shouldShowDriverMarker(TripLocationFreshness.missing),
        isFalse,
      );
    });
  });
}
