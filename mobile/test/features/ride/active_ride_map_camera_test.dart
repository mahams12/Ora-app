import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora/app/theme/theme.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';
import 'package:ora/features/ride/domain/location/trip_location_freshness.dart';
import 'package:ora/features/ride/domain/models/trip_location_latest.dart';
import 'package:ora/features/ride/presentation/location/trip_location_session.dart';
import 'package:ora/features/ride/presentation/widgets/active_ride_map.dart';

Ride _ride({String state = 'DRIVER_ASSIGNED'}) {
  return Ride(
    rideId: 'ride-cam',
    passengerId: 'p1',
    state: state,
    version: 2,
    requestVersion: 1,
    category: 'easy',
    serviceType: 'ride',
    pickup: const LatLngPoint(lat: 31.52, lng: 74.35, address: 'Pickup'),
    destination:
        const LatLngPoint(lat: 31.51, lng: 74.34, address: 'Destination'),
    pricingSnapshotId: 'snap',
    recommendedFareMinor: 25000,
    passengerOfferMinor: 25000,
    paymentMethod: 'CASH',
    passengerCount: 1,
    expiresAt: '2099-01-01T00:00:00.000Z',
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    assignedDriverId: 'd1',
    agreedFareMinor: 21000,
    agreedFareCurrency: 'PKR',
  );
}

TripLocationLatest _latest({
  required double lat,
  required double lng,
  required int seq,
  double heading = 0,
  double speed = 0,
  DateTime? acceptedAt,
}) {
  final at = acceptedAt ?? DateTime.now().toUtc();
  return TripLocationLatest(
    lat: lat,
    lng: lng,
    accuracy: 8,
    heading: heading,
    speed: speed,
    ts: at.millisecondsSinceEpoch,
    acceptedAt: at.toIso8601String(),
    driverId: 'd1',
    locationSeq: seq,
    locationStreamId: 'stream-1',
  );
}

TripLocationSessionState _session({
  TripLocationLatest? latest,
  TripLocationFreshness freshness = TripLocationFreshness.missing,
}) {
  return TripLocationSessionState(
    latest: latest,
    freshness: freshness,
    isListening: true,
    appliedSeq: latest?.locationSeq ?? 0,
  );
}

void main() {
  testWidgets('locationSeq ticks do not spam animateCamera', (tester) async {
    var animateCount = 0;
    final ride = _ride();

    await tester.pumpWidget(
      MaterialApp(
        theme: OraTheme.dark(),
        home: Scaffold(
          body: ActiveRideMap(
            ride: ride,
            locationSession: _session(),
            enableMaps: false,
            showRecenter: false,
            onAnimateCamera: (_) async {
              animateCount++;
            },
          ),
        ),
      ),
    );
    await tester.pump(); // post-frame first fit (anchors-only)
    await tester.pump(const Duration(milliseconds: 16));
    final afterFirst = animateCount;
    expect(afterFirst, 1); // pickup+destination

    // Driver appears → one intentional reframe.
    await tester.pumpWidget(
      MaterialApp(
        theme: OraTheme.dark(),
        home: Scaffold(
          body: ActiveRideMap(
            ride: ride,
            locationSession: _session(
              latest: _latest(lat: 31.525, lng: 74.355, seq: 1),
              freshness: TripLocationFreshness.fresh,
            ),
            enableMaps: false,
            showRecenter: false,
            onAnimateCamera: (_) async {
              animateCount++;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(animateCount, afterFirst + 1);
    final afterDriverAppears = animateCount;

    // Seq 2..4 with different coords — same phase, driver still present.
    for (final entry in [
      (31.526, 74.356, 2, 10.0, 3.0),
      (31.528, 74.358, 3, 45.0, 5.0),
      (31.531, 74.361, 4, 90.0, 8.0),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: OraTheme.dark(),
          home: Scaffold(
            body: ActiveRideMap(
              ride: ride,
              locationSession: _session(
                latest: _latest(
                  lat: entry.$1,
                  lng: entry.$2,
                  seq: entry.$3,
                  heading: entry.$4,
                  speed: entry.$5,
                ),
                freshness: TripLocationFreshness.fresh,
              ),
              enableMaps: false,
              showRecenter: false,
              onAnimateCamera: (_) async {
                animateCount++;
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(
      animateCount,
      afterDriverAppears,
      reason: 'RTDB ticks must not animateCamera',
    );
  });

  testWidgets('RIDE_STARTED causes exactly one intentional reframe', (tester) async {
    var animateCount = 0;
    final latest = _latest(lat: 31.525, lng: 74.355, seq: 2);

    await tester.pumpWidget(
      MaterialApp(
        theme: OraTheme.dark(),
        home: Scaffold(
          body: ActiveRideMap(
            ride: _ride(state: 'DRIVER_EN_ROUTE'),
            locationSession: _session(
              latest: latest,
              freshness: TripLocationFreshness.fresh,
            ),
            enableMaps: false,
            showRecenter: false,
            onAnimateCamera: (_) async {
              animateCount++;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final beforeStart = animateCount;
    expect(beforeStart, 1);

    await tester.pumpWidget(
      MaterialApp(
        theme: OraTheme.dark(),
        home: Scaffold(
          body: ActiveRideMap(
            ride: _ride(state: 'RIDE_STARTED'),
            locationSession: _session(
              latest: _latest(lat: 31.527, lng: 74.357, seq: 5),
              freshness: TripLocationFreshness.fresh,
            ),
            enableMaps: false,
            showRecenter: false,
            onAnimateCamera: (_) async {
              animateCount++;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(animateCount, beforeStart + 1);

    // Further ticks in RIDE_STARTED must not animate.
    await tester.pumpWidget(
      MaterialApp(
        theme: OraTheme.dark(),
        home: Scaffold(
          body: ActiveRideMap(
            ride: _ride(state: 'RIDE_STARTED'),
            locationSession: _session(
              latest: _latest(lat: 31.529, lng: 74.359, seq: 6),
              freshness: TripLocationFreshness.fresh,
            ),
            enableMaps: false,
            showRecenter: false,
            onAnimateCamera: (_) async {
              animateCount++;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(animateCount, beforeStart + 1);
  });

}
