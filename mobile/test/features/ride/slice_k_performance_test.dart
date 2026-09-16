import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/app/theme/theme.dart';
import 'package:ora/core/errors/app_failure.dart';
import 'package:ora/core/errors/failure_mapper.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';
import 'package:ora/features/ride/domain/use_cases/ride_use_cases.dart';
import 'package:ora/features/ride/presentation/active_ride/active_ride_display.dart';
import 'package:ora/features/ride/presentation/view_models/active_ride_view_model.dart';
import 'package:ora/features/ride/presentation/view_models/offers_inbox_view_model.dart';
import 'package:ora/features/ride/presentation/view_models/ride_rating_view_model.dart';
import 'package:ora/features/ride/presentation/views/ride_history_view.dart';

import '../../helpers/in_memory_idempotency_nonce_store.dart';

class MockGetRideUseCase extends Mock implements GetRideUseCase {}

class MockListOffersUseCase extends Mock implements ListOffersUseCase {}

class MockSelectOfferUseCase extends Mock implements SelectOfferUseCase {}

class MockCancelRideUseCase extends Mock implements CancelRideUseCase {}

class MockCloseRideUseCase extends Mock implements CloseRideUseCase {}

class MockListRidesUseCase extends Mock implements ListRidesUseCase {}

class MockGetMyRatingUseCase extends Mock implements GetMyRatingUseCase {}

class MockSubmitRatingUseCase extends Mock implements SubmitRatingUseCase {}

class _PassthroughFailureMapper extends FailureMapper {
  const _PassthroughFailureMapper();

  @override
  AppFailure fromException(Object error, [StackTrace? stackTrace]) {
    if (error is AppFailure) return error;
    return AppFailure.unknown(message: error.toString());
  }
}

