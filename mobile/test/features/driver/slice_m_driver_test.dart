import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/app/router/route_guards.dart';
import 'package:ora/app/router/routes.dart';
import 'package:ora/core/errors/app_failure.dart';
import 'package:ora/core/errors/failure_mapper.dart';
import 'package:ora/features/auth/domain/entities/user_profile.dart';
import 'package:ora/features/auth/presentation/view_models/auth_state_notifier.dart';
import 'package:ora/features/auth/presentation/view_models/auth_view_model.dart';
import 'package:ora/features/auth/presentation/view_models/auth_view_state.dart';
import 'package:ora/features/auth/presentation/view_models/session_user_profile.dart';
import 'package:ora/features/driver/presentation/open_ride_display.dart';
import 'package:ora/features/driver/presentation/view_models/driver_assigned_rides_view_model.dart';
import 'package:ora/features/driver/presentation/view_models/driver_open_rides_view_model.dart';
import 'package:ora/features/driver/presentation/views/driver_open_rides_view.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';
import 'package:ora/features/ride/domain/use_cases/ride_use_cases.dart';
import 'package:ora/features/ride/presentation/offers/offer_display.dart';

import '../../helpers/in_memory_idempotency_nonce_store.dart';

class MockListOpenRidesUseCase extends Mock implements ListOpenRidesUseCase {}

class MockListRidesUseCase extends Mock implements ListRidesUseCase {}

class MockCreateOfferUseCase extends Mock implements CreateOfferUseCase {}

class _PassthroughFailureMapper extends FailureMapper {
  const _PassthroughFailureMapper();

  @override
  AppFailure fromException(Object error, [StackTrace? stackTrace]) {
    if (error is AppFailure) return error;
    return AppFailure.unknown(message: error.toString());
  }
}

class _FixedAuthStateNotifier extends AuthStateNotifier {
  _FixedAuthStateNotifier(this._status);

  final AuthStatus _status;

  @override
  AuthStatus build() => _status;
}

class _FixedAuthViewModel extends AuthViewModel {
  _FixedAuthViewModel(this._flow);

  final AuthFlowState _flow;

  @override
  AuthFlowState build() => _flow;
}

OpenRide _openRide({
  String id = 'open-1',
  String state = 'SEARCHING',
  int requestVersion = 1,
  int passengerOfferMinor = 25000,
  double? distanceKm = 5.2,
  int? estimatedDurationMin = 12,
  String? pickupAddress = 'Pickup A',
  String? destAddress = 'Dest B',
}) {
  return OpenRide(
    rideId: id,
    state: state,
    requestVersion: requestVersion,
    category: 'economy',
    serviceType: 'ride',
    pickup: LatLngPoint(lat: 24.86, lng: 67.0, address: pickupAddress),
    destination: LatLngPoint(lat: 24.9, lng: 67.1, address: destAddress),
    recommendedFareMinor: 25000,
    passengerOfferMinor: passengerOfferMinor,
    paymentMethod: 'CASH',
    passengerCount: 1,
    distanceKm: distanceKm,
    estimatedDurationMin: estimatedDurationMin,
    expiresAt: '2099-01-01T00:00:00.000Z',
    createdAt: '2026-01-01T00:00:00.000Z',
  );
}

RideOffer _offer({
  String rideId = 'open-1',
  String offerId = 'offer-1',
  int amountMinor = 25000,
}) {
  return RideOffer(
    offerId: offerId,
    rideId: rideId,
    driverId: 'driver-1',
    amountMinor: amountMinor,
    currency: 'PKR',
    type: 'DRIVER_COUNTEROFFER',
    status: 'PENDING',
    requestVersion: 1,
    expiresAt: '2099-01-01T00:00:00.000Z',
    createdAt: '2026-01-01T00:00:00.000Z',
  );
}

