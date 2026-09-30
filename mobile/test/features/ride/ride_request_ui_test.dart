import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/app/router/routes.dart';
import 'package:ora/app/theme/theme.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';
import 'package:ora/features/ride/domain/models/resolved_passenger_location.dart';
import 'package:ora/features/ride/domain/ports/device_location_port.dart';
import 'package:ora/features/ride/domain/ports/place_search_port.dart';
import 'package:ora/features/ride/domain/ports/pricing_estimate_port.dart';
import 'package:ora/features/ride/domain/use_cases/ride_use_cases.dart';
import 'package:ora/features/ride/presentation/view_models/offers_inbox_view_model.dart';
import 'package:ora/features/ride/presentation/view_models/ride_request_view_model.dart';
import 'package:ora/features/ride/presentation/views/offers_inbox_view.dart';
import 'package:ora/features/ride/presentation/views/ride_request_created_view.dart';
import 'package:ora/features/ride/presentation/views/ride_request_view.dart';

class MockCreateRideUseCase extends Mock implements CreateRideUseCase {}

class MockGetRideUseCase extends Mock implements GetRideUseCase {}

class MockListOffersUseCase extends Mock implements ListOffersUseCase {}

class _UiPlaceSearch implements PlaceSearchPort {
  @override
  Future<List<PlaceSuggestion>> autocomplete({
    required String query,
    required String sessionToken,
  }) async {
    final q = query.trim().toLowerCase();
    if (q.contains('gulberg') || q == 'a') {
      return const [
        PlaceSuggestion(
          placeId: 'p1',
          primaryText: 'Gulberg III',
          secondaryText: 'Lahore',
        ),
      ];
    }
    if (q.contains('liberty') || q == 'b') {
      return const [
        PlaceSuggestion(
          placeId: 'p2',
          primaryText: 'Liberty Market',
          secondaryText: 'Lahore',
        ),
      ];
    }
    return const [];
  }

  @override
  Future<ResolvedPassengerLocation> resolvePlace({
    required String placeId,
    required String sessionToken,
  }) async {
    if (placeId == 'p1') {
      return const ResolvedPassengerLocation(
        lat: 31.51,
        lng: 74.35,
        address: 'Gulberg III, Lahore',
        placeId: 'p1',
        source: PassengerLocationSource.place,
      );
    }
    return const ResolvedPassengerLocation(
      lat: 31.52,
      lng: 74.34,
      address: 'Liberty Market, Lahore',
      placeId: 'p2',
      source: PassengerLocationSource.place,
    );
  }
}

class _UiDeviceLocation implements DeviceLocationPort {
  @override
  Future<ResolvedPassengerLocation> getCurrentLocation() async {
    return const ResolvedPassengerLocation(
      lat: 31.46,
      lng: 74.26,
      address: 'Current location',
      source: PassengerLocationSource.gps,
    );
  }
}

class _UiPricingSuccess implements PricingEstimatePort {
  @override
  Future<PricingEstimate> estimate(PricingEstimateRequest request) async {
    return PricingEstimate(
      pricingSnapshotId: 'ps_ui_test',
      recommendedFareMinor: 42000,
      offerBoundMinMinor: 30000,
      offerBoundMaxMinor: 75000,
      currency: 'PKR',
      pricingRulesVersion: 'v1',
      computedAt: '2026-01-01T00:00:00.000Z',
      expiresAt: '2099-01-01T00:00:00.000Z',
      distanceKm: 3.6,
      durationMin: 12,
      category: request.category,
    );
  }
}

class _UiPricingFail implements PricingEstimatePort {
  @override
  Future<PricingEstimate> estimate(PricingEstimateRequest request) async {
    throw const PricingClientException(
      PricingFailureKind.pricingUnavailable,
      'Pricing isn\'t available right now. Please try again later.',
    );
  }
}

Widget _wrap(
  Widget child, {
  List<Override> overrides = const [],
  Size size = const Size(390, 844),
  double textScale = 1,
  EdgeInsets viewInsets = EdgeInsets.zero,
  PricingEstimatePort? pricing,
}) {
  return ProviderScope(
    overrides: [
      placeSearchPortProvider.overrideWithValue(_UiPlaceSearch()),
      deviceLocationPortProvider.overrideWithValue(_UiDeviceLocation()),
      pricingEstimatePortProvider.overrideWithValue(
        pricing ?? _UiPricingFail(),
      ),
      ...overrides,
    ],
    child: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
        viewInsets: viewInsets,
      ),
      child: MaterialApp(
        theme: OraTheme.dark(),
        home: child,
      ),
    ),
  );
}

