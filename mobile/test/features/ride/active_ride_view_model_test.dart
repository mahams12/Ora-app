
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/core/errors/app_failure.dart';
import 'package:ora/core/errors/failure_mapper.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';
import 'package:ora/features/ride/domain/use_cases/ride_use_cases.dart';
import 'package:ora/features/ride/presentation/active_ride/active_ride_display.dart';
import 'package:ora/features/ride/presentation/view_models/active_ride_view_model.dart';

import '../../helpers/in_memory_idempotency_nonce_store.dart';

class MockGetRideUseCase extends Mock implements GetRideUseCase {}

class MockCancelRideUseCase extends Mock implements CancelRideUseCase {}

class MockCloseRideUseCase extends Mock implements CloseRideUseCase {}

class _PassthroughFailureMapper extends FailureMapper {
  const _PassthroughFailureMapper();

  @override
  AppFailure fromException(Object error, [StackTrace? stackTrace]) {
    if (error is AppFailure) return error;
    return AppFailure.unknown(message: error.toString());
  }
}

Ride _ride({
  String state = 'DRIVER_ASSIGNED',
  int version = 1,
  int requestVersion = 1,
  String? arrivedAt,
  String? cancellationReason,
  int? agreedFareMinor,
}) {
  return Ride(
    rideId: 'ride-1',
    passengerId: 'p1',
    state: state,
    version: version,
    requestVersion: requestVersion,
    category: 'easy',
    serviceType: 'ride',
    pickup: const LatLngPoint(lat: 1, lng: 2, address: 'A'),
    destination: const LatLngPoint(lat: 3, lng: 4, address: 'B'),
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
    cancellationReason: cancellationReason,
    agreedFareMinor: agreedFareMinor,
    agreedFareCurrency: agreedFareMinor != null ? 'PKR' : null,
  );
}

ProviderContainer _container({
  required MockGetRideUseCase getRide,
  required MockCancelRideUseCase cancel,
  required MockCloseRideUseCase close,
  ActiveRidePollingPolicy policy = const ActiveRidePollingPolicy(
    intervals: [Duration(days: 1)],
    maxLifetime: Duration(days: 1),
  ),
}) {
  return ProviderContainer(
    overrides: [
      getRideUseCaseProvider.overrideWithValue(getRide),
      cancelRideUseCaseProvider.overrideWithValue(cancel),
      closeRideUseCaseProvider.overrideWithValue(close),
      failureMapperProvider.overrideWithValue(const _PassthroughFailureMapper()),
      activeRidePollingPolicyProvider.overrideWithValue(policy),
      idempotencyNonceStoreProvider
          .overrideWithValue(InMemoryIdempotencyNonceStore()),
    ],
  );
}

Future<ActiveRideViewModel> keepActive(ProviderContainer c, [String rideId = 'ride-1']) async {
  c.listen(activeRideViewModelProvider(rideId), (_, __) {});
  final vm = c.read(activeRideViewModelProvider(rideId).notifier);
  await Future<void>.delayed(Duration.zero);
  await vm.refresh();
  return vm;
}

