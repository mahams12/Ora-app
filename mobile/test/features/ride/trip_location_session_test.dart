import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/features/ride/data/location/rtdb_trip_location_data_source.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';
import 'package:ora/features/ride/domain/location/trip_location_freshness.dart';
import 'package:ora/features/ride/domain/models/trip_location_latest.dart';
import 'package:ora/features/ride/domain/use_cases/ride_use_cases.dart';
import 'package:ora/features/ride/presentation/location/trip_location_session.dart';
import 'package:ora/features/ride/presentation/view_models/active_ride_view_model.dart';

import '../../helpers/in_memory_idempotency_nonce_store.dart';

class MockGetRideUseCase extends Mock implements GetRideUseCase {}

class MockCancelRideUseCase extends Mock implements CancelRideUseCase {}

class MockCloseRideUseCase extends Mock implements CloseRideUseCase {}

Ride _ride(String state) {
  return Ride(
    rideId: 'ride-1',
    passengerId: 'p1',
    state: state,
    version: 2,
    requestVersion: 1,
    category: 'easy',
    serviceType: 'ride',
    pickup: const LatLngPoint(lat: 31.52, lng: 74.35, address: 'A'),
    destination: const LatLngPoint(lat: 31.51, lng: 74.34, address: 'B'),
    pricingSnapshotId: 'snap',
    recommendedFareMinor: 1000,
    passengerOfferMinor: 1000,
    paymentMethod: 'CASH',
    passengerCount: 1,
    expiresAt: '2099-01-01T00:00:00.000Z',
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    assignedDriverId: 'd1',
    agreedFareMinor: 1000,
    agreedFareCurrency: 'PKR',
  );
}

TripLocationLatest _latest({
  required int seq,
  DateTime? acceptedAt,
  double lat = 31.53,
  double lng = 74.36,
}) {
  final at = acceptedAt ?? DateTime.utc(2026, 10, 8, 12, 0, 0);
  return TripLocationLatest(
    lat: lat,
    lng: lng,
    accuracy: 8,
    heading: 45,
    speed: 12,
    ts: at.millisecondsSinceEpoch,
    acceptedAt: at.toIso8601String(),
    driverId: 'd1',
    locationSeq: seq,
    locationStreamId: 'stream-1',
  );
}

