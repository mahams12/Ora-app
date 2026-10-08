import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora/app/theme/theme.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';
import 'package:ora/features/ride/domain/location/trip_location_freshness.dart';
import 'package:ora/features/ride/domain/models/trip_location_latest.dart';
import 'package:ora/features/ride/presentation/location/trip_location_session.dart';
import 'package:ora/features/ride/presentation/utils/active_ride_map_progression_policy.dart';
import 'package:ora/features/ride/presentation/widgets/active_ride_map.dart';

Ride _ride({String state = 'DRIVER_ASSIGNED'}) {
  return Ride(
    rideId: 'ride-map3',
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
}) {
  final at = DateTime.now().toUtc();
  return TripLocationLatest(
    lat: lat,
    lng: lng,
    accuracy: 8,
    heading: heading,
    speed: 4,
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
  testWidgets('A. user gesture latches ownership and suppresses identity fit',
      (tester) async {
    var animateCount = 0;
    bool? owns;
    var epoch = 0;
    final ride = _ride();

    Future<void> pump({
      TripLocationSessionState? session,
      Ride? nextRide,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: OraTheme.dark(),
          home: Scaffold(
            body: ActiveRideMap(
              ride: nextRide ?? ride,
              locationSession: session ?? _session(),
              enableMaps: false,
              showRecenter: false,
              userCameraMoveEpoch: epoch,
              onUserOwnsCameraChanged: (v) => owns = v,
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

    await pump();
    expect(animateCount, 1); // initial anchors fit
    expect(owns, isNull); // never latched true

    epoch++;
    await pump();
    expect(owns, isTrue);
    final afterGesture = animateCount;

    // First driver fix while owned — marker/guide path allowed, no camera.
    await pump(
      session: _session(
        latest: _latest(lat: 31.525, lng: 74.355, seq: 1),
        freshness: TripLocationFreshness.fresh,
      ),
    );
    expect(animateCount, afterGesture);
    expect(owns, isTrue);
  });

  testWidgets('B. first driver fix without gesture still animates once',
      (tester) async {
    var animateCount = 0;
    bool? owns;
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
            onUserOwnsCameraChanged: (v) => owns = v,
            onAnimateCamera: (_) async {
              animateCount++;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(animateCount, 1);
    expect(owns, isNull);

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
            onUserOwnsCameraChanged: (v) => owns = v,
            onAnimateCamera: (_) async {
              animateCount++;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(animateCount, 2);
    expect(owns, isNull);
  });

  testWidgets('B. first driver fix after gesture does not animate', (tester) async {
    var animateCount = 0;
    bool? owns;
    var epoch = 0;
    final ride = _ride();

    Future<void> pump(TripLocationSessionState session) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: OraTheme.dark(),
          home: Scaffold(
            body: ActiveRideMap(
              ride: ride,
              locationSession: session,
              enableMaps: false,
              showRecenter: false,
              userCameraMoveEpoch: epoch,
              onUserOwnsCameraChanged: (v) => owns = v,
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

    await pump(_session());
    expect(animateCount, 1);

    epoch++;
    await pump(_session());
    expect(owns, isTrue);
    final afterGesture = animateCount;

    await pump(
      _session(
        latest: _latest(lat: 31.525, lng: 74.355, seq: 1),
        freshness: TripLocationFreshness.fresh,
      ),
    );
    expect(animateCount, afterGesture);
  });

  testWidgets('C. RIDE_STARTED without ownership still reframes once',
      (tester) async {
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
    final before = animateCount;
    expect(before, 1);

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
    expect(animateCount, before + 1);
  });

  testWidgets('C. RIDE_STARTED while owned flips guide without animate',
      (tester) async {
    var animateCount = 0;
    bool? owns;
    var epoch = 0;
    List<ActiveRideMapGuideSegment>? guides;

    Future<void> pump({
      required Ride ride,
      required TripLocationSessionState session,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: OraTheme.dark(),
          home: Scaffold(
            body: ActiveRideMap(
              ride: ride,
              locationSession: session,
              enableMaps: false,
              showRecenter: false,
              userCameraMoveEpoch: epoch,
              onUserOwnsCameraChanged: (v) => owns = v,
              onProgressionSegments: (s) => guides = s,
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

    final session = _session(
      latest: _latest(lat: 31.525, lng: 74.355, seq: 2),
      freshness: TripLocationFreshness.fresh,
    );

    await pump(ride: _ride(state: 'DRIVER_EN_ROUTE'), session: session);
    expect(animateCount, 1);
    expect(guides!.single.kind, ActiveRideMapGuideKind.driverToPickup);

    epoch++;
    await pump(ride: _ride(state: 'DRIVER_EN_ROUTE'), session: session);
    expect(owns, isTrue);
    final afterGesture = animateCount;

    await pump(
      ride: _ride(state: 'RIDE_STARTED'),
      session: _session(
        latest: _latest(lat: 31.527, lng: 74.357, seq: 5),
        freshness: TripLocationFreshness.fresh,
      ),
    );
    expect(guides!.single.kind, ActiveRideMapGuideKind.driverToDestination);
    expect(animateCount, afterGesture);
    expect(owns, isTrue);
  });

  testWidgets('D. Recenter clears ownership and animates exactly once',
      (tester) async {
    var animateCount = 0;
    bool? owns;
    var epoch = 0;
    final ride = _ride();
    final withDriver = _session(
      latest: _latest(lat: 31.525, lng: 74.355, seq: 1),
      freshness: TripLocationFreshness.fresh,
    );

    Future<void> pump() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: OraTheme.dark(),
          home: Scaffold(
            body: ActiveRideMap(
              ride: ride,
              locationSession: withDriver,
              enableMaps: false,
              showRecenter: true,
              userCameraMoveEpoch: epoch,
              onUserOwnsCameraChanged: (v) => owns = v,
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

    await pump();
    expect(animateCount, 1);

    epoch++;
    await pump();
    expect(owns, isTrue);
    final afterGesture = animateCount;

    // Identity change while owned — suppressed.
    await tester.pumpWidget(
      MaterialApp(
        theme: OraTheme.dark(),
        home: Scaffold(
          body: ActiveRideMap(
            ride: _ride(state: 'RIDE_STARTED'),
            locationSession: _session(
              latest: _latest(lat: 31.528, lng: 74.358, seq: 3),
              freshness: TripLocationFreshness.fresh,
            ),
            enableMaps: false,
            showRecenter: true,
            userCameraMoveEpoch: epoch,
            onUserOwnsCameraChanged: (v) => owns = v,
            onAnimateCamera: (_) async {
              animateCount++;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(animateCount, afterGesture);

    await tester.tap(find.byTooltip('Recenter map'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(owns, isFalse);
    expect(animateCount, afterGesture + 1);
  });

  testWidgets('E. new user gesture after Recenter re-owns and suppresses',
      (tester) async {
    var animateCount = 0;
    bool? owns;
    var epoch = 0;

    Future<void> pump({
      required Ride ride,
      required TripLocationSessionState session,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: OraTheme.dark(),
          home: Scaffold(
            body: ActiveRideMap(
              ride: ride,
              locationSession: session,
              enableMaps: false,
              showRecenter: true,
              userCameraMoveEpoch: epoch,
              onUserOwnsCameraChanged: (v) => owns = v,
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

    final base = _session(
      latest: _latest(lat: 31.525, lng: 74.355, seq: 1),
      freshness: TripLocationFreshness.fresh,
    );

    await pump(ride: _ride(), session: base);
    epoch++;
    await pump(ride: _ride(), session: base);
    expect(owns, isTrue);

    await tester.tap(find.byTooltip('Recenter map'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(owns, isFalse);
    final afterRecenter = animateCount;

    epoch++;
    await pump(ride: _ride(), session: base);
    expect(owns, isTrue);

    await pump(
      ride: _ride(state: 'RIDE_STARTED'),
      session: _session(
        latest: _latest(lat: 31.53, lng: 74.36, seq: 4),
        freshness: TripLocationFreshness.fresh,
      ),
    );
    expect(animateCount, afterRecenter);
    expect(owns, isTrue);
  });

  testWidgets('F. programmatic MAP-2B / Recenter animate does not latch ownership',
      (tester) async {
    var animateCount = 0;
    final ownershipEvents = <bool>[];
    final ride = _ride();

    await tester.pumpWidget(
      MaterialApp(
        theme: OraTheme.dark(),
        home: Scaffold(
          body: ActiveRideMap(
            ride: ride,
            locationSession: _session(),
            enableMaps: false,
            showRecenter: true,
            onUserOwnsCameraChanged: ownershipEvents.add,
            onAnimateCamera: (_) async {
              animateCount++;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(animateCount, 1);
    expect(ownershipEvents, isEmpty);

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
            showRecenter: true,
            onUserOwnsCameraChanged: ownershipEvents.add,
            onAnimateCamera: (_) async {
              animateCount++;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(animateCount, 2);
    expect(ownershipEvents, isEmpty);

    await tester.tap(find.byTooltip('Recenter map'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(animateCount, 3);
    expect(ownershipEvents, isEmpty);
  });

  testWidgets('G. MAP-2B regression — seq ticks do not spam animateCamera',
      (tester) async {
    var animateCount = 0;
    final ride = _ride();

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
    final afterFirst = animateCount;
    expect(afterFirst, 1);

    for (final seq in [2, 3, 4]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: OraTheme.dark(),
          home: Scaffold(
            body: ActiveRideMap(
              ride: ride,
              locationSession: _session(
                latest: _latest(
                  lat: 31.525 + seq * 0.001,
                  lng: 74.355 + seq * 0.001,
                  seq: seq,
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
    expect(animateCount, afterFirst);
  });

  testWidgets('H. MAP-2C while owned — guides update, no camera', (tester) async {
    var animateCount = 0;
    var epoch = 0;
    List<ActiveRideMapGuideSegment>? guides;
    final ride = _ride();

    Future<void> pump(TripLocationSessionState session) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: OraTheme.dark(),
          home: Scaffold(
            body: ActiveRideMap(
              ride: ride,
              locationSession: session,
              enableMaps: false,
              showRecenter: false,
              userCameraMoveEpoch: epoch,
              onProgressionSegments: (s) => guides = s,
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

    await pump(_session());
    epoch++;
    await pump(_session());
    final afterGesture = animateCount;

    await pump(
      _session(
        latest: _latest(lat: 31.525, lng: 74.355, seq: 1),
        freshness: TripLocationFreshness.fresh,
      ),
    );
    expect(guides!.single.kind, ActiveRideMapGuideKind.driverToPickup);
    // driver→pickup: start tracks driver; end is fixed pickup.
    final start1 = guides!.single.start;

    await pump(
      _session(
        latest: _latest(lat: 31.53, lng: 74.36, seq: 2),
        freshness: TripLocationFreshness.fresh,
      ),
    );
    expect(guides!.single.kind, ActiveRideMapGuideKind.driverToPickup);
    expect(guides!.single.start.latitude, isNot(start1.latitude));
    expect(animateCount, afterGesture);
  });
}
