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
import 'package:ora/features/driver/presentation/driver_display.dart';
import 'package:ora/features/driver/presentation/view_models/driver_assigned_ride_view_model.dart';
import 'package:ora/features/driver/presentation/view_models/driver_assigned_rides_view_model.dart';
import 'package:ora/features/driver/presentation/view_models/driver_direct_offer_view_model.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';
import 'package:ora/features/ride/domain/use_cases/ride_use_cases.dart';
import 'package:ora/features/ride/presentation/view_models/active_ride_view_model.dart';

import '../../helpers/in_memory_idempotency_nonce_store.dart';

class MockGetRideUseCase extends Mock implements GetRideUseCase {}

class MockListRidesUseCase extends Mock implements ListRidesUseCase {}

class MockMarkEnRouteUseCase extends Mock implements MarkEnRouteUseCase {}

class MockMarkArrivedUseCase extends Mock implements MarkArrivedUseCase {}

class MockStartRideUseCase extends Mock implements StartRideUseCase {}

class MockCompleteRideUseCase extends Mock implements CompleteRideUseCase {}

class MockCancelRideUseCase extends Mock implements CancelRideUseCase {}

class MockCloseRideUseCase extends Mock implements CloseRideUseCase {}

class MockCreateOfferUseCase extends Mock implements CreateOfferUseCase {}

class MockWithdrawOfferUseCase extends Mock implements WithdrawOfferUseCase {}

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