void main() {
  late MockGetRideUseCase getRide;
  late MockCancelRideUseCase cancel;
  late MockCloseRideUseCase close;
  late MemoryTripLocationPort memoryPort;
  late DateTime clock;

  setUp(() {
    getRide = MockGetRideUseCase();
    cancel = MockCancelRideUseCase();
    close = MockCloseRideUseCase();
    memoryPort = MemoryTripLocationPort();
    clock = DateTime.utc(2026, 10, 8, 12, 0, 0);
  });

  ProviderContainer _container({required String initialState}) {
    when(() => getRide(any())).thenAnswer((_) async => _ride(initialState));
    return ProviderContainer(
      overrides: [
        getRideUseCaseProvider.overrideWithValue(getRide),
        cancelRideUseCaseProvider.overrideWithValue(cancel),
        closeRideUseCaseProvider.overrideWithValue(close),
        tripLocationPortProvider.overrideWithValue(memoryPort),
        tripLocationClockProvider.overrideWithValue(() => clock),
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

  Future<void> _settle(
    ProviderContainer c, {
    String rideId = 'ride-1',
    MemoryTripLocationPort? port,
  }) async {
    final p = port ?? memoryPort;
    // Keep AutoDispose providers alive for the test.
    c.listen(activeRideViewModelProvider(rideId), (_, __) {});
    c.listen(tripLocationSessionProvider(rideId), (_, __) {});
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final s = c.read(tripLocationSessionProvider(rideId));
      if (s.isListening && p.activeRideIds.contains(rideId)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return;
      }
    }
  }

  test('DRIVER_ASSIGNED starts exactly one listener', () async {
    final c = _container(initialState: 'DRIVER_ASSIGNED');
    addTearDown(c.dispose);
    await _settle(c);
    expect(memoryPort.watchStartCount, 1);
    expect(memoryPort.activeRideIds, contains('ride-1'));
    final session = c.read(tripLocationSessionProvider('ride-1').notifier);
    expect(session.activeSubscriptionCount, 1);
    expect(c.read(tripLocationSessionProvider('ride-1')).isListening, isTrue);
  });

  test('DRIVER_EN_ROUTE / ARRIVED / STARTED start listener', () async {
    for (final state in [
      'DRIVER_EN_ROUTE',
      'DRIVER_ARRIVED',
      'RIDE_STARTED',
    ]) {
      final port = MemoryTripLocationPort();
      when(() => getRide(any())).thenAnswer((_) async => _ride(state));
      final c = ProviderContainer(
        overrides: [
          getRideUseCaseProvider.overrideWithValue(getRide),
          cancelRideUseCaseProvider.overrideWithValue(cancel),
          closeRideUseCaseProvider.overrideWithValue(close),
          tripLocationPortProvider.overrideWithValue(port),
          tripLocationClockProvider.overrideWithValue(() => clock),
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
      addTearDown(c.dispose);
      await _settle(c, port: port);
      expect(port.watchStartCount, 1, reason: state);
    }
  });

  test('RIDE_COMPLETED stops listener', () async {
    final c = _container(initialState: 'DRIVER_ASSIGNED');
    addTearDown(c.dispose);
    await _settle(c);
    expect(memoryPort.watchStartCount, 1);

    // Simulate VM state advance by overriding getRide and refreshing.
    when(() => getRide(any())).thenAnswer((_) async => _ride('RIDE_COMPLETED'));
    await c.read(activeRideViewModelProvider('ride-1').notifier).refresh();
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(
      c.read(tripLocationSessionProvider('ride-1')).isListening,
      isFalse,
    );
    expect(memoryPort.activeRideIds, isEmpty);
  });

  test('CANCELLED / NO_SHOW / RIDE_CLOSED stop listener', () async {
    for (final terminal in ['CANCELLED', 'NO_SHOW', 'RIDE_CLOSED']) {
      final port = MemoryTripLocationPort();
      when(() => getRide(any()))
          .thenAnswer((_) async => _ride('DRIVER_ASSIGNED'));
      final c = ProviderContainer(
        overrides: [
          getRideUseCaseProvider.overrideWithValue(getRide),
          cancelRideUseCaseProvider.overrideWithValue(cancel),
          closeRideUseCaseProvider.overrideWithValue(close),
          tripLocationPortProvider.overrideWithValue(port),
          tripLocationClockProvider.overrideWithValue(() => clock),
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
      addTearDown(c.dispose);
      await _settle(c, port: port);
      expect(port.watchStartCount, 1);

      when(() => getRide(any())).thenAnswer((_) async => _ride(terminal));
      await c.read(activeRideViewModelProvider('ride-1').notifier).refresh();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(
        c.read(tripLocationSessionProvider('ride-1')).isListening,
        isFalse,
        reason: terminal,
      );
    }
  });

  test('waiting when assigned but no RTDB latest', () async {
    final c = _container(initialState: 'DRIVER_ASSIGNED');
    addTearDown(c.dispose);
    await _settle(c);
    memoryPort.emit('ride-1', null);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final s = c.read(tripLocationSessionProvider('ride-1'));
    expect(s.latest, isNull);
    expect(s.statusMessage, contains('Waiting'));
  });

  test('driver marker fields appear with valid latest', () async {
    final c = _container(initialState: 'DRIVER_ASSIGNED');
    addTearDown(c.dispose);
    await _settle(c);
    memoryPort.emit('ride-1', _latest(seq: 1, acceptedAt: clock));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final s = c.read(tripLocationSessionProvider('ride-1'));
    expect(s.latest, isNotNull);
    expect(s.appliedSeq, 1);
    expect(s.freshness, TripLocationFreshness.fresh);
  });

  test('older locationSeq is ignored', () async {
    final c = _container(initialState: 'DRIVER_EN_ROUTE');
    addTearDown(c.dispose);
    await _settle(c);
    memoryPort.emit('ride-1', _latest(seq: 5, lat: 31.54));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    memoryPort.emit('ride-1', _latest(seq: 3, lat: 31.0));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final s = c.read(tripLocationSessionProvider('ride-1'));
    expect(s.appliedSeq, 5);
    expect(s.latest!.lat, 31.54);
  });

  test('malformed latest does not crash session', () async {
    final c = _container(initialState: 'DRIVER_ASSIGNED');
    addTearDown(c.dispose);
    await _settle(c);
    // Port only emits validated models; simulate soft null.
    expect(() => memoryPort.emit('ride-1', null), returnsNormally);
  });

  test('stale marker UX message', () async {
    final c = _container(initialState: 'DRIVER_ASSIGNED');
    addTearDown(c.dispose);
    await _settle(c);
    final staleAt = clock.subtract(const Duration(seconds: 30));
    memoryPort.emit('ride-1', _latest(seq: 2, acceptedAt: staleAt));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final s = c.read(tripLocationSessionProvider('ride-1'));
    expect(s.freshness, TripLocationFreshness.stale);
    expect(s.statusMessage, 'Location updating…');
  });

  test('no duplicate listener while already watching', () async {
    final c = _container(initialState: 'DRIVER_ASSIGNED');
    addTearDown(c.dispose);
    await _settle(c);
    final gen1 = c.read(tripLocationSessionProvider('ride-1')).watchGeneration;
    // Lifecycle resume while already listening should not stack.
    c
        .read(tripLocationSessionProvider('ride-1').notifier)
        .onAppLifecycle(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(memoryPort.watchStartCount, 1);
    expect(
      c.read(tripLocationSessionProvider('ride-1')).watchGeneration,
      gen1,
    );
  });

  test('background pauses; foreground resumes one listener', () async {
    final c = _container(initialState: 'DRIVER_ASSIGNED');
    addTearDown(c.dispose);
    await _settle(c);
    expect(memoryPort.watchStartCount, 1);
    final session = c.read(tripLocationSessionProvider('ride-1').notifier);
    session.onAppLifecycle(AppLifecycleState.paused);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(memoryPort.activeRideIds, isEmpty);
    session.onAppLifecycle(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(memoryPort.watchStartCount, 2);
    expect(memoryPort.activeRideIds, contains('ride-1'));
  });

  test('rideId change disposes old listener via AutoDispose family', () async {
    when(() => getRide(any())).thenAnswer((invocation) async {
      final id = invocation.positionalArguments.first as String;
      return Ride(
        rideId: id,
        passengerId: 'p1',
        state: 'DRIVER_ASSIGNED',
        version: 2,
        requestVersion: 1,
        category: 'easy',
        serviceType: 'ride',
        pickup: const LatLngPoint(lat: 31.52, lng: 74.35),
        destination: const LatLngPoint(lat: 31.51, lng: 74.34),
        pricingSnapshotId: 'snap',
        recommendedFareMinor: 1000,
        passengerOfferMinor: 1000,
        paymentMethod: 'CASH',
        passengerCount: 1,
        expiresAt: '2099-01-01T00:00:00.000Z',
        createdAt: '2026-01-01T00:00:00.000Z',
        updatedAt: '2026-01-01T00:00:00.000Z',
        assignedDriverId: 'd1',
      );
    });
    final port = MemoryTripLocationPort();
    final c = ProviderContainer(
      overrides: [
        getRideUseCaseProvider.overrideWithValue(getRide),
        cancelRideUseCaseProvider.overrideWithValue(cancel),
        closeRideUseCaseProvider.overrideWithValue(close),
        tripLocationPortProvider.overrideWithValue(port),
        tripLocationClockProvider.overrideWithValue(() => clock),
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
    addTearDown(c.dispose);

    final subA = c.listen(tripLocationSessionProvider('ride-a'), (_, __) {});
    c.read(activeRideViewModelProvider('ride-a'));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(port.activeRideIds, contains('ride-a'));

    final subB = c.listen(tripLocationSessionProvider('ride-b'), (_, __) {});
    c.read(activeRideViewModelProvider('ride-b'));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(port.activeRideIds, containsAll(['ride-a', 'ride-b']));

    subA.close();
    // Allow autoDispose.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(port.activeRideIds.contains('ride-a'), isFalse);
    expect(port.activeRideIds, contains('ride-b'));
    subB.close();
  });
}