Ride _assignedRide({String id = 'assigned-1'}) {
  return Ride(
    rideId: id,
    passengerId: 'p1',
    assignedDriverId: 'driver-1',
    state: 'DRIVER_ASSIGNED',
    version: 2,
    requestVersion: 1,
    category: 'economy',
    serviceType: 'ride',
    pickup: const LatLngPoint(lat: 24.8, lng: 67.0, address: 'A'),
    destination: const LatLngPoint(lat: 24.9, lng: 67.1, address: 'B'),
    pricingSnapshotId: 'snap-1',
    recommendedFareMinor: 20000,
    passengerOfferMinor: 20000,
    paymentMethod: 'CASH',
    passengerCount: 1,
    expiresAt: '2099-01-01T00:00:00.000Z',
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
  });

  group('open ride display honesty', () {
    test('open-ride fares use canonical PKR formatter (verified Ora contract)',
        () {
      expect(oraRideMoneyCurrencyCode, 'PKR');
      expect(formatOpenRideFareMinor(25000), 'Rs 250');
      expect(formatOpenRideFareMinor(25050), 'Rs 250.50');
      // Same path as offer cards — not a bespoke ÷100 string.
      expect(
        formatOpenRideFareMinor(25000),
        formatOfferAmountMinor(25000, oraRideMoneyCurrencyCode),
      );
    });

    test('does not invent a non-contract currency code', () {
      expect(oraRideMoneyCurrencyCode, isNot(equals('USD')));
      expect(formatOpenRideFareMinor(100), startsWith('Rs '));
    });

    test('omits distance/duration when null — no local fabrication', () {
      expect(formatOpenRideDistanceKm(null), isNull);
      expect(formatOpenRideDurationMin(null), isNull);
      expect(formatOpenRideDistanceKm(5), '5 km (server)');
    });

    test('location falls back to coordinates, not invented place names', () {
      const point = LatLngPoint(lat: 24.86, lng: 67.0);
      final label = openRideLocationLabel(point, fallback: 'Pickup');
      expect(label, contains('24.8600'));
      expect(label.toLowerCase(), isNot(contains('karachi')));
    });
  });

  group('approved-driver discovery gate', () {
    Future<String> resolve(
      WidgetTester tester, {
      required String requested,
      UserProfile? profile,
    }) async {
      final container = ProviderContainer(
        overrides: [
          authStateNotifierProvider.overrideWith(
            () => _FixedAuthStateNotifier(AuthStatus.authenticatedReady),
          ),
          authViewModelProvider.overrideWith(
            () => _FixedAuthViewModel(const AuthFlowIdle()),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(sessionUserProfileProvider.notifier).setProfile(profile);

      final localRouterProvider = Provider<GoRouter>((ref) {
        final guard = AuthRouteGuard(ref);
        return GoRouter(
          initialLocation: requested,
          redirect: (context, state) => guard.redirect(state),
          routes: [
            for (final path in <String>[
              AppRoutes.splash,
              AppRoutes.home,
              AppRoutes.driverHome,
              AppRoutes.driverRides,
              AppRoutes.driverRide,
              AppRoutes.driverDirectOffer,
            ])
              GoRoute(
                path: path,
                builder: (context, state) => const SizedBox.shrink(),
              ),
          ],
        );
      });

      final router = container.read(localRouterProvider);
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      return router.routerDelegate.currentConfiguration.uri.path;
    }

    testWidgets('approved driver can access /driver', (tester) async {
      expect(
        await resolve(
          tester,
          requested: AppRoutes.driverHome,
          profile: const UserProfile(
            uid: 'd1',
            phoneNumber: '+92',
            role: 'driver',
            driverStatus: 'approved',
            profileComplete: true,
          ),
        ),
        AppRoutes.driverHome,
      );
    });

    testWidgets('non-approved driver blocked from /driver', (tester) async {
      expect(
        await resolve(
          tester,
          requested: AppRoutes.driverHome,
          profile: const UserProfile(
            uid: 'd1',
            phoneNumber: '+92',
            role: 'driver',
            driverStatus: 'pending',
            profileComplete: true,
          ),
        ),
        AppRoutes.home,
      );
    });

    testWidgets('passenger blocked from /driver', (tester) async {
      expect(
        await resolve(
          tester,
          requested: AppRoutes.driverHome,
          profile: const UserProfile(
            uid: 'p1',
            phoneNumber: '+92',
            role: 'passenger',
            driverStatus: 'none',
            profileComplete: true,
          ),
        ),
        AppRoutes.home,
      );
    });
  });

  group('DriverOpenRidesViewModel', () {
    late MockListOpenRidesUseCase listOpen;
    late MockCreateOfferUseCase createOffer;
    late InMemoryIdempotencyNonceStore nonceStore;

    ProviderContainer container() {
      return ProviderContainer(
        overrides: [
          listOpenRidesUseCaseProvider.overrideWithValue(listOpen),
          createOfferUseCaseProvider.overrideWithValue(createOffer),
          idempotencyNonceStoreProvider.overrideWithValue(nonceStore),
          failureMapperProvider.overrideWithValue(
            const _PassthroughFailureMapper(),
          ),
        ],
      );
    }

    setUp(() {
      listOpen = MockListOpenRidesUseCase();
      createOffer = MockCreateOfferUseCase();
      nonceStore = InMemoryIdempotencyNonceStore();
    });

    test('first page loads via use case path', () async {
      when(
        () => listOpen(
          limit: any(named: 'limit'),
          cursor: any(named: 'cursor'),
        ),
      ).thenAnswer(
        (_) async => OpenRideListPage(rides: [_openRide()], nextCursor: null),
      );

      final c = container();
      addTearDown(c.dispose);
      c.listen(driverOpenRidesViewModelProvider, (_, __) {});
      final vm = c.read(driverOpenRidesViewModelProvider.notifier);
      await vm.loadInitial();

      final state = c.read(driverOpenRidesViewModelProvider);
      expect(state.phase, DriverOpenRidesPhase.ready);
      expect(state.rides.single.rideId, 'open-1');
      expect(state.rides.single.requestVersion, 1);
      verify(
        () => listOpen(limit: openRidesDefaultLimit, cursor: null),
      ).called(1);
    });

    test('maps DTO fields without prohibited passenger identity', () async {
      when(
        () => listOpen(
          limit: any(named: 'limit'),
          cursor: any(named: 'cursor'),
        ),
      ).thenAnswer(
        (_) async => OpenRideListPage(
          rides: [_openRide(requestVersion: 3)],
          nextCursor: null,
        ),
      );

      final c = container();
      addTearDown(c.dispose);
      c.listen(driverOpenRidesViewModelProvider, (_, __) {});
      await c.read(driverOpenRidesViewModelProvider.notifier).loadInitial();
      final ride = c.read(driverOpenRidesViewModelProvider).rides.single;
      expect(ride.requestVersion, 3);
      expect(ride.passengerOfferMinor, 25000);
      // OpenRide has no passengerId field — compile-time + runtime shape check.
      expect(ride.toString(), isNot(contains('passengerId')));
    });

    test('empty state', () async {
      when(
        () => listOpen(
          limit: any(named: 'limit'),
          cursor: any(named: 'cursor'),
        ),
      ).thenAnswer(
        (_) async => const OpenRideListPage(rides: [], nextCursor: null),
      );

      final c = container();
      addTearDown(c.dispose);
      c.listen(driverOpenRidesViewModelProvider, (_, __) {});
      await c.read(driverOpenRidesViewModelProvider.notifier).loadInitial();
      expect(
        c.read(driverOpenRidesViewModelProvider).phase,
        DriverOpenRidesPhase.empty,
      );
    });

    test('error state', () async {
      when(
        () => listOpen(
          limit: any(named: 'limit'),
          cursor: any(named: 'cursor'),
        ),
      ).thenThrow(const AppFailure.network(message: 'offline'));

      final c = container();
      addTearDown(c.dispose);
      c.listen(driverOpenRidesViewModelProvider, (_, __) {});
      await c.read(driverOpenRidesViewModelProvider.notifier).loadInitial();
      final state = c.read(driverOpenRidesViewModelProvider);
      expect(state.phase, DriverOpenRidesPhase.fatalError);
      expect(state.errorMessage, 'offline');
    });

    test('refresh resets cursor and reloads first page', () async {
      var calls = 0;
      when(
        () => listOpen(
          limit: any(named: 'limit'),
          cursor: any(named: 'cursor'),
        ),
      ).thenAnswer((invocation) async {
        calls += 1;
        final cursor = invocation.namedArguments[#cursor] as String?;
        if (calls == 1) {
          return OpenRideListPage(
            rides: [_openRide(id: 'a')],
            nextCursor: 'cursor-1',
          );
        }
        expect(cursor, isNull);
        return OpenRideListPage(
          rides: [_openRide(id: 'b')],
          nextCursor: null,
        );
      });

      final c = container();
      addTearDown(c.dispose);
      c.listen(driverOpenRidesViewModelProvider, (_, __) {});
      final vm = c.read(driverOpenRidesViewModelProvider.notifier);
      await vm.loadInitial();
      expect(c.read(driverOpenRidesViewModelProvider).hasMore, isTrue);
      await vm.refresh();
      final state = c.read(driverOpenRidesViewModelProvider);
      expect(state.rides.single.rideId, 'b');
      expect(state.nextCursor, isNull);
    });

    test('cursor pagination appends without duplicates', () async {
      when(
        () => listOpen(limit: any(named: 'limit'), cursor: null),
      ).thenAnswer(
        (_) async => OpenRideListPage(
          rides: [_openRide(id: 'a'), _openRide(id: 'b')],
          nextCursor: 'c1',
        ),
      );
      when(
        () => listOpen(limit: any(named: 'limit'), cursor: 'c1'),
      ).thenAnswer(
        (_) async => OpenRideListPage(
          rides: [_openRide(id: 'b'), _openRide(id: 'c')],
          nextCursor: null,
        ),
      );

      final c = container();
      addTearDown(c.dispose);
      c.listen(driverOpenRidesViewModelProvider, (_, __) {});
      final vm = c.read(driverOpenRidesViewModelProvider.notifier);
      await vm.loadInitial();
      await vm.loadMore();
      final ids =
          c.read(driverOpenRidesViewModelProvider).rides.map((r) => r.rideId);
      expect(ids.toList(), ['a', 'b', 'c']);
    });

    test('duplicate pagination request prevented', () async {
      final gate = Completer<OpenRideListPage>();
      when(
        () => listOpen(limit: any(named: 'limit'), cursor: null),
      ).thenAnswer(
        (_) async => OpenRideListPage(
          rides: [_openRide(id: 'a')],
          nextCursor: 'c1',
        ),
      );
      when(
        () => listOpen(limit: any(named: 'limit'), cursor: 'c1'),
      ).thenAnswer((_) => gate.future);

      final c = container();
      addTearDown(c.dispose);
      c.listen(driverOpenRidesViewModelProvider, (_, __) {});
      final vm = c.read(driverOpenRidesViewModelProvider.notifier);
      await vm.loadInitial();
      final first = vm.loadMore();
      final second = vm.loadMore();
      gate.complete(
        OpenRideListPage(rides: [_openRide(id: 'b')], nextCursor: null),
      );
      await Future.wait([first, second]);
      verify(
        () => listOpen(limit: any(named: 'limit'), cursor: 'c1'),
      ).called(1);
    });

    test('offer uses rideId + requestVersion; duplicate submit blocked',
        () async {
      when(
        () => listOpen(
          limit: any(named: 'limit'),
          cursor: any(named: 'cursor'),
        ),
      ).thenAnswer(
        (_) async => OpenRideListPage(
          rides: [_openRide(id: 'open-9', requestVersion: 7)],
          nextCursor: null,
        ),
      );
      final gate = Completer<RideOffer>();
      when(
        () => createOffer(
          rideId: any(named: 'rideId'),
          body: any(named: 'body'),
          operationKey: any(named: 'operationKey'),
        ),
      ).thenAnswer((_) => gate.future);

      final c = container();
      addTearDown(c.dispose);
      c.listen(driverOpenRidesViewModelProvider, (_, __) {});
      final vm = c.read(driverOpenRidesViewModelProvider.notifier);
      await vm.loadInitial();
      final ride = c.read(driverOpenRidesViewModelProvider).rides.single;

      final first = vm.submitOffer(
        ride: ride,
        type: 'DRIVER_COUNTEROFFER',
        amountMinor: 26000,
      );
      final second = vm.submitOffer(
        ride: ride,
        type: 'DRIVER_COUNTEROFFER',
        amountMinor: 27000,
      );
      gate.complete(_offer(rideId: 'open-9', amountMinor: 26000));
      await Future.wait([first, second]);

      final captured = verify(
        () => createOffer(
          rideId: 'open-9',
          body: captureAny(named: 'body'),
          operationKey: any(named: 'operationKey'),
        ),
      ).captured;
      expect(captured, hasLength(1));
      final body = captured.single as Map<String, Object?>;
      expect(body['expectedRequestVersion'], 7);
      expect(body['type'], 'DRIVER_COUNTEROFFER');
      expect(body['amountMinor'], 26000);

      final state = c.read(driverOpenRidesViewModelProvider);
      expect(state.lastCreatedOffer?.offerId, 'offer-1');
      expect(state.offerInfoMessage, isNotNull);
    });

    test('successful offer message uses server offer currency formatter',
        () async {
      when(
        () => listOpen(
          limit: any(named: 'limit'),
          cursor: any(named: 'cursor'),
        ),
      ).thenAnswer(
        (_) async => OpenRideListPage(rides: [_openRide()], nextCursor: null),
      );
      when(
        () => createOffer(
          rideId: any(named: 'rideId'),
          body: any(named: 'body'),
          operationKey: any(named: 'operationKey'),
        ),
      ).thenAnswer(
        (_) async => _offer(amountMinor: 26000),
      );

      final c = container();
      addTearDown(c.dispose);
      c.listen(driverOpenRidesViewModelProvider, (_, __) {});
      final vm = c.read(driverOpenRidesViewModelProvider.notifier);
      await vm.loadInitial();
      await vm.submitOffer(
        ride: c.read(driverOpenRidesViewModelProvider).rides.single,
        type: 'DRIVER_COUNTEROFFER',
        amountMinor: 26000,
      );
      final msg = c.read(driverOpenRidesViewModelProvider).offerInfoMessage!;
      expect(msg, contains(formatOfferAmountMinor(26000, 'PKR')));
      expect(msg, isNot(contains('26000 minor')));
    });

    test('PASSENGER_PRICE_ACCEPTED path', () async {
      when(
        () => listOpen(
          limit: any(named: 'limit'),
          cursor: any(named: 'cursor'),
        ),
      ).thenAnswer(
        (_) async => OpenRideListPage(rides: [_openRide()], nextCursor: null),
      );
      when(
        () => createOffer(
          rideId: any(named: 'rideId'),
          body: any(named: 'body'),
          operationKey: any(named: 'operationKey'),
        ),
      ).thenAnswer((_) async => _offer());

      final c = container();
      addTearDown(c.dispose);
      c.listen(driverOpenRidesViewModelProvider, (_, __) {});
      final vm = c.read(driverOpenRidesViewModelProvider.notifier);
      await vm.loadInitial();
      await vm.submitOffer(
        ride: c.read(driverOpenRidesViewModelProvider).rides.single,
        type: 'PASSENGER_PRICE_ACCEPTED',
        amountMinor: 25000,
      );
      final body = verify(
        () => createOffer(
          rideId: any(named: 'rideId'),
          body: captureAny(named: 'body'),
          operationKey: any(named: 'operationKey'),
        ),
      ).captured.single as Map<String, Object?>;
      expect(body['type'], 'PASSENGER_PRICE_ACCEPTED');
    });

    test('ALREADY_ASSIGNED removes item and refreshes', () async {
      var calls = 0;
      when(
        () => listOpen(
          limit: any(named: 'limit'),
          cursor: any(named: 'cursor'),
        ),
      ).thenAnswer((_) async {
        calls += 1;
        if (calls == 1) {
          return OpenRideListPage(
            rides: [_openRide(id: 'gone')],
            nextCursor: null,
          );
        }
        return const OpenRideListPage(rides: [], nextCursor: null);
      });
      when(
        () => createOffer(
          rideId: any(named: 'rideId'),
          body: any(named: 'body'),
          operationKey: any(named: 'operationKey'),
        ),
      ).thenThrow(
        const AppFailure.conflict(
          message: 'assigned',
          code: 'ALREADY_ASSIGNED',
        ),
      );

      final c = container();
      addTearDown(c.dispose);
      c.listen(driverOpenRidesViewModelProvider, (_, __) {});
      final vm = c.read(driverOpenRidesViewModelProvider.notifier);
      await vm.loadInitial();
      await vm.submitOffer(
        ride: c.read(driverOpenRidesViewModelProvider).rides.single,
        type: 'DRIVER_COUNTEROFFER',
        amountMinor: 26000,
      );
      await Future<void>.delayed(Duration.zero);
      final state = c.read(driverOpenRidesViewModelProvider);
      expect(state.rides.where((r) => r.rideId == 'gone'), isEmpty);
      expect(state.offerErrorMessage, contains('no longer available'));
    });

    test('STATE_CONFLICT handled as unavailable', () async {
      when(
        () => listOpen(
          limit: any(named: 'limit'),
          cursor: any(named: 'cursor'),
        ),
      ).thenAnswer(
        (_) async => OpenRideListPage(rides: [_openRide()], nextCursor: null),
      );
      when(
        () => createOffer(
          rideId: any(named: 'rideId'),
          body: any(named: 'body'),
          operationKey: any(named: 'operationKey'),
        ),
      ).thenThrow(
        const AppFailure.conflict(
          message: 'expired',
          code: 'STATE_CONFLICT',
        ),
      );

      final c = container();
      addTearDown(c.dispose);
      c.listen(driverOpenRidesViewModelProvider, (_, __) {});
      final vm = c.read(driverOpenRidesViewModelProvider.notifier);
      await vm.loadInitial();
      await vm.submitOffer(
        ride: c.read(driverOpenRidesViewModelProvider).rides.single,
        type: 'DRIVER_COUNTEROFFER',
        amountMinor: 26000,
      );
      expect(
        c.read(driverOpenRidesViewModelProvider).offerErrorMessage,
        contains('no longer available'),
      );
    });

    test('VERSION_CONFLICT handled as unavailable', () async {
      when(
        () => listOpen(
          limit: any(named: 'limit'),
          cursor: any(named: 'cursor'),
        ),
      ).thenAnswer(
        (_) async => OpenRideListPage(rides: [_openRide()], nextCursor: null),
      );
      when(
        () => createOffer(
          rideId: any(named: 'rideId'),
          body: any(named: 'body'),
          operationKey: any(named: 'operationKey'),
        ),
      ).thenThrow(
        const AppFailure.conflict(
          message: 'version',
          code: 'VERSION_CONFLICT',
        ),
      );

      final c = container();
      addTearDown(c.dispose);
      c.listen(driverOpenRidesViewModelProvider, (_, __) {});
      final vm = c.read(driverOpenRidesViewModelProvider.notifier);
      await vm.loadInitial();
      await vm.submitOffer(
        ride: c.read(driverOpenRidesViewModelProvider).rides.single,
        type: 'DRIVER_COUNTEROFFER',
        amountMinor: 26000,
      );
      expect(
        c.read(driverOpenRidesViewModelProvider).offerErrorMessage,
        contains('no longer available'),
      );
    });

    test('OFFER_STALE / validation prompts refresh', () async {
      when(
        () => listOpen(
          limit: any(named: 'limit'),
          cursor: any(named: 'cursor'),
        ),
      ).thenAnswer(
        (_) async => OpenRideListPage(rides: [_openRide()], nextCursor: null),
      );
      when(
        () => createOffer(
          rideId: any(named: 'rideId'),
          body: any(named: 'body'),
          operationKey: any(named: 'operationKey'),
        ),
      ).thenThrow(
        const AppFailure.validation(message: 'Offer requestVersion mismatch'),
      );

      final c = container();
      addTearDown(c.dispose);
      c.listen(driverOpenRidesViewModelProvider, (_, __) {});
      final vm = c.read(driverOpenRidesViewModelProvider.notifier);
      await vm.loadInitial();
      await vm.submitOffer(
        ride: c.read(driverOpenRidesViewModelProvider).rides.single,
        type: 'DRIVER_COUNTEROFFER',
        amountMinor: 26000,
      );
      final msg = c.read(driverOpenRidesViewModelProvider).offerErrorMessage!;
      expect(msg, contains('refresh'));
      expect(
        c.read(driverOpenRidesViewModelProvider).rides,
        isNotEmpty,
      );
    });

    test('dispose-safe: superseded load is ignored', () async {
      final slow = Completer<OpenRideListPage>();
      var call = 0;
      when(
        () => listOpen(
          limit: any(named: 'limit'),
          cursor: any(named: 'cursor'),
        ),
      ).thenAnswer((_) async {
        call += 1;
        if (call == 1) return slow.future;
        return OpenRideListPage(
          rides: [_openRide(id: 'fresh')],
          nextCursor: null,
        );
      });

      final c = container();
      addTearDown(c.dispose);
      c.listen(driverOpenRidesViewModelProvider, (_, __) {});
      final vm = c.read(driverOpenRidesViewModelProvider.notifier);
      final first = vm.loadInitial();
      await vm.loadInitial();
      slow.complete(
        OpenRideListPage(rides: [_openRide(id: 'stale')], nextCursor: null),
      );
      await first;
      expect(
        c.read(driverOpenRidesViewModelProvider).rides.single.rideId,
        'fresh',
      );
    });
  });

  group('assigned-driver + passenger regression', () {
    test('assigned rides list still uses ListRidesUseCase only', () async {
      final listRides = MockListRidesUseCase();
      when(
        () => listRides(
          limit: any(named: 'limit'),
          cursor: any(named: 'cursor'),
          status: any(named: 'status'),
          serviceType: any(named: 'serviceType'),
        ),
      ).thenAnswer(
        (_) async => RideListPage(rides: [_assignedRide()], nextCursor: null),
      );

      final c = ProviderContainer(
        overrides: [
          listRidesUseCaseProvider.overrideWithValue(listRides),
          failureMapperProvider.overrideWithValue(
            const _PassthroughFailureMapper(),
          ),
        ],
      );
      addTearDown(c.dispose);
      c.listen(driverAssignedRidesViewModelProvider, (_, __) {});
      await c.read(driverAssignedRidesViewModelProvider.notifier).loadInitial();
      expect(
        c.read(driverAssignedRidesViewModelProvider).rides.single.rideId,
        'assigned-1',
      );
      verify(
        () => listRides(
          limit: any(named: 'limit'),
          cursor: null,
          status: 'all',
          serviceType: null,
        ),
      ).called(1);
    });
  });

  group('DriverOpenRidesView UI', () {
    testWidgets('empty copy avoids nearby language', (tester) async {
      final listOpen = MockListOpenRidesUseCase();
      when(
        () => listOpen(
          limit: any(named: 'limit'),
          cursor: any(named: 'cursor'),
        ),
      ).thenAnswer(
        (_) async => const OpenRideListPage(rides: [], nextCursor: null),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            listOpenRidesUseCaseProvider.overrideWithValue(listOpen),
            createOfferUseCaseProvider.overrideWithValue(MockCreateOfferUseCase()),
            idempotencyNonceStoreProvider.overrideWithValue(
              InMemoryIdempotencyNonceStore(),
            ),
            failureMapperProvider.overrideWithValue(
              const _PassthroughFailureMapper(),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: DriverOpenRidesView(active: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('No open ride requests'), findsOneWidget);
      expect(find.textContaining('nearby'), findsNothing);
      expect(find.textContaining('near you'), findsNothing);
    });

    testWidgets('card does not show passengerId or fabricated ETA',
        (tester) async {
      final listOpen = MockListOpenRidesUseCase();
      when(
        () => listOpen(
          limit: any(named: 'limit'),
          cursor: any(named: 'cursor'),
        ),
      ).thenAnswer(
        (_) async => OpenRideListPage(
          rides: [
            _openRide(distanceKm: null, estimatedDurationMin: null),
          ],
          nextCursor: null,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            listOpenRidesUseCaseProvider.overrideWithValue(listOpen),
            createOfferUseCaseProvider
                .overrideWithValue(MockCreateOfferUseCase()),
            idempotencyNonceStoreProvider.overrideWithValue(
              InMemoryIdempotencyNonceStore(),
            ),
            failureMapperProvider.overrideWithValue(
              const _PassthroughFailureMapper(),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: DriverOpenRidesView(active: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('passengerId'), findsNothing);
      expect(find.textContaining('ETA'), findsNothing);
      expect(find.textContaining('Pickup A'), findsOneWidget);
      expect(find.textContaining('Respond'), findsOneWidget);
    });
  });
}
