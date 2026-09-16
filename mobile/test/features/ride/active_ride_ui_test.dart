import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/app/theme/theme.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';
import 'package:ora/features/ride/domain/use_cases/ride_use_cases.dart';
import 'package:ora/features/ride/presentation/view_models/active_ride_view_model.dart';
import 'package:ora/features/ride/presentation/views/active_ride_view.dart';

import '../../helpers/in_memory_idempotency_nonce_store.dart';

class MockGetRideUseCase extends Mock implements GetRideUseCase {}

class MockCancelRideUseCase extends Mock implements CancelRideUseCase {}

class MockCloseRideUseCase extends Mock implements CloseRideUseCase {}

Ride _ride({
  String state = 'DRIVER_ASSIGNED',
  String? arrivedAt,
  int? agreedFareMinor = 21000,
}) {
  return Ride(
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
    assignedDriverId: 'd1',
    arrivedAt: arrivedAt,
    agreedFareMinor: agreedFareMinor,
    agreedFareCurrency: agreedFareMinor != null ? 'PKR' : null,
  );
}

Widget _wrap(
  Widget child, {
  required List<Override> overrides,
  Size size = const Size(390, 844),
  double textScale = 1,
}) {
  return ProviderScope(
    overrides: [
      ...overrides,
      activeRidePollingPolicyProvider.overrideWithValue(
        const ActiveRidePollingPolicy(
          intervals: [Duration(days: 1)],
          maxLifetime: Duration(days: 1),
        ),
      ),
      idempotencyNonceStoreProvider
          .overrideWithValue(InMemoryIdempotencyNonceStore()),
    ],
    child: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: MaterialApp(theme: OraTheme.dark(), home: child),
    ),
  );
}

void main() {
  late MockGetRideUseCase getRide;
  late MockCancelRideUseCase cancel;
  late MockCloseRideUseCase close;

  setUpAll(() {
    registerFallbackValue('');
  });

  setUp(() {
    getRide = MockGetRideUseCase();
    cancel = MockCancelRideUseCase();
    close = MockCloseRideUseCase();
  });

  List<Override> overrides() => [
        getRideUseCaseProvider.overrideWithValue(getRide),
        cancelRideUseCaseProvider.overrideWithValue(cancel),
        closeRideUseCaseProvider.overrideWithValue(close),
      ];

  testWidgets('DRIVER_ASSIGNED — no fake ETA/map claims', (tester) async {
    when(() => getRide(any())).thenAnswer((_) async => _ride());

    await tester.pumpWidget(
      _wrap(const ActiveRideView(rideId: 'ride-1'), overrides: overrides()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Driver assigned'), findsOneWidget);
    expect(find.textContaining('not available in this build'), findsOneWidget);
    expect(find.textContaining('ETA'), findsWidgets); // honest denial
    expect(find.text('Mark En Route'), findsNothing);
    expect(find.textContaining('4.9'), findsNothing);
    expect(find.text('Cancel ride'), findsOneWidget);
  });

  testWidgets('DRIVER_EN_ROUTE honest copy', (tester) async {
    when(() => getRide(any()))
        .thenAnswer((_) async => _ride(state: 'DRIVER_EN_ROUTE'));

    await tester.pumpWidget(
      _wrap(const ActiveRideView(rideId: 'ride-1'), overrides: overrides()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Driver on the way'), findsOneWidget);
    expect(find.textContaining('fake map'), findsOneWidget);
  });

  testWidgets('DRIVER_ARRIVED shows wait from arrivedAt', (tester) async {
    when(() => getRide(any())).thenAnswer(
      (_) async => _ride(
        state: 'DRIVER_ARRIVED',
        arrivedAt:
            DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String(),
      ),
    );

    await tester.pumpWidget(
      _wrap(const ActiveRideView(rideId: 'ride-1'), overrides: overrides()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Driver has arrived'), findsOneWidget);
    expect(find.textContaining('Waiting'), findsWidgets);
  });

  testWidgets('NO_SHOW — no invented fees', (tester) async {
    when(() => getRide(any()))
        .thenAnswer((_) async => _ride(state: 'NO_SHOW', agreedFareMinor: null));

    await tester.pumpWidget(
      _wrap(const ActiveRideView(rideId: 'ride-1'), overrides: overrides()),
    );
    await tester.pumpAndSettle();

    expect(find.text('No-show recorded'), findsOneWidget);
    expect(find.textContaining('No fees'), findsOneWidget);
    expect(find.text('Cancel ride'), findsNothing);
  });

  testWidgets('RIDE_COMPLETED shows close — not ratings form', (tester) async {
    when(() => getRide(any()))
        .thenAnswer((_) async => _ride(state: 'RIDE_COMPLETED'));

    await tester.pumpWidget(
      _wrap(const ActiveRideView(rideId: 'ride-1'), overrides: overrides()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ride completed'), findsOneWidget);
    expect(find.text('Close ride'), findsOneWidget);
    expect(find.text('Rate ride'), findsOneWidget);
    expect(find.text('Submit rating'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('no driver progression controls', (tester) async {
    when(() => getRide(any()))
        .thenAnswer((_) async => _ride(state: 'RIDE_STARTED'));

    await tester.pumpWidget(
      _wrap(const ActiveRideView(rideId: 'ride-1'), overrides: overrides()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ride in progress'), findsOneWidget);
    expect(find.text('Start Ride'), findsNothing);
    expect(find.text('Complete Ride'), findsNothing);
    expect(find.text('Mark Arrived'), findsNothing);
  });

  testWidgets('responsive 320@1.3 and tablet', (tester) async {
    when(() => getRide(any())).thenAnswer((_) async => _ride());

    await tester.pumpWidget(
      _wrap(
        const ActiveRideView(rideId: 'ride-1'),
        overrides: overrides(),
        size: const Size(320, 568),
        textScale: 1.3,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      _wrap(
        const ActiveRideView(rideId: 'ride-1'),
        overrides: overrides(),
        size: const Size(768, 1024),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
