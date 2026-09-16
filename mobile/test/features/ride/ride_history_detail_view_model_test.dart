import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/core/errors/app_failure.dart';
import 'package:ora/core/errors/failure_mapper.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';
import 'package:ora/features/ride/domain/use_cases/ride_use_cases.dart';
import 'package:ora/features/ride/presentation/view_models/ride_history_detail_view_model.dart';

class MockGetRideUseCase extends Mock implements GetRideUseCase {}

class _PassthroughFailureMapper extends FailureMapper {
  const _PassthroughFailureMapper();

  @override
  AppFailure fromException(Object error, [StackTrace? stackTrace]) {
    if (error is AppFailure) return error;
    return AppFailure.unknown(message: error.toString());
  }
}

Ride _ride(String state) {
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
  );
}

void main() {
  late MockGetRideUseCase getRide;

  setUpAll(() {
    registerFallbackValue('');
  });

  setUp(() {
    getRide = MockGetRideUseCase();
  });

  ProviderContainer container() => ProviderContainer(
        overrides: [
          getRideUseCaseProvider.overrideWithValue(getRide),
          failureMapperProvider.overrideWithValue(
            const _PassthroughFailureMapper(),
          ),
        ],
      );

  Future<void> settle(ProviderContainer c) async {
    await c
        .read(rideHistoryDetailViewModelProvider('ride-1').notifier)
        .load();
  }

  test('terminal ride stays on detail', () async {
    when(() => getRide(any())).thenAnswer((_) async => _ride('RIDE_CLOSED'));
    final c = container();
    addTearDown(c.dispose);
    await settle(c);
    final s = c.read(rideHistoryDetailViewModelProvider('ride-1'));
    expect(s.phase, RideHistoryDetailPhase.ready);
    expect(s.ride?.state, 'RIDE_CLOSED');
  });

  test('active ride redirects to active', () async {
    when(() => getRide(any()))
        .thenAnswer((_) async => _ride('DRIVER_ARRIVED'));
    final c = container();
    addTearDown(c.dispose);
    await settle(c);
    expect(
      c.read(rideHistoryDetailViewModelProvider('ride-1')).phase,
      RideHistoryDetailPhase.redirectActive,
    );
  });

  test('marketplace redirects to offers', () async {
    when(() => getRide(any()))
        .thenAnswer((_) async => _ride('SEARCHING'));
    final c = container();
    addTearDown(c.dispose);
    await settle(c);
    expect(
      c.read(rideHistoryDetailViewModelProvider('ride-1')).phase,
      RideHistoryDetailPhase.redirectOffers,
    );
  });

  test('error then retry', () async {
    var calls = 0;
    when(() => getRide(any())).thenAnswer((_) async {
      calls += 1;
      if (calls == 1) {
        throw const AppFailure.network(message: 'offline');
      }
      return _ride('CANCELLED');
    });
    final c = container();
    addTearDown(c.dispose);
    await settle(c);
    expect(
      c.read(rideHistoryDetailViewModelProvider('ride-1')).phase,
      RideHistoryDetailPhase.fatalError,
    );
    await c.read(rideHistoryDetailViewModelProvider('ride-1').notifier).retry();
    expect(
      c.read(rideHistoryDetailViewModelProvider('ride-1')).phase,
      RideHistoryDetailPhase.ready,
    );
  });
}