void main() {
  setUpAll(() {
    registerFallbackValue(0);
  });

  late MockGetRideUseCase getRide;
  late MockCancelRideUseCase cancel;
  late MockCloseRideUseCase close;

  setUp(() {
    getRide = MockGetRideUseCase();
    cancel = MockCancelRideUseCase();
    close = MockCloseRideUseCase();
  });

  test('shouldAcceptRideSnapshot rejects stale version', () {
    final current = _ride(version: 5);
    final stale = _ride(version: 4, state: 'DRIVER_ARRIVED');
    expect(shouldAcceptRideSnapshot(stale, current), isFalse);
    expect(shouldAcceptRideSnapshot(_ride(version: 6), current), isTrue);
  });

  test('initial fetch renders authoritative assigned state', () async {
    when(() => getRide('ride-1'))
        .thenAnswer((_) async => _ride(state: 'DRIVER_EN_ROUTE', version: 2));

    final c = _container(getRide: getRide, cancel: cancel, close: close);
    addTearDown(c.dispose);

    await (await keepActive(c)).refresh();
    final state = c.read(activeRideViewModelProvider('ride-1'));
    expect(state.ride?.state, 'DRIVER_EN_ROUTE');
    expect(state.phase, ActiveRidePhase.active);
  });

  test('stale poll response does not regress state', () async {
    when(() => getRide('ride-1')).thenAnswer((_) async => _ride(version: 3));

    final c = _container(getRide: getRide, cancel: cancel, close: close);
    addTearDown(c.dispose);
    final vm = await keepActive(c);
    await vm.refresh();

    // Inject newer local state then apply stale via second fetch race.
    when(() => getRide('ride-1')).thenAnswer(
      (_) async => _ride(state: 'DRIVER_ARRIVED', version: 2),
    );
    await vm.refresh();
    expect(c.read(activeRideViewModelProvider('ride-1')).ride?.version, 3);
    expect(
      c.read(activeRideViewModelProvider('ride-1')).ride?.state,
      'DRIVER_ASSIGNED',
    );
  });

  test('cancel uses server response — never local CANCELLED invent', () async {
    when(() => getRide('ride-1')).thenAnswer((_) async => _ride());
    when(
      () => cancel(
        rideId: any(named: 'rideId'),
        reason: any(named: 'reason'),
        operationKey: any(named: 'operationKey'),
      ),
    ).thenAnswer((_) async => _ride(state: 'CANCELLED', version: 4));

    final c = _container(getRide: getRide, cancel: cancel, close: close);
    addTearDown(c.dispose);
    final vm = await keepActive(c);
    await vm.refresh();
    await vm.cancel();

    final state = c.read(activeRideViewModelProvider('ride-1'));
    expect(state.ride?.state, 'CANCELLED');
    expect(state.phase, ActiveRidePhase.ended);
    expect(state.isPolling, isFalse);
    verify(
      () => cancel(
        rideId: 'ride-1',
        reason: any(named: 'reason'),
        operationKey: any(named: 'operationKey'),
      ),
    ).called(1);
  });

  test('version conflict on cancel refetches truth', () async {
    when(() => getRide('ride-1'))
        .thenAnswer((_) async => _ride(state: 'DRIVER_EN_ROUTE', version: 2));
    when(
      () => cancel(
        rideId: any(named: 'rideId'),
        reason: any(named: 'reason'),
        operationKey: any(named: 'operationKey'),
      ),
    ).thenThrow(
      const AppFailure.conflict(
        message: 'Conflict',
        code: 'VERSION_CONFLICT',
      ),
    );

    final c = _container(getRide: getRide, cancel: cancel, close: close);
    addTearDown(c.dispose);
    final vm = await keepActive(c);
    await vm.refresh();

    when(() => getRide('ride-1'))
        .thenAnswer((_) async => _ride(state: 'RIDE_STARTED', version: 5));
    await vm.cancel();

    final state = c.read(activeRideViewModelProvider('ride-1'));
    expect(state.ride?.state, 'RIDE_STARTED');
    expect(state.ride?.version, 5);
    expect(state.isCancelling, isFalse);
  });

  test('close ride from RIDE_COMPLETED', () async {
    when(() => getRide('ride-1'))
        .thenAnswer((_) async => _ride(state: 'RIDE_COMPLETED', version: 8));
    when(
      () => close(
        rideId: any(named: 'rideId'),
        expectedVersion: any(named: 'expectedVersion'),
        operationKey: any(named: 'operationKey'),
      ),
    ).thenAnswer((_) async => _ride(state: 'RIDE_CLOSED', version: 9));

    final c = _container(getRide: getRide, cancel: cancel, close: close);
    addTearDown(c.dispose);
    final vm = await keepActive(c);
    await vm.refresh();
    await vm.closeRide();

    expect(
      c.read(activeRideViewModelProvider('ride-1')).ride?.state,
      'RIDE_CLOSED',
    );
    expect(
      c.read(activeRideViewModelProvider('ride-1')).phase,
      ActiveRidePhase.ended,
    );
  });

  test('polling stops on terminal NO_SHOW', () async {
    when(() => getRide('ride-1'))
        .thenAnswer((_) async => _ride(state: 'NO_SHOW', version: 3));

    final c = _container(
      getRide: getRide,
      cancel: cancel,
      close: close,
      policy: const ActiveRidePollingPolicy(
        intervals: [Duration(milliseconds: 20)],
        maxLifetime: Duration(seconds: 2),
      ),
    );
    addTearDown(c.dispose);

    await (await keepActive(c)).start();
    expect(
      c.read(activeRideViewModelProvider('ride-1')).phase,
      ActiveRidePhase.ended,
    );
    clearInteractions(getRide);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    verifyNever(() => getRide(any()));
  });

  test('dispose stops polling', () async {
    when(() => getRide('ride-1')).thenAnswer((_) async => _ride());
    final c = _container(
      getRide: getRide,
      cancel: cancel,
      close: close,
      policy: const ActiveRidePollingPolicy(
        intervals: [Duration(milliseconds: 20)],
        maxLifetime: Duration(seconds: 2),
      ),
    );
    await (await keepActive(c)).start();
    c.dispose();
    clearInteractions(getRide);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    verifyNever(() => getRide(any()));
  });

  test('soft network error keeps last ride visible', () async {
    when(() => getRide('ride-1')).thenAnswer((_) async => _ride());
    final c = _container(getRide: getRide, cancel: cancel, close: close);
    addTearDown(c.dispose);
    final vm = await keepActive(c);
    await vm.refresh();

    when(() => getRide('ride-1'))
        .thenThrow(const AppFailure.network(message: 'offline'));
    await vm.refresh();

    final state = c.read(activeRideViewModelProvider('ride-1'));
    expect(state.ride?.state, 'DRIVER_ASSIGNED');
    expect(state.connectivityDegraded, isTrue);
    expect(state.phase, isNot(ActiveRidePhase.fatalError));
  });

  test('arrivedWaitLabel uses real arrivedAt only', () {
    final ride = _ride(
      state: 'DRIVER_ARRIVED',
      arrivedAt: DateTime.now().subtract(const Duration(minutes: 2)).toIso8601String(),
    );
    final label = arrivedWaitLabel(ride, DateTime.now());
    expect(label, isNotNull);
    expect(label, contains('Waiting'));
    expect(arrivedWaitLabel(_ride(arrivedAt: null), DateTime.now()), isNull);
  });

  test('passengerCanCancel false for RIDE_COMPLETED', () {
    expect(passengerCanCancel('RIDE_COMPLETED'), isFalse);
    expect(passengerCanClose('RIDE_COMPLETED'), isTrue);
  });
}
