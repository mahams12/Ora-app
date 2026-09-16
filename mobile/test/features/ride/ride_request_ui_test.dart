import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/app/router/routes.dart';
import 'package:ora/app/theme/theme.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';
import 'package:ora/features/ride/domain/use_cases/ride_use_cases.dart';
import 'package:ora/features/ride/presentation/view_models/offers_inbox_view_model.dart';
import 'package:ora/features/ride/presentation/view_models/ride_request_view_model.dart';
import 'package:ora/features/ride/presentation/views/offers_inbox_view.dart';
import 'package:ora/features/ride/presentation/views/ride_request_created_view.dart';
import 'package:ora/features/ride/presentation/views/ride_request_view.dart';

class MockCreateRideUseCase extends Mock implements CreateRideUseCase {}

class MockGetRideUseCase extends Mock implements GetRideUseCase {}

class MockListOffersUseCase extends Mock implements ListOffersUseCase {}

Widget _wrap(
  Widget child, {
  List<Override> overrides = const [],
  Size size = const Size(390, 844),
  double textScale = 1,
}) {
  return ProviderScope(
    overrides: overrides,
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
    registerFallbackValue(<String, Object?>{});
  });

  testWidgets('compose surface renders pickup destination and CTA', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const RideRequestView()));
    await tester.pumpAndSettle();

    expect(find.text('Where to?'), findsOneWidget);
    expect(find.text('Pickup'), findsOneWidget);
    expect(find.text('Destination'), findsOneWidget);
    expect(find.text('Confirm destination'), findsOneWidget);
    expect(find.textContaining('not your location'), findsOneWidget);
    expect(find.textContaining('Rs '), findsNothing);
  });

  testWidgets('filled destinations advance to category review', (tester) async {
    await tester.pumpWidget(_wrap(const RideRequestView()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Gulberg III');
    await tester.enterText(find.byType(TextField).at(1), 'Liberty Market');
    await tester.pump();

    await tester.tap(find.text('Confirm destination'));
    await tester.pumpAndSettle();

    expect(find.text('Select a ride'), findsOneWidget);
    expect(find.text('Easy'), findsWidgets);
    expect(find.text('Price TBD'), findsWidgets);
    expect(find.text('Request Easy'), findsOneWidget);
    expect(find.textContaining('Rs '), findsNothing);
  });

  testWidgets('request CTA shows pricing unavailable — no createRide', (
    tester,
  ) async {
    final createRide = MockCreateRideUseCase();
    await tester.pumpWidget(
      _wrap(
        const RideRequestView(),
        overrides: [
          createRideUseCaseProvider.overrideWithValue(createRide),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'A');
    await tester.enterText(find.byType(TextField).at(1), 'B');
    await tester.pump();
    await tester.tap(find.text('Confirm destination'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Request Easy'));
    await tester.pumpAndSettle();

    expect(find.text('Pricing unavailable'), findsOneWidget);
    expect(find.textContaining('Pricing isn\'t available'), findsOneWidget);
    verifyNever(
      () => createRide(
        body: any(named: 'body'),
        operationKey: any(named: 'operationKey'),
      ),
    );
  });

  testWidgets('category selection updates request CTA label', (tester) async {
    await tester.pumpWidget(_wrap(const RideRequestView()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'A');
    await tester.enterText(find.byType(TextField).at(1), 'B');
    await tester.pump();
    await tester.tap(find.text('Confirm destination'));
    await tester.pumpAndSettle();

    expect(find.text('Request Easy'), findsOneWidget);

    // Zip is first in the list — safely above the sticky CTA.
    await tester.ensureVisible(find.text('Zip'));
    await tester.tap(find.text('Zip'));
    await tester.pumpAndSettle();
    expect(find.text('Request Zip'), findsOneWidget);
  });

  testWidgets('created view links to offers honestly', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const RideRequestCreatedView(
          rideId: 'ride-abcdefgh',
          serverState: 'SEARCHING',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Request created'), findsOneWidget);
    expect(find.text('View offers'), findsOneWidget);
    expect(find.textContaining('Finding drivers'), findsNothing);
    expect(find.text('SEARCHING'), findsOneWidget);
  });

  testWidgets('responsive compose at 320 and 1.3x', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const RideRequestView(),
        size: const Size(320, 568),
        textScale: 1.3,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Where to?'), findsOneWidget);
  });

  testWidgets('tablet compose has no overflow', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const RideRequestView(),
        size: const Size(768, 1024),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('successful create navigates to offers inbox', (tester) async {
    final createRide = MockCreateRideUseCase();
    when(
      () => createRide(
        body: any(named: 'body'),
        operationKey: any(named: 'operationKey'),
      ),
    ).thenAnswer(
      (_) async => const Ride(
        rideId: 'ride-nav-001',
        passengerId: 'p1',
        state: 'SEARCHING',
        version: 1,
        requestVersion: 1,
        category: 'easy',
        serviceType: 'ride',
        pickup: LatLngPoint(lat: 1, lng: 2),
        destination: LatLngPoint(lat: 3, lng: 4),
        pricingSnapshotId: 'snap-1',
        recommendedFareMinor: 100,
        passengerOfferMinor: 100,
        paymentMethod: 'CASH',
        passengerCount: 1,
        expiresAt: '2099-01-01T00:00:00.000Z',
        createdAt: '2026-01-01T00:00:00.000Z',
        updatedAt: '2026-01-01T00:00:00.000Z',
      ),
    );

    final getRide = MockGetRideUseCase();
    final listOffers = MockListOffersUseCase();
    when(() => getRide(any())).thenAnswer(
      (_) async => const Ride(
        rideId: 'ride-nav-001',
        passengerId: 'p1',
        state: 'SEARCHING',
        version: 1,
        requestVersion: 1,
        category: 'easy',
        serviceType: 'ride',
        pickup: LatLngPoint(lat: 1, lng: 2, address: 'A'),
        destination: LatLngPoint(lat: 3, lng: 4, address: 'B'),
        pricingSnapshotId: 'snap-1',
        recommendedFareMinor: 100,
        passengerOfferMinor: 100,
        paymentMethod: 'CASH',
        passengerCount: 1,
        expiresAt: '2099-01-01T00:00:00.000Z',
        createdAt: '2026-01-01T00:00:00.000Z',
        updatedAt: '2026-01-01T00:00:00.000Z',
      ),
    );
    when(() => listOffers(any())).thenAnswer((_) async => []);

    final router = GoRouter(
      initialLocation: AppRoutes.rideRequest,
      routes: [
        GoRoute(
          path: AppRoutes.rideRequest,
          builder: (_, __) => const RideRequestView(),
        ),
        GoRoute(
          path: AppRoutes.offersInbox,
          builder: (context, state) => OffersInboxView(
            rideId: state.pathParameters['rideId'] ?? '',
          ),
        ),
        GoRoute(
          path: AppRoutes.home,
          builder: (_, __) => const SizedBox.shrink(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          createRideUseCaseProvider.overrideWithValue(createRide),
          getRideUseCaseProvider.overrideWithValue(getRide),
          listOffersUseCaseProvider.overrideWithValue(listOffers),
          offerPollingPolicyProvider.overrideWithValue(
            const OfferPollingPolicy(
              intervals: [Duration(days: 1)],
              maxLifetime: Duration(days: 1),
            ),
          ),
          rideRequestCapabilitiesProvider.overrideWithValue(
            const RideRequestCapabilities(
              pricingSnapshotId: 'snap-1',
              passengerOfferMinor: 100,
              resolvedPickup: LatLngPoint(lat: 1, lng: 2),
              resolvedDestination: LatLngPoint(lat: 3, lng: 4),
            ),
          ),
        ],
        child: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: MaterialApp.router(
            theme: OraTheme.dark(),
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'A');
    await tester.enterText(find.byType(TextField).at(1), 'B');
    await tester.pump();
    await tester.tap(find.text('Confirm destination'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request Easy'));
    await tester.pumpAndSettle();

    expect(find.text('Offers'), findsWidgets);
    expect(find.text('Waiting for offers'), findsOneWidget);
  });
}
