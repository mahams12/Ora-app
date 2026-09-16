import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/app/theme/theme.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';
import 'package:ora/features/ride/domain/use_cases/ride_use_cases.dart';
import 'package:ora/features/ride/presentation/view_models/offers_inbox_view_model.dart';
import 'package:ora/features/ride/presentation/views/offers_inbox_view.dart';
import 'package:ora/features/ride/presentation/widgets/offer_card.dart';

import '../../helpers/in_memory_idempotency_nonce_store.dart';

class MockGetRideUseCase extends Mock implements GetRideUseCase {}

class MockListOffersUseCase extends Mock implements ListOffersUseCase {}

class MockSelectOfferUseCase extends Mock implements SelectOfferUseCase {}

Ride _ride({String state = 'OFFERS_AVAILABLE'}) => Ride(
      rideId: 'ride-1',
      passengerId: 'p1',
      state: state,
      version: 2,
      requestVersion: 1,
      category: 'easy',
      serviceType: 'ride',
      pickup: const LatLngPoint(lat: 1, lng: 2, address: 'Gulberg'),
      destination: const LatLngPoint(lat: 3, lng: 4, address: 'Liberty'),
      pricingSnapshotId: 'snap',
      recommendedFareMinor: 25000,
      passengerOfferMinor: 25000,
      paymentMethod: 'CASH',
      passengerCount: 1,
      expiresAt: '2099-01-01T00:00:00.000Z',
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: '2026-01-01T00:00:00.000Z',
    );

RideOffer _offer({
  required String id,
  int amount = 22000,
  String status = 'PENDING',
}) =>
    RideOffer(
      offerId: id,
      rideId: 'ride-1',
      driverId: 'internal-driver-id',
      amountMinor: amount,
      currency: 'PKR',
      type: 'COUNTER',
      status: status,
      requestVersion: 1,
      expiresAt: '2099-01-01T12:30:00.000Z',
      createdAt: '2026-01-01T00:00:00.000Z',
      driverSnapshot: const {'displayName': null, 'role': 'driver'},
    );

Widget _wrap(
  Widget child, {
  required List<Override> overrides,
  Size size = const Size(390, 844),
  double textScale = 1,
}) {
  return ProviderScope(
    overrides: [
      ...overrides,
      offerPollingPolicyProvider.overrideWithValue(
        const OfferPollingPolicy(
          intervals: [Duration(days: 1)],
          maxLifetime: Duration(days: 1),
        ),
      ),
    ],
    child: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: MaterialApp(
        theme: OraTheme.dark(),
        home: child,
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(0);
  });

  late MockGetRideUseCase getRide;
  late MockListOffersUseCase listOffers;
  late MockSelectOfferUseCase selectOffer;

  setUp(() {
    getRide = MockGetRideUseCase();
    listOffers = MockListOffersUseCase();
    selectOffer = MockSelectOfferUseCase();
  });

  List<Override> overrides() => [
        getRideUseCaseProvider.overrideWithValue(getRide),
        listOffersUseCaseProvider.overrideWithValue(listOffers),
        selectOfferUseCaseProvider.overrideWithValue(selectOffer),
        idempotencyNonceStoreProvider
            .overrideWithValue(InMemoryIdempotencyNonceStore()),
      ];

  testWidgets('empty waiting state', (tester) async {
    when(() => getRide(any())).thenAnswer((_) async => _ride());
    when(() => listOffers(any())).thenAnswer((_) async => []);

    await tester.pumpWidget(
      _wrap(const OffersInboxView(rideId: 'ride-1'), overrides: overrides()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Waiting for offers'), findsOneWidget);
    expect(find.textContaining('not inventing'), findsOneWidget);
    expect(find.textContaining('nearby'), findsOneWidget);
    expect(find.byType(OfferCard), findsNothing);
    expect(find.textContaining('internal-driver-id'), findsNothing);
    expect(find.textContaining('4.9'), findsNothing);
  });

  testWidgets('renders multiple real offers without fake driver bios',
      (tester) async {
    when(() => getRide(any())).thenAnswer((_) async => _ride());
    when(() => listOffers(any())).thenAnswer(
      (_) async => [
        _offer(id: 'o1', amount: 20000),
        _offer(id: 'o2', amount: 24000),
      ],
    );

    await tester.pumpWidget(
      _wrap(const OffersInboxView(rideId: 'ride-1'), overrides: overrides()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(OfferCard), findsNWidgets(2));
    expect(find.text('Rs 200'), findsOneWidget);
    expect(find.text('Rs 240'), findsOneWidget);
    expect(find.text('Driver offer'), findsWidgets);
    expect(find.text('Ali'), findsNothing);
    expect(find.textContaining('Corolla'), findsNothing);
    expect(find.textContaining('★'), findsNothing);
  });

  testWidgets('selecting shows assigned transitional state', (tester) async {
    when(() => getRide(any())).thenAnswer((_) async => _ride());
    when(() => listOffers(any()))
        .thenAnswer((_) async => [_offer(id: 'o1', amount: 21000)]);
    when(
      () => selectOffer(
        rideId: any(named: 'rideId'),
        offerId: any(named: 'offerId'),
        expectedVersion: any(named: 'expectedVersion'),
        operationKey: any(named: 'operationKey'),
      ),
    ).thenAnswer(
      (_) async => const RideAssignment(
        rideId: 'ride-1',
        state: 'DRIVER_ASSIGNED',
        version: 3,
        assignedDriverId: 'd1',
        agreedFareMinor: 21000,
        agreedOfferId: 'o1',
        currency: 'PKR',
      ),
    );

    await tester.pumpWidget(
      _wrap(const OffersInboxView(rideId: 'ride-1'), overrides: overrides()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();

    expect(find.text('Driver assigned'), findsOneWidget);
    expect(find.text('Open active ride'), findsOneWidget);
    expect(find.textContaining('Finding drivers'), findsNothing);
  });

  testWidgets('terminal EXPIRED renders ended state', (tester) async {
    when(() => getRide(any()))
        .thenAnswer((_) async => _ride(state: 'EXPIRED'));
    when(() => listOffers(any())).thenAnswer((_) async => []);

    await tester.pumpWidget(
      _wrap(const OffersInboxView(rideId: 'ride-1'), overrides: overrides()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Request ended'), findsOneWidget);
    expect(find.textContaining('EXPIRED'), findsWidgets);
  });

  testWidgets('fatal error shows retry', (tester) async {
    when(() => getRide(any())).thenThrow(Exception('boom'));
    when(() => listOffers(any())).thenAnswer((_) async => []);

    await tester.pumpWidget(
      _wrap(const OffersInboxView(rideId: 'ride-1'), overrides: overrides()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load offers'), findsOneWidget);
  });

  testWidgets('responsive 320 / 1.3x and tablet', (tester) async {
    when(() => getRide(any())).thenAnswer((_) async => _ride());
    when(() => listOffers(any()))
        .thenAnswer((_) async => [_offer(id: 'o1')]);

    await tester.pumpWidget(
      _wrap(
        const OffersInboxView(rideId: 'ride-1'),
        overrides: overrides(),
        size: const Size(320, 568),
        textScale: 1.3,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      _wrap(
        const OffersInboxView(rideId: 'ride-1'),
        overrides: overrides(),
        size: const Size(768, 1024),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