Future<void> _confirmTrip(WidgetTester tester) async {
  final element = tester.element(find.byType(RideRequestView));
  final container = ProviderScope.containerOf(element);
  final vm = container.read(rideRequestViewModelProvider.notifier);

  await vm.selectPlaceSuggestion(
    field: LocationField.pickup,
    suggestion: const PlaceSuggestion(
      placeId: 'p1',
      primaryText: 'Gulberg III',
      secondaryText: 'Lahore',
    ),
  );
  await tester.pumpAndSettle();
  vm.confirmPickup();
  await tester.pumpAndSettle();

  await vm.selectPlaceSuggestion(
    field: LocationField.destination,
    suggestion: const PlaceSuggestion(
      placeId: 'p2',
      primaryText: 'Liberty Market',
      secondaryText: 'Lahore',
    ),
  );
  await tester.pumpAndSettle();
  vm.confirmDestination();
  await tester.pumpAndSettle();
  await vm.requestPricingEstimate(force: true);
  await tester.pumpAndSettle();

  expect(find.text('Continue'), findsOneWidget);
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
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
    expect(find.text('Use current location'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.textContaining('Search and GPS'), findsOneWidget);
    expect(find.textContaining('Rs '), findsNothing);
  });

  testWidgets(
    'destination proposal is visible and tappable after place resolve',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          const RideRequestView(),
          size: const Size(390, 700),
          viewInsets: const EdgeInsets.only(bottom: 280),
        ),
      );
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(RideRequestView));
      final container = ProviderScope.containerOf(element);
      final vm = container.read(rideRequestViewModelProvider.notifier);

      await vm.useCurrentLocationForPickup();
      await tester.pumpAndSettle();
      vm.confirmPickup();
      await tester.pumpAndSettle();

      await vm.selectPlaceSuggestion(
        field: LocationField.destination,
        suggestion: const PlaceSuggestion(
          placeId: 'p2',
          primaryText: 'Liberty Market',
          secondaryText: 'Lahore',
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(OraMotion.fade);

      final confirmDestination = find.text('Confirm destination');
      expect(confirmDestination, findsOneWidget);
      expect(find.textContaining('Place search ·'), findsOneWidget);

      expect(
        container.read(rideRequestViewModelProvider).proposedDestination,
        isNotNull,
      );

      final confirmRect = tester.getRect(confirmDestination);
      final continueRect = tester.getRect(find.text('Continue'));
      expect(confirmRect.bottom, lessThan(continueRect.top));

      expect(
        tester.getSemantics(confirmDestination).hasFlag(SemanticsFlag.isButton),
        isTrue,
      );

      await tester.tap(confirmDestination);
      await tester.pumpAndSettle();

      final state = container.read(rideRequestViewModelProvider);
      expect(state.hasConfirmedDestination, isTrue);
      expect(state.canAdvanceToReview, isTrue);
    },
  );

  testWidgets('search suggestions appear after debounce', (tester) async {
    await tester.pumpWidget(_wrap(const RideRequestView()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Gulberg');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Gulberg III'), findsWidgets);
    expect(find.text('Use current location'), findsOneWidget);
  });

  testWidgets('text alone does not open review', (tester) async {
    await tester.pumpWidget(_wrap(const RideRequestView()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Gulberg III');
    await tester.enterText(find.byType(TextField).at(1), 'Liberty Market');
    await tester.pump();
    expect(find.text('Continue'), findsOneWidget);
    // Disabled CTA — tapping should not open review.
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Select a ride'), findsNothing);
  });

  testWidgets('confirmed places advance to category review with pricing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const RideRequestView(), pricing: _UiPricingSuccess()),
    );
    await tester.pumpAndSettle();
    await _confirmTrip(tester);

    expect(find.text('Select a ride'), findsOneWidget);
    expect(find.text('Request Easy'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Estimated fare'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Rs 420'), findsWidgets);
    expect(find.textContaining('Offer range'), findsOneWidget);
    expect(find.textContaining('3.6 km'), findsOneWidget);
    expect(find.textContaining('12 min'), findsOneWidget);
    expect(find.textContaining('confirmed'), findsWidgets);
  });

  testWidgets('request CTA shows pricing unavailable — no createRide', (
    tester,
  ) async {
    final createRide = MockCreateRideUseCase();
    await tester.pumpWidget(
      _wrap(
        const RideRequestView(),
        pricing: _UiPricingFail(),
        overrides: [
          createRideUseCaseProvider.overrideWithValue(createRide),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await _confirmTrip(tester);

    expect(find.text('Select a ride'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Retry pricing'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Retry pricing'), findsOneWidget);
    // CTA disabled without usable pricing.
    final request = find.text('Request Easy');
    expect(request, findsOneWidget);
    await tester.tap(request);
    await tester.pumpAndSettle();

    verifyNever(
      () => createRide(
        body: any(named: 'body'),
        operationKey: any(named: 'operationKey'),
      ),
    );
  });

  testWidgets('category selection updates request CTA label', (tester) async {
    await tester.pumpWidget(
      _wrap(const RideRequestView(), pricing: _UiPricingSuccess()),
    );
    await tester.pumpAndSettle();
    await _confirmTrip(tester);

    expect(find.text('Request Easy'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Zip'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
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
          placeSearchPortProvider.overrideWithValue(_UiPlaceSearch()),
          deviceLocationPortProvider.overrideWithValue(_UiDeviceLocation()),
          pricingEstimatePortProvider.overrideWithValue(_UiPricingSuccess()),
          createRideUseCaseProvider.overrideWithValue(createRide),
          getRideUseCaseProvider.overrideWithValue(getRide),
          listOffersUseCaseProvider.overrideWithValue(listOffers),
          offerPollingPolicyProvider.overrideWithValue(
            const OfferPollingPolicy(
              intervals: [Duration(days: 1)],
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

    await _confirmTrip(tester);
    await tester.tap(find.text('Request Easy'));
    await tester.pumpAndSettle();

    expect(find.text('Offers'), findsWidgets);
    expect(find.text('Waiting for offers'), findsOneWidget);
  });
}
