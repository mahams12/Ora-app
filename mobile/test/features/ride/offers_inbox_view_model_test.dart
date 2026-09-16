import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/core/errors/app_failure.dart';
import 'package:ora/core/errors/failure_mapper.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';
import 'package:ora/features/ride/domain/use_cases/ride_use_cases.dart';
import 'package:ora/features/ride/presentation/view_models/offers_inbox_view_model.dart';

import '../../helpers/in_memory_idempotency_nonce_store.dart';

class MockGetRideUseCase extends Mock implements GetRideUseCase {}

class MockListOffersUseCase extends Mock implements ListOffersUseCase {}

class MockSelectOfferUseCase extends Mock implements SelectOfferUseCase {}

Ride _ride({
  String state = 'SEARCHING',
  int version = 1,
  String? assignedDriverId,
  int? agreedFareMinor,
  String? agreedOfferId,
}) {
  return Ride(
    rideId: 'ride-1',
    passengerId: 'p1',
    state: state,
    version: version,
    requestVersion: 1,
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
    assignedDriverId: assignedDriverId,
    agreedFareMinor: agreedFareMinor,
    agreedOfferId: agreedOfferId,
  );
}

RideOffer _offer({
  String id = 'offer-1',
  String status = 'PENDING',
  int amount = 20000,
}) {
  return RideOffer(
    offerId: id,
    rideId: 'ride-1',
    driverId: 'driver-secret',
    amountMinor: amount,
    currency: 'PKR',
    type: 'COUNTER',
    status: status,
    requestVersion: 1,
    expiresAt: '2099-01-01T00:00:00.000Z',
    createdAt: '2026-01-01T00:00:00.000Z',
    driverSnapshot: const {'displayName': null, 'role': 'driver'},
  );
}

class _PassthroughFailureMapper extends FailureMapper {
  const _PassthroughFailureMapper();

  @override
  AppFailure fromException(Object error, [StackTrace? stackTrace]) {
    if (error is AppFailure) return error;
    return AppFailure.unknown(message: error.toString());
  }
}

ProviderContainer _container({
  required MockGetRideUseCase getRide,
  required MockListOffersUseCase listOffers,
  required MockSelectOfferUseCase selectOffer,
  OfferPollingPolicy policy = const OfferPollingPolicy(
    intervals: [Duration(milliseconds: 30), Duration(milliseconds: 40)],
    maxLifetime: Duration(seconds: 2),
  ),
}) {
  return ProviderContainer(
    overrides: [
      getRideUseCaseProvider.overrideWithValue(getRide),
      listOffersUseCaseProvider.overrideWithValue(listOffers),
      selectOfferUseCaseProvider.overrideWithValue(selectOffer),
      failureMapperProvider.overrideWithValue(const _PassthroughFailureMapper()),
      offerPollingPolicyProvider.overrideWithValue(policy),
      idempotencyNonceStoreProvider
          .overrideWithValue(InMemoryIdempotencyNonceStore()),
    ],
  );
}

