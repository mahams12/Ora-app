import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora/app/theme/theme.dart';
import 'package:ora/features/driver/presentation/open_ride_display.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';
import 'package:ora/features/ride/domain/models/resolved_passenger_location.dart';
import 'package:ora/features/ride/presentation/widgets/ride_card/ride_card.dart';
import 'package:ora/features/ride/presentation/widgets/ride_card/ride_card_avatar.dart';

OpenRide _openRide({
  String state = 'SEARCHING',
  String? pickupAddress = 'Bahria Town, Phase 7',
  String? destAddress = 'Liberty Market, Gulberg III',
}) {
  return OpenRide(
    rideId: 'ride_open_1',
    state: state,
    requestVersion: 1,
    category: 'easy',
    serviceType: 'ride',
    pickup: LatLngPoint(lat: 31.46, lng: 74.26, address: pickupAddress),
    destination: LatLngPoint(lat: 31.52, lng: 74.34, address: destAddress),
    recommendedFareMinor: 120000,
    passengerOfferMinor: 114000,
    paymentMethod: 'CASH',
    passengerCount: 1,
    distanceKm: 24.0,
    estimatedDurationMin: 39,
    expiresAt: '2099-01-01T00:00:00.000Z',
    createdAt: '2026-01-01T00:00:00.000Z',
  );
}

Ride _ride({
  String state = 'RIDE_STARTED',
  String? assignedDriverId = 'driver_1',
  int? agreedFareMinor = 114000,
}) {
  return Ride(
    rideId: 'ride_hist_1',
    passengerId: 'passenger_1',
    assignedDriverId: assignedDriverId,
    state: state,
    version: 2,
    requestVersion: 1,
    category: 'easy',
    serviceType: 'ride',
    pickup: const LatLngPoint(
      lat: 31.46,
      lng: 74.26,
      address: 'Bahria Town, Lahore',
    ),
    destination: const LatLngPoint(
      lat: 31.52,
      lng: 74.34,
      address: 'Liberty Market, Lahore',
    ),
    pricingSnapshotId: 'ps_1',
    recommendedFareMinor: 120000,
    passengerOfferMinor: 114000,
    agreedFareMinor: agreedFareMinor,
    agreedFareCurrency: agreedFareMinor == null ? null : 'PKR',
    paymentMethod: 'CASH',
    passengerCount: 1,
    expiresAt: '2099-01-01T00:00:00.000Z',
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T01:00:00.000Z',
  );
}