Ride _ride({
  String state = 'SEARCHING',
  int version = 1,
  String? arrivedAt,
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
    arrivedAt: arrivedAt,
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
    driverId: 'd1',
    amountMinor: amount,
    currency: 'PKR',
    type: 'COUNTER',
    status: status,
    requestVersion: 1,
    expiresAt: '2099-01-01T00:00:00.000Z',
    createdAt: '2026-01-01T00:00:00.000Z',
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(0);
    registerFallbackValue('');
  });

  group('K-P1-02 snapshot equivalence', () {
    test('equal-version unchanged ride is ui-equivalent', () {
      final a = _ride(state: 'DRIVER_ASSIGNED', version: 3);
      final b = _ride(state: 'DRIVER_ASSIGNED', version: 3);
      expect(shouldAcceptRideSnapshot(b, a), isTrue);
      expect(isRideUiEquivalent(a, b), isTrue);
    });

    test('equal-version offer status change is not equivalent', () {
      final a = [_offer(status: 'PENDING')];
      final b = [_offer(status: 'EXPIRED')];
      expect(areOfferListsUiEquivalent(a, b), isFalse);
    });

    test('equal-version offer amount change is not equivalent', () {
      final a = [_offer(amount: 20000)];
      final b = [_offer(amount: 21000)];
      expect(areOfferListsUiEquivalent(a, b), isFalse);
    });

    test('older snapshot still rejected by version gate', () {
      final current = _ride(version: 5);
      final stale = _ride(version: 4, state: 'DRIVER_ARRIVED');
      expect(shouldAcceptRideSnapshot(stale, current), isFalse);
    });
  });

  group('K-P1-02 / K-P1-03 offers apply behavior', () {
    late MockGetRideUseCase getRide;
    late MockListOffersUseCase listOffers;
    late MockSelectOfferUseCase selectOffer;

    setUp(() {
      getRide = MockGetRideUseCase();
      listOffers = MockListOffersUseCase();
      selectOffer = MockSelectOfferUseCase();
    });

    Future<OffersInboxViewModel> boot(ProviderContainer c) async {
      c.listen(offersInboxViewModelProvider('ride-1'), (_, __) {});
      final vm = c.read(offersInboxViewModelProvider('ride-1').notifier);
      await Future<void>.delayed(Duration.zero);
      await vm.refresh();
      return vm;
    }

    test('unchanged equal-version poll keeps same Ride instance', () async {
      final ride = _ride(version: 2, state: 'OFFERS_AVAILABLE');
      final offers = [_offer()];
      when(() => getRide('ride-1')).thenAnswer((_) async => ride);
      when(() => listOffers('ride-1')).thenAnswer((_) async => offers);

      final c = ProviderContainer(
        overrides: [
          getRideUseCaseProvider.overrideWithValue(getRide),
          listOffersUseCaseProvider.overrideWithValue(listOffers),
          selectOfferUseCaseProvider.overrideWithValue(selectOffer),
          failureMapperProvider
              .overrideWithValue(const _PassthroughFailureMapper()),
          offerPollingPolicyProvider.overrideWithValue(
            const OfferPollingPolicy(
              intervals: [Duration(days: 1)],
              maxLifetime: Duration(days: 1),
            ),
          ),
          idempotencyNonceStoreProvider
              .overrideWithValue(InMemoryIdempotencyNonceStore()),
        ],
      );
      addTearDown(c.dispose);

      final vm = await boot(c);
      final firstRide = c.read(offersInboxViewModelProvider('ride-1')).ride;
      final firstOffers = c.read(offersInboxViewModelProvider('ride-1')).offers;

      when(() => getRide('ride-1'))
          .thenAnswer((_) async => _ride(version: 2, state: 'OFFERS_AVAILABLE'));
      when(() => listOffers('ride-1'))
          .thenAnswer((_) async => [_offer()]);
      await vm.refresh();

      final after = c.read(offersInboxViewModelProvider('ride-1'));
      expect(identical(after.ride, firstRide), isTrue);
      expect(identical(after.offers, firstOffers), isTrue);
    });

    test('equal-version offer status change updates list', () async {
      when(() => getRide('ride-1'))
          .thenAnswer((_) async => _ride(version: 2, state: 'OFFERS_AVAILABLE'));
      when(() => listOffers('ride-1'))
          .thenAnswer((_) async => [_offer(status: 'PENDING')]);

      final c = ProviderContainer(
        overrides: [
          getRideUseCaseProvider.overrideWithValue(getRide),
          listOffersUseCaseProvider.overrideWithValue(listOffers),
          selectOfferUseCaseProvider.overrideWithValue(selectOffer),
          failureMapperProvider
              .overrideWithValue(const _PassthroughFailureMapper()),
          offerPollingPolicyProvider.overrideWithValue(
            const OfferPollingPolicy(
              intervals: [Duration(days: 1)],
              maxLifetime: Duration(days: 1),
            ),
          ),
          idempotencyNonceStoreProvider
              .overrideWithValue(InMemoryIdempotencyNonceStore()),
        ],
      );
      addTearDown(c.dispose);
      final vm = await boot(c);

      when(() => listOffers('ride-1'))
          .thenAnswer((_) async => [_offer(status: 'WITHDRAWN')]);
      await vm.refresh();
      expect(
        c.read(offersInboxViewModelProvider('ride-1')).offers.first.status,
        'WITHDRAWN',
      );
    });

    test('parallel GETs discarded when superseded', () async {
      final rideQ = <Completer<Ride>>[];
      final offersQ = <Completer<List<RideOffer>>>[];
      when(() => getRide('ride-1')).thenAnswer((_) {
        final c = Completer<Ride>();
        rideQ.add(c);
        return c.future;
      });
      when(() => listOffers('ride-1')).thenAnswer((_) {
        final c = Completer<List<RideOffer>>();
        offersQ.add(c);
        return c.future;
      });

      final c = ProviderContainer(
        overrides: [
          getRideUseCaseProvider.overrideWithValue(getRide),
          listOffersUseCaseProvider.overrideWithValue(listOffers),
          selectOfferUseCaseProvider.overrideWithValue(selectOffer),
          failureMapperProvider
              .overrideWithValue(const _PassthroughFailureMapper()),
          offerPollingPolicyProvider.overrideWithValue(
            const OfferPollingPolicy(
              intervals: [Duration(days: 1)],
              maxLifetime: Duration(days: 1),
            ),
          ),
          idempotencyNonceStoreProvider
              .overrideWithValue(InMemoryIdempotencyNonceStore()),
        ],
      );
      addTearDown(c.dispose);
      c.listen(offersInboxViewModelProvider('ride-1'), (_, __) {});
      final vm = c.read(offersInboxViewModelProvider('ride-1').notifier);

      // Complete the build()/start() boot pair.
      await Future<void>.delayed(Duration.zero);
      expect(rideQ.length, 1);
      rideQ[0].complete(_ride(version: 4, state: 'OFFERS_AVAILABLE'));
      offersQ[0].complete([_offer(id: 'boot')]);
      await Future<void>.delayed(Duration.zero);

      final a = vm.refresh();
      final b = vm.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(rideQ.length, 3);
      expect(offersQ.length, 3);

      rideQ[2].complete(_ride(version: 6, state: 'OFFERS_AVAILABLE'));
      offersQ[2].complete([_offer(id: 'new')]);
      await b;
      rideQ[1].complete(_ride(version: 5));
      offersQ[1].complete([_offer(id: 'old')]);
      await a;

      expect(c.read(offersInboxViewModelProvider('ride-1')).ride?.version, 6);
      expect(
        c.read(offersInboxViewModelProvider('ride-1')).offers.first.offerId,
        'new',
      );
    });

    test('successful select does not force reconcile GET', () async {
      when(() => getRide('ride-1'))
          .thenAnswer((_) async => _ride(version: 2, state: 'OFFERS_AVAILABLE'));
      when(() => listOffers('ride-1'))
          .thenAnswer((_) async => [_offer()]);
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
          agreedFareMinor: 20000,
          agreedOfferId: 'offer-1',
          currency: 'PKR',
        ),
      );

      final c = ProviderContainer(
        overrides: [
          getRideUseCaseProvider.overrideWithValue(getRide),
          listOffersUseCaseProvider.overrideWithValue(listOffers),
          selectOfferUseCaseProvider.overrideWithValue(selectOffer),
          failureMapperProvider
              .overrideWithValue(const _PassthroughFailureMapper()),
          offerPollingPolicyProvider.overrideWithValue(
            const OfferPollingPolicy(
              intervals: [Duration(days: 1)],
              maxLifetime: Duration(days: 1),
            ),
          ),
          idempotencyNonceStoreProvider
              .overrideWithValue(InMemoryIdempotencyNonceStore()),
        ],
      );
      addTearDown(c.dispose);
      final vm = await boot(c);
      clearInteractions(getRide);
      clearInteractions(listOffers);
      await vm.selectOffer('offer-1');

      expect(
        c.read(offersInboxViewModelProvider('ride-1')).phase,
        OffersInboxPhase.assigned,
      );
      verifyNever(() => getRide(any()));
      verifyNever(() => listOffers(any()));
    });
  });

  group('K-P1-01 clock isolation', () {
    test('clock tick does not change ActiveRideUiState identity fields',
        () async {
      final getRide = MockGetRideUseCase();
      final cancel = MockCancelRideUseCase();
      final close = MockCloseRideUseCase();
      when(() => getRide('ride-1')).thenAnswer(
        (_) async => _ride(
          state: 'DRIVER_ARRIVED',
          version: 2,
          arrivedAt: DateTime.now()
              .subtract(const Duration(minutes: 1))
              .toIso8601String(),
          assignedDriverId: 'd1',
        ),
      );

      final c = ProviderContainer(
        overrides: [
          getRideUseCaseProvider.overrideWithValue(getRide),
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
      addTearDown(c.dispose);
      c.listen(activeRideViewModelProvider('ride-1'), (_, __) {});
      final vm = c.read(activeRideViewModelProvider('ride-1').notifier);
      await Future<void>.delayed(Duration.zero);
      await vm.refresh();

      var uiNotifications = 0;
      c.listen(activeRideViewModelProvider('ride-1'), (_, __) {
        uiNotifications += 1;
      });
      final before = c.read(activeRideViewModelProvider('ride-1'));
      final clockBefore = vm.arrivedNow.value;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      final after = c.read(activeRideViewModelProvider('ride-1'));
      expect(identical(before.ride, after.ride), isTrue);
      expect(before.phase, after.phase);
      expect(vm.arrivedNow.value.isAfter(clockBefore), isTrue);
      expect(uiNotifications, 0);
    });
  });

  group('K-P2-01 lazy history', () {
    testWidgets('inactive history does not load; active loads once',
        (tester) async {
      final list = MockListRidesUseCase();
      when(
        () => list(
          limit: any(named: 'limit'),
          cursor: any(named: 'cursor'),
          status: any(named: 'status'),
          serviceType: any(named: 'serviceType'),
        ),
      ).thenAnswer(
        (_) async => const RideListPage(rides: [], nextCursor: null),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            listRidesUseCaseProvider.overrideWithValue(list),
            failureMapperProvider
                .overrideWithValue(const _PassthroughFailureMapper()),
          ],
          child: MaterialApp(
            theme: OraTheme.dark(),
            home: const RideHistoryView(active: false),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      verifyNever(
        () => list(
          limit: any(named: 'limit'),
          cursor: any(named: 'cursor'),
          status: any(named: 'status'),
          serviceType: any(named: 'serviceType'),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            listRidesUseCaseProvider.overrideWithValue(list),
            failureMapperProvider
                .overrideWithValue(const _PassthroughFailureMapper()),
          ],
          child: MaterialApp(
            theme: OraTheme.dark(),
            home: const RideHistoryView(active: true),
          ),
        ),
      );
      await tester.pump(); // build + schedule post-frame
      await tester.pump(); // run post-frame loadInitial

      // Re-entering active must not duplicate the gated initial load.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            listRidesUseCaseProvider.overrideWithValue(list),
            failureMapperProvider
                .overrideWithValue(const _PassthroughFailureMapper()),
          ],
          child: MaterialApp(
            theme: OraTheme.dark(),
            home: const RideHistoryView(active: false),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            listRidesUseCaseProvider.overrideWithValue(list),
            failureMapperProvider
                .overrideWithValue(const _PassthroughFailureMapper()),
          ],
          child: MaterialApp(
            theme: OraTheme.dark(),
            home: const RideHistoryView(active: true),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
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

  group('K-P2-04 rating parallel open', () {
    test('already rated resolves with parallel GETs', () async {
      final getRide = MockGetRideUseCase();
      final getMy = MockGetMyRatingUseCase();
      final submit = MockSubmitRatingUseCase();
      when(() => getRide(any()))
          .thenAnswer((_) async => _ride(state: 'RIDE_CLOSED'));
      when(() => getMy(any())).thenAnswer(
        (_) async => const RideRating(
          ratingId: 'r1',
          rideId: 'ride-1',
          raterId: 'p1',
          ratedId: 'd1',
          ratingType: 'passenger_rates_driver',
          stars: 4,
          createdAt: '2026-01-02T00:00:00.000Z',
        ),
      );

      final c = ProviderContainer(
        overrides: [
          getRideUseCaseProvider.overrideWithValue(getRide),
          getMyRatingUseCaseProvider.overrideWithValue(getMy),
          submitRatingUseCaseProvider.overrideWithValue(submit),
          failureMapperProvider
              .overrideWithValue(const _PassthroughFailureMapper()),
          idempotencyNonceStoreProvider
              .overrideWithValue(InMemoryIdempotencyNonceStore()),
        ],
      );
      addTearDown(c.dispose);
      c.listen(rideRatingViewModelProvider('ride-1'), (_, __) {});
      await c.read(rideRatingViewModelProvider('ride-1').notifier).load();
      expect(
        c.read(rideRatingViewModelProvider('ride-1')).phase,
        RideRatingPhase.alreadyRated,
      );
      verify(() => getRide(any())).called(1);
      verify(() => getMy(any())).called(1);
    });
  });
}