Future<OffersInboxViewModel> keepOffers(ProviderContainer c, [String rideId = 'ride-1']) async {
  c.listen(offersInboxViewModelProvider(rideId), (_, __) {});
  final vm = c.read(offersInboxViewModelProvider(rideId).notifier);
  await Future<void>.delayed(Duration.zero);
  await vm.refresh();
  return vm;
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

  test('initial fetch empty offers → ready waiting', () async {
    when(() => getRide('ride-1')).thenAnswer((_) async => _ride());
    when(() => listOffers('ride-1')).thenAnswer((_) async => []);

    final c = _container(
      getRide: getRide,
      listOffers: listOffers,
      selectOffer: selectOffer,
      policy: const OfferPollingPolicy(
        intervals: [Duration(days: 1)],
        maxLifetime: Duration(days: 1),
      ),
    );
    addTearDown(c.dispose);

    await keepOffers(c);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await (await keepOffers(c)).refresh();
    await (await keepOffers(c)).refresh();

    final state = c.read(offersInboxViewModelProvider('ride-1'));
    expect(state.phase, OffersInboxPhase.ready);
    expect(state.offers, isEmpty);
    expect(state.ride?.state, 'SEARCHING');
  });

  test('offers received and deduplicated by id', () async {
    when(() => getRide('ride-1')).thenAnswer((_) async => _ride());
    when(() => listOffers('ride-1')).thenAnswer(
      (_) async => [_offer(id: 'a'), _offer(id: 'a'), _offer(id: 'b')],
    );

    final c = _container(
      getRide: getRide,
      listOffers: listOffers,
      selectOffer: selectOffer,
      policy: const OfferPollingPolicy(
        intervals: [Duration(days: 1)],
        maxLifetime: Duration(days: 1),
      ),
    );
    addTearDown(c.dispose);

    await (await keepOffers(c)).refresh();
    final state = c.read(offersInboxViewModelProvider('ride-1'));
    expect(state.offers.map((o) => o.offerId), ['a', 'b']);
    // Never invent fake driver names from null snapshot.
    expect(state.offers.every((o) => o.driverSnapshot?['displayName'] == null),
        isTrue);
  });

  test('polling stops on terminal EXPIRED', () async {
    when(() => getRide('ride-1')).thenAnswer((_) async => _ride(state: 'EXPIRED'));
    when(() => listOffers('ride-1')).thenAnswer((_) async => []);

    final c = _container(
      getRide: getRide,
      listOffers: listOffers,
      selectOffer: selectOffer,
      policy: const OfferPollingPolicy(
        intervals: [Duration(milliseconds: 20)],
        maxLifetime: Duration(seconds: 5),
      ),
    );
    addTearDown(c.dispose);

    await (await keepOffers(c)).start();
    final state = c.read(offersInboxViewModelProvider('ride-1'));
    expect(state.phase, OffersInboxPhase.terminal);
    expect(state.isPolling, isFalse);

    clearInteractions(getRide);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    verifyNever(() => getRide(any()));
  });

  test('polling stops on dispose', () async {
    when(() => getRide('ride-1')).thenAnswer((_) async => _ride());
    when(() => listOffers('ride-1')).thenAnswer((_) async => []);

    final c = _container(
      getRide: getRide,
      listOffers: listOffers,
      selectOffer: selectOffer,
      policy: const OfferPollingPolicy(
        intervals: [Duration(milliseconds: 20)],
        maxLifetime: Duration(seconds: 5),
      ),
    );

    await (await keepOffers(c)).start();
    c.dispose();
    clearInteractions(getRide);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    verifyNever(() => getRide(any()));
  });

  test('select success → assigned and stops polling', () async {
    when(() => getRide('ride-1')).thenAnswer((_) async => _ride(version: 3));
    when(() => listOffers('ride-1'))
        .thenAnswer((_) async => [_offer(id: 'offer-1')]);
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
        version: 4,
        assignedDriverId: 'd1',
        agreedFareMinor: 20000,
        agreedOfferId: 'offer-1',
        currency: 'PKR',
      ),
    );

    final c = _container(
      getRide: getRide,
      listOffers: listOffers,
      selectOffer: selectOffer,
      policy: const OfferPollingPolicy(
        intervals: [Duration(days: 1)],
        maxLifetime: Duration(days: 1),
      ),
    );
    addTearDown(c.dispose);

    final vm = await keepOffers(c);
    await vm.refresh();
    await vm.selectOffer('offer-1');

    final state = c.read(offersInboxViewModelProvider('ride-1'));
    expect(state.phase, OffersInboxPhase.assigned);
    expect(state.assignment?.agreedOfferId, 'offer-1');
    expect(state.isPolling, isFalse);
    verify(
      () => selectOffer(
        rideId: 'ride-1',
        offerId: 'offer-1',
        expectedVersion: 3,
        operationKey: any(named: 'operationKey'),
      ),
    ).called(1);
  });

  test('version conflict reconciles via refetch — no local version invent',
      () async {
    var version = 2;
    when(() => getRide('ride-1')).thenAnswer((_) async => _ride(version: version));
    when(() => listOffers('ride-1'))
        .thenAnswer((_) async => [_offer(id: 'offer-1')]);
    when(
      () => selectOffer(
        rideId: any(named: 'rideId'),
        offerId: any(named: 'offerId'),
        expectedVersion: any(named: 'expectedVersion'),
        operationKey: any(named: 'operationKey'),
      ),
    ).thenThrow(
      const AppFailure.conflict(
        message: 'Version conflict',
        code: 'VERSION_CONFLICT',
      ),
    );

    final c = _container(
      getRide: getRide,
      listOffers: listOffers,
      selectOffer: selectOffer,
      policy: const OfferPollingPolicy(
        intervals: [Duration(days: 1)],
        maxLifetime: Duration(days: 1),
      ),
    );
    addTearDown(c.dispose);

    final vm = await keepOffers(c);
    await vm.refresh();
    version = 5;
    await vm.selectOffer('offer-1');

    final state = c.read(offersInboxViewModelProvider('ride-1'));
    expect(state.phase, OffersInboxPhase.ready);
    expect(state.ride?.version, 5);
    expect(state.selectingOfferId, isNull);
    expect(state.infoMessage, isNotNull);
  });

  test('already assigned conflict refreshes to assigned phase', () async {
    when(() => getRide('ride-1')).thenAnswer(
      (_) async => _ride(
        state: 'DRIVER_ASSIGNED',
        assignedDriverId: 'd9',
        agreedFareMinor: 18000,
        agreedOfferId: 'offer-9',
      ),
    );
    when(() => listOffers('ride-1')).thenAnswer((_) async => []);
    when(
      () => selectOffer(
        rideId: any(named: 'rideId'),
        offerId: any(named: 'offerId'),
        expectedVersion: any(named: 'expectedVersion'),
        operationKey: any(named: 'operationKey'),
      ),
    ).thenThrow(
      const AppFailure.conflict(
        message: 'Already assigned',
        code: 'ALREADY_ASSIGNED',
      ),
    );

    // First load as marketplace so select can be attempted.
    final getRideSeq = MockGetRideUseCase();
    when(() => getRideSeq('ride-1')).thenAnswer((_) async => _ride(version: 1));
    final listSeq = MockListOffersUseCase();
    when(() => listSeq('ride-1'))
        .thenAnswer((_) async => [_offer(id: 'offer-1')]);

    final c = _container(
      getRide: getRideSeq,
      listOffers: listSeq,
      selectOffer: selectOffer,
      policy: const OfferPollingPolicy(
        intervals: [Duration(days: 1)],
        maxLifetime: Duration(days: 1),
      ),
    );
    addTearDown(c.dispose);

    final vm = await keepOffers(c);
    await vm.refresh();

    // Next refresh after conflict returns assigned ride.
    when(() => getRideSeq('ride-1')).thenAnswer(
      (_) async => _ride(
        state: 'DRIVER_ASSIGNED',
        assignedDriverId: 'd9',
        agreedFareMinor: 18000,
        agreedOfferId: 'offer-9',
      ),
    );
    when(() => listSeq('ride-1')).thenAnswer((_) async => []);

    await vm.selectOffer('offer-1');
    final state = c.read(offersInboxViewModelProvider('ride-1'));
    expect(state.phase, OffersInboxPhase.assigned);
  });

  test('network error on initial load is fatal; soft on refresh', () async {
    when(() => getRide('ride-1'))
        .thenThrow(const AppFailure.network(message: 'offline'));
    when(() => listOffers('ride-1')).thenAnswer((_) async => []);

    final c = _container(
      getRide: getRide,
      listOffers: listOffers,
      selectOffer: selectOffer,
      policy: const OfferPollingPolicy(
        intervals: [Duration(days: 1)],
        maxLifetime: Duration(days: 1),
      ),
    );
    addTearDown(c.dispose);

    await (await keepOffers(c)).refresh();
    expect(
      c.read(offersInboxViewModelProvider('ride-1')).phase,
      OffersInboxPhase.fatalError,
    );
  });

  test('expired offers are not selectable', () async {
    when(() => getRide('ride-1')).thenAnswer((_) async => _ride());
    when(() => listOffers('ride-1')).thenAnswer(
      (_) async => [_offer(id: 'x', status: 'EXPIRED')],
    );

    final c = _container(
      getRide: getRide,
      listOffers: listOffers,
      selectOffer: selectOffer,
      policy: const OfferPollingPolicy(
        intervals: [Duration(days: 1)],
        maxLifetime: Duration(days: 1),
      ),
    );
    addTearDown(c.dispose);

    final vm = await keepOffers(c);
    await vm.refresh();
    await vm.selectOffer('x');
    verifyNever(
      () => selectOffer(
        rideId: any(named: 'rideId'),
        offerId: any(named: 'offerId'),
        expectedVersion: any(named: 'expectedVersion'),
        operationKey: any(named: 'operationKey'),
      ),
    );
  });

  test('duplicate select while selecting is ignored', () async {
    final gate = Completer<RideAssignment>();
    when(() => getRide('ride-1')).thenAnswer((_) async => _ride(version: 1));
    when(() => listOffers('ride-1'))
        .thenAnswer((_) async => [_offer(id: 'offer-1')]);
    when(
      () => selectOffer(
        rideId: any(named: 'rideId'),
        offerId: any(named: 'offerId'),
        expectedVersion: any(named: 'expectedVersion'),
        operationKey: any(named: 'operationKey'),
      ),
    ).thenAnswer((_) => gate.future);

    final c = _container(
      getRide: getRide,
      listOffers: listOffers,
      selectOffer: selectOffer,
      policy: const OfferPollingPolicy(
        intervals: [Duration(days: 1)],
        maxLifetime: Duration(days: 1),
      ),
    );
    addTearDown(c.dispose);

    final vm = await keepOffers(c);
    await vm.refresh();
    final first = vm.selectOffer('offer-1');
    final second = vm.selectOffer('offer-1');
    gate.complete(
      const RideAssignment(
        rideId: 'ride-1',
        state: 'DRIVER_ASSIGNED',
        version: 2,
        assignedDriverId: 'd1',
        agreedFareMinor: 20000,
        agreedOfferId: 'offer-1',
        currency: 'PKR',
      ),
    );
    await Future.wait([first, second]);
    verify(
      () => selectOffer(
        rideId: any(named: 'rideId'),
        offerId: any(named: 'offerId'),
        expectedVersion: any(named: 'expectedVersion'),
        operationKey: any(named: 'operationKey'),
      ),
    ).called(1);
  });

  test('pause then resume performs fresh fetch', () async {
    when(() => getRide('ride-1')).thenAnswer((_) async => _ride());
    when(() => listOffers('ride-1')).thenAnswer((_) async => []);

    final c = _container(
      getRide: getRide,
      listOffers: listOffers,
      selectOffer: selectOffer,
      policy: const OfferPollingPolicy(
        intervals: [Duration(days: 1)],
        maxLifetime: Duration(days: 1),
      ),
    );
    addTearDown(c.dispose);

    final vm = await keepOffers(c);
    await vm.start();
    clearInteractions(getRide);
    vm.pausePolling();
    await vm.resumePolling();
    verify(() => getRide('ride-1')).called(1);
  });
}