Ride _ride({
  String id = 'ride-1',
  String state = 'DRIVER_ASSIGNED',
  int version = 1,
  String? assignedDriverId = 'driver-1',
}) {
  return Ride(
    rideId: id,
    passengerId: 'p1',
    assignedDriverId: assignedDriverId,
    state: state,
    version: version,
    requestVersion: 1,
    category: 'CITY',
    serviceType: 'CITY',
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

RideOffer _offer({
  String id = 'offer-1',
  String rideId = 'ride-1',
  String status = 'PENDING',
}) {
  return RideOffer(
    offerId: id,
    rideId: rideId,
    driverId: 'driver-1',
    amountMinor: 20000,
    currency: 'PKR',
    type: 'DRIVER_COUNTEROFFER',
    status: status,
    requestVersion: 1,
    expiresAt: '2099-01-01T00:00:00.000Z',
    createdAt: '2026-01-01T00:00:00.000Z',
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
    registerFallbackValue('');
  });

  group('driver_display gates', () {
    test('progression labels and gates', () {
      expect(driverCanEnRoute('DRIVER_ASSIGNED'), isTrue);
      expect(driverCanArrive('DRIVER_EN_ROUTE'), isTrue);
      expect(driverCanStart('DRIVER_ARRIVED'), isTrue);
      expect(driverCanComplete('RIDE_STARTED'), isTrue);
      expect(driverCanEnRoute('DRIVER_EN_ROUTE'), isFalse);
      expect(driverPrimaryActionLabel('DRIVER_ASSIGNED'), 'Mark en route');
      expect(isDriverJobTerminalState('RIDE_CLOSED'), isTrue);
      expect(isDriverJobPollingState('DRIVER_ARRIVED'), isTrue);
    });
  });

  group('UserProfile.isApprovedDriver', () {
    test('only role=driver and driverStatus=approved', () {
      expect(
        const UserProfile(
          uid: 'u1',
          phoneNumber: '+92',
          role: 'driver',
          driverStatus: 'approved',
        ).isApprovedDriver,
        isTrue,
      );
      expect(
        const UserProfile(
          uid: 'u1',
          phoneNumber: '+92',
          role: 'driver',
          driverStatus: 'pending',
        ).isApprovedDriver,
        isFalse,
      );
      expect(
        const UserProfile(
          uid: 'u1',
          phoneNumber: '+92',
          role: 'passenger',
          driverStatus: 'approved',
        ).isApprovedDriver,
        isFalse,
      );
    });
  });

  group('role gate routing', () {
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
      container
          .read(sessionUserProfileProvider.notifier)
          .setProfile(profile);

      final routerProvider = Provider<GoRouter>((ref) {
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

      final router = container.read(routerProvider);
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      return router.routerDelegate.currentConfiguration.uri.path;
    }

    testWidgets('approved driver may open /driver', (tester) async {
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

    testWidgets('passenger is redirected from /driver to home', (tester) async {
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

    testWidgets('pending driver cannot open /driver', (tester) async {
      expect(
        await resolve(
          tester,
          requested: '/driver/rides/ride-1',
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
  });

  group('assigned rides list', () {
    test('loads assigned rides from GET /rides (not marketplace)', () async {
      final list = MockListRidesUseCase();
      when(
        () => list(
          limit: any(named: 'limit'),
          cursor: any(named: 'cursor'),
          status: any(named: 'status'),
          serviceType: any(named: 'serviceType'),
        ),
      ).thenAnswer(
        (_) async => RideListPage(
          rides: [_ride()],
          nextCursor: null,
        ),
      );

      final c = ProviderContainer(
        overrides: [
          listRidesUseCaseProvider.overrideWithValue(list),
          failureMapperProvider
              .overrideWithValue(const _PassthroughFailureMapper()),
        ],
      );
      addTearDown(c.dispose);
      c.listen(driverAssignedRidesViewModelProvider, (_, __) {});
      final vm = c.read(driverAssignedRidesViewModelProvider.notifier);
      await vm.loadInitial();

      final state = c.read(driverAssignedRidesViewModelProvider);
      expect(state.phase, DriverAssignedRidesPhase.ready);
      expect(state.rides, hasLength(1));
      expect(state.rides.first.assignedDriverId, 'driver-1');
      verify(
        () => list(
          limit: any(named: 'limit'),
          cursor: any(named: 'cursor'),
          status: any(named: 'status'),
          serviceType: any(named: 'serviceType'),
        ),
      ).called(1);
    });
  });

  group('assigned-job progression', () {
    late MockGetRideUseCase getRide;
    late MockMarkEnRouteUseCase enRoute;
    late MockMarkArrivedUseCase arrive;
    late MockStartRideUseCase start;
    late MockCompleteRideUseCase complete;
    late MockCancelRideUseCase cancel;
    late MockCloseRideUseCase close;

    ProviderContainer containerFor(Ride initial) {
      getRide = MockGetRideUseCase();
      enRoute = MockMarkEnRouteUseCase();
      arrive = MockMarkArrivedUseCase();
      start = MockStartRideUseCase();
      complete = MockCompleteRideUseCase();
      cancel = MockCancelRideUseCase();
      close = MockCloseRideUseCase();
      when(() => getRide('ride-1')).thenAnswer((_) async => initial);

      return ProviderContainer(
        overrides: [
          getRideUseCaseProvider.overrideWithValue(getRide),
          markEnRouteUseCaseProvider.overrideWithValue(enRoute),
          markArrivedUseCaseProvider.overrideWithValue(arrive),
          startRideUseCaseProvider.overrideWithValue(start),
          completeRideUseCaseProvider.overrideWithValue(complete),
          cancelRideUseCaseProvider.overrideWithValue(cancel),
          closeRideUseCaseProvider.overrideWithValue(close),
          failureMapperProvider
              .overrideWithValue(const _PassthroughFailureMapper()),
          activeRidePollingPolicyProvider.overrideWithValue(
            const ActiveRidePollingPolicy(
              intervals: [Duration(days: 1)],
              maxLifetime: Duration(days: 1),
            ),
          ),
          idempotencyNonceStoreProvider
              .overrideWithValue(InMemoryIdempotencyNonceStore()),
        ],
      );
    }

    Future<DriverAssignedRideViewModel> boot(
      ProviderContainer c,
    ) async {
      c.listen(driverAssignedRideViewModelProvider('ride-1'), (_, __) {});
      final vm =
          c.read(driverAssignedRideViewModelProvider('ride-1').notifier);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      return vm;
    }

    test('DRIVER_ASSIGNED -> EN_ROUTE', () async {
      final c = containerFor(_ride());
      addTearDown(c.dispose);
      when(
        () => enRoute(
          rideId: any(named: 'rideId'),
          expectedVersion: any(named: 'expectedVersion'),
          operationKey: any(named: 'operationKey'),
        ),
      ).thenAnswer(
        (_) async => _ride(state: 'DRIVER_EN_ROUTE', version: 2),
      );
      final vm = await boot(c);
      await vm.markEnRoute();
      expect(
        c.read(driverAssignedRideViewModelProvider('ride-1')).ride?.state,
        'DRIVER_EN_ROUTE',
      );
      verify(
        () => enRoute(
          rideId: 'ride-1',
          expectedVersion: 1,
          operationKey: any(named: 'operationKey'),
        ),
      ).called(1);
    });

    test('EN_ROUTE -> ARRIVED -> STARTED -> COMPLETED', () async {
      final c = containerFor(_ride(state: 'DRIVER_EN_ROUTE', version: 2));
      addTearDown(c.dispose);
      when(
        () => arrive(
          rideId: any(named: 'rideId'),
          expectedVersion: any(named: 'expectedVersion'),
          operationKey: any(named: 'operationKey'),
        ),
      ).thenAnswer(
        (_) async => _ride(state: 'DRIVER_ARRIVED', version: 3),
      );
      when(
        () => start(
          rideId: any(named: 'rideId'),
          expectedVersion: any(named: 'expectedVersion'),
          operationKey: any(named: 'operationKey'),
        ),
      ).thenAnswer(
        (_) async => _ride(state: 'RIDE_STARTED', version: 4),
      );
      when(
        () => complete(
          rideId: any(named: 'rideId'),
          expectedVersion: any(named: 'expectedVersion'),
          operationKey: any(named: 'operationKey'),
        ),
      ).thenAnswer(
        (_) async => _ride(state: 'RIDE_COMPLETED', version: 5),
      );

      final vm = await boot(c);
      await vm.markArrived();
      await vm.startRide();
      await vm.completeRide();
      expect(
        c.read(driverAssignedRideViewModelProvider('ride-1')).ride?.state,
        'RIDE_COMPLETED',
      );
    });

    test('illegal transition does not call mutation', () async {
      final c = containerFor(_ride(state: 'DRIVER_ASSIGNED'));
      addTearDown(c.dispose);
      final vm = await boot(c);
      await vm.markArrived();
      verifyNever(
        () => arrive(
          rideId: any(named: 'rideId'),
          expectedVersion: any(named: 'expectedVersion'),
          operationKey: any(named: 'operationKey'),
        ),
      );
    });

    test('double tap / concurrent mutation blocked', () async {
      final gate = Completer<Ride>();
      final c = containerFor(_ride());
      addTearDown(c.dispose);
      when(
        () => enRoute(
          rideId: any(named: 'rideId'),
          expectedVersion: any(named: 'expectedVersion'),
          operationKey: any(named: 'operationKey'),
        ),
      ).thenAnswer((_) => gate.future);

      final vm = await boot(c);
      final first = vm.markEnRoute();
      final second = vm.markEnRoute();
      gate.complete(_ride(state: 'DRIVER_EN_ROUTE', version: 2));
      await Future.wait([first, second]);
      verify(
        () => enRoute(
          rideId: any(named: 'rideId'),
          expectedVersion: any(named: 'expectedVersion'),
          operationKey: any(named: 'operationKey'),
        ),
      ).called(1);
    });

    test('stale GET ignored after newer mutation', () async {
      final slowGet = Completer<Ride>();
      var getCalls = 0;
      final c = containerFor(_ride());
      addTearDown(c.dispose);
      when(() => getRide('ride-1')).thenAnswer((_) async {
        getCalls += 1;
        if (getCalls == 1) return _ride();
        return slowGet.future;
      });
      when(
        () => enRoute(
          rideId: any(named: 'rideId'),
          expectedVersion: any(named: 'expectedVersion'),
          operationKey: any(named: 'operationKey'),
        ),
      ).thenAnswer(
        (_) async => _ride(state: 'DRIVER_EN_ROUTE', version: 5),
      );

      final vm = await boot(c);
      // Soft refresh starts second GET.
      final pending = vm.refresh();
      await vm.markEnRoute();
      slowGet.complete(_ride(state: 'DRIVER_ASSIGNED', version: 1));
      await pending;
      expect(
        c.read(driverAssignedRideViewModelProvider('ride-1')).ride?.version,
        5,
      );
    });

    test('VERSION_CONFLICT rotates key and force reconciles', () async {
      final c = containerFor(_ride());
      addTearDown(c.dispose);
      var calls = 0;
      String? firstKey;
      String? secondKey;
      when(
        () => enRoute(
          rideId: any(named: 'rideId'),
          expectedVersion: any(named: 'expectedVersion'),
          operationKey: any(named: 'operationKey'),
        ),
      ).thenAnswer((inv) async {
        calls += 1;
        final key = inv.namedArguments[#operationKey] as String;
        if (calls == 1) {
          firstKey = key;
          throw const AppFailure.conflict(
            message: 'version',
            code: 'VERSION_CONFLICT',
          );
        }
        secondKey = key;
        return _ride(state: 'DRIVER_EN_ROUTE', version: 3);
      });
      when(() => getRide('ride-1')).thenAnswer(
        (_) async => _ride(state: 'DRIVER_ASSIGNED', version: 2),
      );

      final vm = await boot(c);
      await vm.markEnRoute();
      clearInteractions(getRide);
      when(() => getRide('ride-1')).thenAnswer(
        (_) async => _ride(state: 'DRIVER_ASSIGNED', version: 2),
      );
      await vm.markEnRoute();
      expect(firstKey, isNotNull);
      expect(secondKey, isNotNull);
      expect(firstKey, isNot(secondKey));
    });

    test('disposed VM ignores late mutation', () async {
      final gate = Completer<Ride>();
      final c = containerFor(_ride());
      when(
        () => enRoute(
          rideId: any(named: 'rideId'),
          expectedVersion: any(named: 'expectedVersion'),
          operationKey: any(named: 'operationKey'),
        ),
      ).thenAnswer((_) => gate.future);

      final vm = await boot(c);
      final pending = vm.markEnRoute();
      c.dispose();
      gate.complete(_ride(state: 'DRIVER_EN_ROUTE', version: 2));
      await pending;
      // No throw; state write skipped after dispose.
    });

    test('terminal RIDE_CLOSED stops polling', () async {
      final c = containerFor(_ride(state: 'RIDE_CLOSED', version: 9));
      addTearDown(c.dispose);
      await boot(c);
      final state = c.read(driverAssignedRideViewModelProvider('ride-1'));
      expect(state.phase, DriverAssignedRidePhase.ended);
      expect(state.isPolling, isFalse);
    });
  });

  group('direct offer', () {
    test('create and withdraw for explicit rideId', () async {
      final create = MockCreateOfferUseCase();
      final withdraw = MockWithdrawOfferUseCase();
      when(
        () => create(
          rideId: any(named: 'rideId'),
          body: any(named: 'body'),
          operationKey: any(named: 'operationKey'),
        ),
      ).thenAnswer((_) async => _offer());
      when(
        () => withdraw(
          rideId: any(named: 'rideId'),
          offerId: any(named: 'offerId'),
          operationKey: any(named: 'operationKey'),
        ),
      ).thenAnswer((_) async => _offer(status: 'WITHDRAWN'));

      final c = ProviderContainer(
        overrides: [
          createOfferUseCaseProvider.overrideWithValue(create),
          withdrawOfferUseCaseProvider.overrideWithValue(withdraw),
          failureMapperProvider
              .overrideWithValue(const _PassthroughFailureMapper()),
          idempotencyNonceStoreProvider
              .overrideWithValue(InMemoryIdempotencyNonceStore()),
        ],
      );
      addTearDown(c.dispose);
      c.listen(driverDirectOfferViewModelProvider, (_, __) {});
      final vm = c.read(driverDirectOfferViewModelProvider.notifier);
      vm.setRideId('ride-1');
      vm.setExpectedRequestVersion('1');
      vm.setAmountMinor('20000');
      vm.setType('DRIVER_COUNTEROFFER');
      await vm.createOffer();
      expect(
        c.read(driverDirectOfferViewModelProvider).lastCreatedOffer?.offerId,
        'offer-1',
      );
      await vm.withdrawOffer();
      verify(
        () => withdraw(
          rideId: 'ride-1',
          offerId: 'offer-1',
          operationKey: any(named: 'operationKey'),
        ),
      ).called(1);
    });

    test('in-flight create blocks second create', () async {
      final create = MockCreateOfferUseCase();
      final gate = Completer<RideOffer>();
      when(
        () => create(
          rideId: any(named: 'rideId'),
          body: any(named: 'body'),
          operationKey: any(named: 'operationKey'),
        ),
      ).thenAnswer((_) => gate.future);

      final c = ProviderContainer(
        overrides: [
          createOfferUseCaseProvider.overrideWithValue(create),
          withdrawOfferUseCaseProvider.overrideWithValue(
            MockWithdrawOfferUseCase(),
          ),
          failureMapperProvider
              .overrideWithValue(const _PassthroughFailureMapper()),
          idempotencyNonceStoreProvider
              .overrideWithValue(InMemoryIdempotencyNonceStore()),
        ],
      );
      addTearDown(c.dispose);
      c.listen(driverDirectOfferViewModelProvider, (_, __) {});
      final vm = c.read(driverDirectOfferViewModelProvider.notifier);
      vm.setRideId('ride-1');
      vm.setExpectedRequestVersion('1');
      vm.setAmountMinor('20000');
      final a = vm.createOffer();
      final b = vm.createOffer();
      gate.complete(_offer());
      await Future.wait([a, b]);
      verify(
        () => create(
          rideId: any(named: 'rideId'),
          body: any(named: 'body'),
          operationKey: any(named: 'operationKey'),
        ),
      ).called(1);
    });
  });
}