Future<void> _pumpCard(WidgetTester tester, RideCardModel model) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: OraTheme.dark(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: RideCard(model: model),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('RideCardAdapters / Open Rides', () {
    testWidgets('epic open ride shows map, route, Easy, earnings, Decline+Accept',
        (tester) async {
      var responded = false;
      final model = RideCardAdapters.fromOpenRide(
        _openRide(),
        offering: false,
        offerDisabled: false,
        onAccept: () => responded = true,
      );

      await _pumpCard(tester, model);

      expect(model.showMapThumb, isTrue);
      expect(model.showCarAccent, isTrue);
      expect(model.participant, isNull);
      expect(model.categoryLabel, 'Easy');
      expect(model.fareCaption, 'Trip fare');

      expect(find.text('Pickup'), findsOneWidget);
      expect(find.text('Bahria Town, Phase 7'), findsOneWidget);
      expect(find.text('Liberty Market, Gulberg III'), findsOneWidget);
      expect(find.text('Rs 1140'), findsOneWidget);
      expect(find.text('Trip fare'), findsOneWidget);
      expect(find.textContaining('24 km'), findsOneWidget);
      expect(find.textContaining('39 min'), findsOneWidget);
      expect(find.text('Easy'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);

      // Flutter-built empty avatar (not a photo / not fake name).
      expect(find.byType(RideCardAvatarPlaceholder), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
      expect(find.text('Passenger'), findsNothing);
      expect(find.textContaining('Recommended'), findsNothing);
      expect(find.textContaining('Ayesha'), findsNothing);
      expect(find.textContaining('4.8'), findsNothing);

      await tester.tap(find.text('Accept'));
      await tester.pump();
      expect(responded, isTrue);
    });

    testWidgets('Decline callback fires without claiming server success',
        (tester) async {
      var declined = false;
      final model = RideCardAdapters.fromOpenRide(
        _openRide(),
        offering: false,
        offerDisabled: false,
        onAccept: () {},
        onDecline: () => declined = true,
      );
      await _pumpCard(tester, model);
      await tester.tap(find.text('Decline'));
      await tester.pump();
      expect(declined, isTrue);
      expect(find.textContaining('Declined'), findsNothing);
      expect(find.textContaining('declined'), findsNothing);
    });

    testWidgets('omits optional distance/duration when absent', (tester) async {
      const ride = OpenRide(
        rideId: 'ride_open_2',
        state: 'OFFERS_AVAILABLE',
        requestVersion: 1,
        category: 'easy',
        serviceType: 'ride',
        pickup: LatLngPoint(lat: 31.46, lng: 74.26),
        destination: LatLngPoint(lat: 31.52, lng: 74.34),
        recommendedFareMinor: 10000,
        passengerOfferMinor: 10000,
        paymentMethod: 'CASH',
        passengerCount: 2,
        expiresAt: '2099-01-01T00:00:00.000Z',
        createdAt: '2026-01-01T00:00:00.000Z',
      );
      final model = RideCardAdapters.fromOpenRide(
        ride,
        offering: false,
        offerDisabled: false,
        onAccept: () {},
      );
      await _pumpCard(tester, model);
      expect(find.text('Location selected'), findsNWidgets(2));
      expect(find.textContaining(' km'), findsNothing);
      expect(find.textContaining(' min'), findsNothing);
    });

    test('maps Current location address to Location selected', () {
      final model = RideCardAdapters.fromOpenRide(
        _openRide(pickupAddress: 'Current location'),
        offering: false,
        offerDisabled: false,
        onAccept: () {},
      );
      expect(model.pickupLabel, 'Location selected');
      expect(model.pickupLabel.toLowerCase(), isNot(contains('current')));
      expect(model.pickupLat, 31.46);
      expect(model.pickupLng, 74.26);
    });
  });

  group('RideCardAdapters / Driver My Rides', () {
    testWidgets('active job card shows In progress and agreed fare',
        (tester) async {
      var tapped = false;
      final model = RideCardAdapters.fromDriverJob(
        _ride(state: 'RIDE_STARTED'),
        onTap: () => tapped = true,
      );
      await _pumpCard(tester, model);

      expect(find.text('In progress'), findsOneWidget);
      expect(
        find.textContaining('Bahria Town, Lahore → Liberty Market, Lahore'),
        findsOneWidget,
      );
      expect(find.textContaining('Rs 1140'), findsOneWidget);
      expect(find.text('Agreed fare'), findsOneWidget);
      expect(model.participant, isNull);
      expect(find.text('Passenger'), findsNothing);
      expect(find.textContaining('LEA-'), findsNothing);
      expect(find.textContaining('Ayesha'), findsNothing);

      await tester.tap(find.byType(RideCard));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('completed job uses success status', (tester) async {
      final model = RideCardAdapters.fromDriverJob(
        _ride(state: 'RIDE_CLOSED'),
      );
      expect(model.tone, RideCardTone.standard);
      expect(model.statusLabel, 'Completed');
      expect(model.statusKind, RideCardStatusKind.success);
      await _pumpCard(tester, model);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Trip fare'), findsOneWidget);
    });
  });

  group('RideCardAdapters / Passenger My Rides', () {
    testWidgets('history omits driver profile placeholder', (tester) async {
      final model = RideCardAdapters.fromPassengerHistory(
        _ride(state: 'RIDE_COMPLETED'),
      );
      expect(model.participant, isNull);
      expect(model.showMapThumb, isFalse);
      await _pumpCard(tester, model);
      expect(find.text('Driver'), findsNothing);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.textContaining('Toyota'), findsNothing);
      expect(find.textContaining('4.9'), findsNothing);
      expect(find.text('Paid (Cash)'), findsOneWidget);
    });

    testWidgets('omits participant when no assigned driver', (tester) async {
      final model = RideCardAdapters.fromPassengerHistory(
        _ride(state: 'SEARCHING', assignedDriverId: null, agreedFareMinor: null),
      );
      expect(model.participant, isNull);
      await _pumpCard(tester, model);
      expect(find.text('Driver'), findsNothing);
      expect(find.text('Passenger'), findsNothing);
    });

    testWidgets('cancelled history shows Cancelled caption, distance, em-dash duration',
        (tester) async {
      final model = RideCardAdapters.fromPassengerHistory(
        _ride(state: 'CANCELLED', assignedDriverId: null),
      );
      expect(model.statusLabel, 'Cancelled');
      expect(model.fareCaption, 'Cancelled');
      expect(model.distanceLabel, isNotNull);
      expect(model.distanceLabel!, contains('km'));
      expect(model.durationLabel, isNull);
      await _pumpCard(tester, model);
      expect(find.text('Cancelled'), findsWidgets);
      expect(find.textContaining('km'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(find.text('Distance'), findsOneWidget);
      expect(find.text('Duration'), findsOneWidget);
    });
  });

  group('RideCardAdapters / Offer', () {
    testWidgets('offer card has no fabricated route or identity', (tester) async {
      const offer = RideOffer(
        offerId: 'off_1',
        rideId: 'ride_1',
        driverId: 'd1',
        amountMinor: 114000,
        currency: 'PKR',
        type: 'DRIVER_COUNTEROFFER',
        status: 'PENDING',
        requestVersion: 1,
        expiresAt: '2099-01-01T12:30:00.000Z',
        createdAt: '2026-01-01T00:00:00.000Z',
        driverSnapshot: {'displayName': null, 'role': 'driver'},
      );
      final model = RideCardAdapters.fromOffer(
        offer,
        onSelect: () {},
        isSelecting: false,
        enabled: true,
      );
      expect(model.showRoutePreview, isFalse);
      expect(model.participant, isNull);
      await _pumpCard(tester, model);
      expect(find.text('Select'), findsOneWidget);
      expect(find.text('Driver offer'), findsWidgets);
      expect(find.text('Pickup'), findsNothing);
    });

    testWidgets('offer shows real driver name when API provides it',
        (tester) async {
      const offer = RideOffer(
        offerId: 'off_2',
        rideId: 'ride_1',
        driverId: 'd1',
        amountMinor: 114000,
        currency: 'PKR',
        type: 'DRIVER_COUNTEROFFER',
        status: 'PENDING',
        requestVersion: 1,
        expiresAt: '2099-01-01T12:30:00.000Z',
        createdAt: '2026-01-01T00:00:00.000Z',
        driverSnapshot: {
          'displayName': 'Ali Raza',
          'role': 'driver',
        },
      );
      final model = RideCardAdapters.fromOffer(
        offer,
        onSelect: () {},
        isSelecting: false,
        enabled: true,
      );
      expect(model.participant?.displayName, 'Ali Raza');
      await _pumpCard(tester, model);
      expect(find.text('Ali Raza'), findsWidgets);
    });
  });

  group('location labels', () {
    test('humanReadablePlaceLabel never invents or exposes coords', () {
      expect(humanReadablePlaceLabel(null), 'Location selected');
      expect(humanReadablePlaceLabel(''), 'Location selected');
      expect(humanReadablePlaceLabel('Current location'), 'Location selected');
      expect(
        humanReadablePlaceLabel('Bahria Town, Phase 7'),
        'Bahria Town, Phase 7',
      );
      expect(
        openRideLocationLabel(
          const LatLngPoint(lat: 1, lng: 2),
          fallback: 'Location selected',
        ),
        'Location selected',
      );
    });

    test('ResolvedPassengerLocation.displayLabel never shows coords', () {
      const gps = ResolvedPassengerLocation(
        lat: 31.46,
        lng: 74.26,
        source: PassengerLocationSource.gps,
      );
      expect(gps.displayLabel, 'Location selected');
      expect(gps.displayLabel, isNot(contains('31.46')));

      const legacy = ResolvedPassengerLocation(
        lat: 31.46,
        lng: 74.26,
        address: 'Current location',
        source: PassengerLocationSource.gps,
      );
      expect(legacy.displayLabel, 'Location selected');

      const named = ResolvedPassengerLocation(
        lat: 31.46,
        lng: 74.26,
        address: 'Bahria Town, Lahore',
        source: PassengerLocationSource.gps,
      );
      expect(named.displayLabel, 'Bahria Town, Lahore');
      expect(named.lat, 31.46);
      expect(named.lng, 74.26);
    });
  });

  group('missing optional profile / vehicle', () {
    test('participant without stats does not claim fake rating', () {
      const p = RideCardParticipant(roleLabel: 'Passenger');
      expect(p.hasStats, isFalse);
      expect(p.hasIdentity, isFalse);
      expect(p.resolvedName, 'Passenger');
    });

    test('vehicle without fields is omitted', () {
      const v = RideCardVehicle();
      expect(v.hasAnyField, isFalse);
    });
  });
}
