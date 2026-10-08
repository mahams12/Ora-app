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
    rideId: 'ride-prog',
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
  testWidgets('1. initial active ride — pickup↔destination guide', (tester) async {
    List<ActiveRideMapGuideSegment>? last;
    await tester.pumpWidget(
      MaterialApp(
        theme: OraTheme.dark(),
        home: Scaffold(
          body: ActiveRideMap(
            ride: _ride(),
            locationSession: _session(),
            enableMaps: false,
            showRecenter: false,
            onAnimateCamera: (_) async {},
            onProgressionSegments: (s) => last = s,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(last, isNotNull);
    expect(last!, hasLength(1));
    expect(last!.single.kind, ActiveRideMapGuideKind.pickupToDestination);
    expect(
      last!.single.semanticsLabel,
      contains('Guide line — not a road route'),
    );
    expect(
      find.bySemanticsLabel(RegExp('Guide line — not a road route')),
      findsWidgets,
    );
  });

  testWidgets('2. first valid driver fix — driver→pickup guide', (tester) async {
    List<ActiveRideMapGuideSegment>? last;
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
            onAnimateCamera: (_) async {},
            onProgressionSegments: (s) => last = s,
          ),
        ),
      ),
    );
    await tester.pump();

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
            onAnimateCamera: (_) async {},
            onProgressionSegments: (s) => last = s,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(last!.single.kind, ActiveRideMapGuideKind.driverToPickup);
    expect(last!.single.start.latitude, 31.525);
    expect(
      last!.single.semanticsLabel,
      'Guide line — not a road route. Driver to pickup.',
    );
    expect(
      find.bySemanticsLabel(RegExp('Driver to pickup')),
      findsWidgets,
    );
  });

  testWidgets('3–4. seq changes update guide endpoint; no extra animateCamera',
      (tester) async {
    var animateCount = 0;
    List<ActiveRideMapGuideSegment>? last;
    final ride = _ride();

    Future<void> pumpSession(TripLocationSessionState session) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: OraTheme.dark(),
          home: Scaffold(
            body: ActiveRideMap(
              ride: ride,
              locationSession: session,
              enableMaps: false,
              showRecenter: false,
              onAnimateCamera: (_) async {
                animateCount++;
              },
              onProgressionSegments: (s) => last = s,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
    }

    await pumpSession(_session());
    final afterAnchors = animateCount;
    expect(afterAnchors, 1);

    await pumpSession(
      _session(
        latest: _latest(lat: 31.525, lng: 74.355, seq: 1),
        freshness: TripLocationFreshness.fresh,
      ),
    );
    expect(animateCount, afterAnchors + 1);
    final afterAppear = animateCount;
    expect(last!.single.start.latitude, 31.525);

    await pumpSession(
      _session(
        latest: _latest(lat: 31.528, lng: 74.358, seq: 2, heading: 45),
        freshness: TripLocationFreshness.fresh,
      ),
    );
    await pumpSession(
      _session(
        latest: _latest(lat: 31.531, lng: 74.361, seq: 3, heading: 90),
        freshness: TripLocationFreshness.fresh,
      ),
    );

    expect(last!.single.kind, ActiveRideMapGuideKind.driverToPickup);
    expect(last!.single.start.latitude, 31.531);
    expect(animateCount, afterAppear, reason: 'seq ticks must not animateCamera');
  });

  testWidgets('5. RIDE_STARTED switches guide to driver→destination', (tester) async {
    List<ActiveRideMapGuideSegment>? last;
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
            onProgressionSegments: (s) => last = s,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(last!.single.kind, ActiveRideMapGuideKind.driverToPickup);
    final beforeStart = animateCount;

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
            onProgressionSegments: (s) => last = s,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(last!.single.kind, ActiveRideMapGuideKind.driverToDestination);
    expect(last!.single.end.latitude, 31.51);
    expect(animateCount, beforeStart + 1);
  });

  testWidgets('6. driver expires — driver guide disappears', (tester) async {
    List<ActiveRideMapGuideSegment>? last;
    final ride = _ride();
    final latest = _latest(lat: 31.525, lng: 74.355, seq: 3);

    await tester.pumpWidget(
      MaterialApp(
        theme: OraTheme.dark(),
        home: Scaffold(
          body: ActiveRideMap(
            ride: ride,
            locationSession: _session(
              latest: latest,
              freshness: TripLocationFreshness.fresh,
            ),
            enableMaps: false,
            showRecenter: false,
            onAnimateCamera: (_) async {},
            onProgressionSegments: (s) => last = s,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(last!.single.kind, ActiveRideMapGuideKind.driverToPickup);

    await tester.pumpWidget(
      MaterialApp(
        theme: OraTheme.dark(),
        home: Scaffold(
          body: ActiveRideMap(
            ride: ride,
            locationSession: _session(
              latest: latest,
              freshness: TripLocationFreshness.expired,
            ),
            enableMaps: false,
            showRecenter: false,
            onAnimateCamera: (_) async {},
            onProgressionSegments: (s) => last = s,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(last!.single.kind, ActiveRideMapGuideKind.pickupToDestination);
    expect(
      last!.any((s) => s.kind == ActiveRideMapGuideKind.driverToPickup),
      isFalse,
    );
  });

  testWidgets('7. maps disabled — soft shell; guide hook still reports', (tester) async {
    List<ActiveRideMapGuideSegment>? last;
    await tester.pumpWidget(
      MaterialApp(
        theme: OraTheme.dark(),
        home: Scaffold(
          body: ActiveRideMap(
            ride: _ride(),
            locationSession: _session(
              latest: _latest(lat: 31.525, lng: 74.355, seq: 1),
              freshness: TripLocationFreshness.fresh,
            ),
            enableMaps: false,
            showRecenter: false,
            onAnimateCamera: (_) async {},
            onProgressionSegments: (s) => last = s,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Map preview'), findsOneWidget);
    expect(last!.single.kind, ActiveRideMapGuideKind.driverToPickup);
  });

  testWidgets('8. terminal state — no crash; anchors guide only', (tester) async {
    List<ActiveRideMapGuideSegment>? last;
    await tester.pumpWidget(
      MaterialApp(
        theme: OraTheme.dark(),
        home: Scaffold(
          body: ActiveRideMap(
            ride: _ride(state: 'CANCELLED'),
            locationSession: _session(
              latest: _latest(lat: 31.525, lng: 74.355, seq: 9),
              freshness: TripLocationFreshness.fresh,
            ),
            enableMaps: false,
            showRecenter: false,
            onAnimateCamera: (_) async {},
            onProgressionSegments: (s) => last = s,
          ),
        ),
      ),
    );
    await tester.pump();
    // CANCELLED → anchors phase → no driver segment even if coords present.
    expect(last!.single.kind, ActiveRideMapGuideKind.pickupToDestination);
  });
}
