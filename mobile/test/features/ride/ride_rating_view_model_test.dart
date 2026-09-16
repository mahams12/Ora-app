import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/core/errors/app_failure.dart';
import 'package:ora/core/errors/failure_mapper.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';
import 'package:ora/features/ride/domain/use_cases/ride_use_cases.dart';
import 'package:ora/features/ride/presentation/view_models/ride_rating_view_model.dart';

import '../../helpers/in_memory_idempotency_nonce_store.dart';

class MockGetRideUseCase extends Mock implements GetRideUseCase {}

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

Ride _ride({String state = 'RIDE_CLOSED'}) {
  return Ride(
    rideId: 'ride-1',
    passengerId: 'p1',
    state: state,
    version: 1,
    requestVersion: 1,
    category: 'easy',
    serviceType: 'ride',
    pickup: const LatLngPoint(lat: 1, lng: 2, address: 'A'),
    destination: const LatLngPoint(lat: 3, lng: 4, address: 'B'),
    pricingSnapshotId: 'snap',
    recommendedFareMinor: 20000,
    passengerOfferMinor: 20000,
    paymentMethod: 'CASH',
    passengerCount: 1,
    expiresAt: '2099-01-01T00:00:00.000Z',
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    assignedDriverId: 'd1',
  );
}

RideRating _rating({int stars = 5}) {
  return RideRating(
    ratingId: 'ride-1_passenger_rates_driver',
    rideId: 'ride-1',
    raterId: 'p1',
    ratedId: 'd1',
    ratingType: 'passenger_rates_driver',
    stars: stars,
    createdAt: '2026-01-02T00:00:00.000Z',
  );
}

void main() {
  late MockGetRideUseCase getRide;
  late MockGetMyRatingUseCase getMyRating;
  late MockSubmitRatingUseCase submitRating;

  setUpAll(() {
    registerFallbackValue('');
  });

  setUp(() {
    getRide = MockGetRideUseCase();
    getMyRating = MockGetMyRatingUseCase();
    submitRating = MockSubmitRatingUseCase();
  });

  ProviderContainer container() => ProviderContainer(
        overrides: [
          getRideUseCaseProvider.overrideWithValue(getRide),
          getMyRatingUseCaseProvider.overrideWithValue(getMyRating),
          submitRatingUseCaseProvider.overrideWithValue(submitRating),
          failureMapperProvider.overrideWithValue(
            const _PassthroughFailureMapper(),
          ),
          idempotencyNonceStoreProvider
              .overrideWithValue(InMemoryIdempotencyNonceStore()),
        ],
      );

  Future<RideRatingViewModel> boot(ProviderContainer c) async {
    c.listen(rideRatingViewModelProvider('ride-1'), (_, __) {});
    final vm = c.read(rideRatingViewModelProvider('ride-1').notifier);
    await vm.load();
    return vm;
  }

  test('no existing rating → ready to rate', () async {
    when(() => getRide(any())).thenAnswer((_) async => _ride());
    when(() => getMyRating(any()))
        .thenThrow(const AppFailure.notFound(message: 'none'));

    final c = container();
    addTearDown(c.dispose);
    await boot(c);
    final s = c.read(rideRatingViewModelProvider('ride-1'));
    expect(s.phase, RideRatingPhase.readyToRate);
    expect(s.selectedStars, 0);
  });

  test('existing rating → already rated read-only', () async {
    when(() => getRide(any())).thenAnswer((_) async => _ride());
    when(() => getMyRating(any())).thenAnswer((_) async => _rating(stars: 4));

    final c = container();
    addTearDown(c.dispose);
    await boot(c);
    final s = c.read(rideRatingViewModelProvider('ride-1'));
    expect(s.phase, RideRatingPhase.alreadyRated);
    expect(s.displayStars, 4);
    expect(s.isReadOnly, isTrue);
    expect(s.canSubmit, isFalse);
  });

  test('selecting 1 through 5 stars', () async {
    when(() => getRide(any())).thenAnswer((_) async => _ride());
    when(() => getMyRating(any()))
        .thenThrow(const AppFailure.notFound());

    final c = container();
    addTearDown(c.dispose);
    final vm = await boot(c);
    for (var i = 1; i <= 5; i++) {
      vm.selectStars(i);
      expect(c.read(rideRatingViewModelProvider('ride-1')).selectedStars, i);
      expect(c.read(rideRatingViewModelProvider('ride-1')).canSubmit, isTrue);
    }
  });

  test('successful submission', () async {
    when(() => getRide(any())).thenAnswer((_) async => _ride());
    when(() => getMyRating(any()))
        .thenThrow(const AppFailure.notFound());
    when(
      () => submitRating(
        rideId: any(named: 'rideId'),
        stars: any(named: 'stars'),
        operationKey: any(named: 'operationKey'),
      ),
    ).thenAnswer((_) async => _rating(stars: 5));

    final c = container();
    addTearDown(c.dispose);
    final vm = await boot(c);
    vm.selectStars(5);
    await vm.submit();
    final s = c.read(rideRatingViewModelProvider('ride-1'));
    expect(s.phase, RideRatingPhase.success);
    expect(s.submittedRating?.stars, 5);
    expect(s.isReadOnly, isTrue);
    verify(
      () => submitRating(
        rideId: 'ride-1',
        stars: 5,
        operationKey: any(named: 'operationKey'),
      ),
    ).called(1);
  });

  test('idempotency key reused across retries of same submit session', () async {
    when(() => getRide(any())).thenAnswer((_) async => _ride());
    when(() => getMyRating(any()))
        .thenThrow(const AppFailure.notFound());
    final keys = <String>[];
    when(
      () => submitRating(
        rideId: any(named: 'rideId'),
        stars: any(named: 'stars'),
        operationKey: any(named: 'operationKey'),
      ),
    ).thenAnswer((invocation) async {
      keys.add(invocation.namedArguments[#operationKey] as String);
      throw const AppFailure.network(message: 'offline');
    });

    final c = container();
    addTearDown(c.dispose);
    final vm = await boot(c);
    vm.selectStars(3);
    await vm.submit();
    await vm.submit();
    expect(keys, hasLength(2));
    expect(keys[0], keys[1]);
  });

  test('ALREADY_RATED fetches existing and becomes read-only', () async {
    when(() => getRide(any())).thenAnswer((_) async => _ride());
    when(() => getMyRating(any()))
        .thenThrow(const AppFailure.notFound());
    when(
      () => submitRating(
        rideId: any(named: 'rideId'),
        stars: any(named: 'stars'),
        operationKey: any(named: 'operationKey'),
      ),
    ).thenThrow(
      const AppFailure.conflict(message: 'exists', code: 'ALREADY_RATED'),
    );

    final c = container();
    addTearDown(c.dispose);
    final vm = await boot(c);
    when(() => getMyRating(any())).thenAnswer((_) async => _rating(stars: 2));
    vm.selectStars(5);
    await vm.submit();
    final s = c.read(rideRatingViewModelProvider('ride-1'));
    expect(s.phase, RideRatingPhase.alreadyRated);
    expect(s.displayStars, 2);
    expect(s.isReadOnly, isTrue);
  });

  test('STATE_CONFLICT → ineligible', () async {
    when(() => getRide(any())).thenAnswer((_) async => _ride());
    when(() => getMyRating(any()))
        .thenThrow(const AppFailure.notFound());
    when(
      () => submitRating(
        rideId: any(named: 'rideId'),
        stars: any(named: 'stars'),
        operationKey: any(named: 'operationKey'),
      ),
    ).thenThrow(
      const AppFailure.conflict(message: 'bad state', code: 'STATE_CONFLICT'),
    );

    final c = container();
    addTearDown(c.dispose);
    final vm = await boot(c);
    vm.selectStars(4);
    await vm.submit();
    expect(
      c.read(rideRatingViewModelProvider('ride-1')).phase,
      RideRatingPhase.ineligible,
    );
  });

  test('soft-ineligible for CANCELLED', () async {
    when(() => getRide(any()))
        .thenAnswer((_) async => _ride(state: 'CANCELLED'));
    when(() => getMyRating(any()))
        .thenThrow(const AppFailure.notFound());

    final c = container();
    addTearDown(c.dispose);
    await boot(c);
    expect(
      c.read(rideRatingViewModelProvider('ride-1')).phase,
      RideRatingPhase.ineligible,
    );
  });

  test('getMyRating network failure → fatal', () async {
    when(() => getRide(any())).thenAnswer((_) async => _ride());
    when(() => getMyRating(any()))
        .thenThrow(const AppFailure.network(message: 'offline'));

    final c = container();
    addTearDown(c.dispose);
    await boot(c);
    expect(
      c.read(rideRatingViewModelProvider('ride-1')).phase,
      RideRatingPhase.fatalError,
    );
  });

  test('authorization failure on submit returns to ready with error', () async {
    when(() => getRide(any())).thenAnswer((_) async => _ride());
    when(() => getMyRating(any()))
        .thenThrow(const AppFailure.notFound());
    when(
      () => submitRating(
        rideId: any(named: 'rideId'),
        stars: any(named: 'stars'),
        operationKey: any(named: 'operationKey'),
      ),
    ).thenThrow(const AppFailure.forbidden(message: 'nope'));

    final c = container();
    addTearDown(c.dispose);
    final vm = await boot(c);
    vm.selectStars(1);
    await vm.submit();
    final s = c.read(rideRatingViewModelProvider('ride-1'));
    expect(s.phase, RideRatingPhase.readyToRate);
    expect(s.errorMessage, 'nope');
  });

  test('cannot select stars when already rated', () async {
    when(() => getRide(any())).thenAnswer((_) async => _ride());
    when(() => getMyRating(any())).thenAnswer((_) async => _rating(stars: 3));

    final c = container();
    addTearDown(c.dispose);
    final vm = await boot(c);
    vm.selectStars(5);
    expect(c.read(rideRatingViewModelProvider('ride-1')).displayStars, 3);
  });
}
