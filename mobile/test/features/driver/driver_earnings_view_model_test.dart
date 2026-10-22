import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/core/errors/app_failure.dart';
import 'package:ora/core/errors/failure_mapper.dart';
import 'package:ora/features/driver/presentation/view_models/driver_earnings_view_model.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';
import 'package:ora/features/ride/domain/use_cases/ride_use_cases.dart';

class MockListRidesUseCase extends Mock implements ListRidesUseCase {}

class _PassthroughFailureMapper extends FailureMapper {
  const _PassthroughFailureMapper();

  @override
  AppFailure fromException(Object error, [StackTrace? stackTrace]) {
    if (error is AppFailure) return error;
    return AppFailure.unknown(message: error.toString());
  }
}

Ride _ride({
  required String id,
  String state = 'RIDE_CLOSED',
  int? agreedFareMinor,
}) {
  return Ride(
    rideId: id,
    passengerId: 'p1',
    assignedDriverId: 'd1',
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
    createdAt: '2026-03-01T10:00:00.000Z',
    updatedAt: '2026-03-01T10:00:00.000Z',
    closedAt: '2026-03-01T11:00:00.000Z',
    agreedFareMinor: agreedFareMinor,
    agreedFareCurrency: agreedFareMinor != null ? 'PKR' : null,
  );
}

void main() {
  late MockListRidesUseCase listRides;

  setUpAll(() {
    registerFallbackValue('');
  });

  setUp(() {
    listRides = MockListRidesUseCase();
  });

  ProviderContainer container() {
    return ProviderContainer(
      overrides: [
        listRidesUseCaseProvider.overrideWithValue(listRides),
        failureMapperProvider.overrideWithValue(
          const _PassthroughFailureMapper(),
        ),
      ],
    );
  }

  void stubPages(Map<String?, RideListPage> pages) {
    when(
      () => listRides(
        limit: any(named: 'limit'),
        cursor: any(named: 'cursor'),
        status: any(named: 'status'),
        serviceType: any(named: 'serviceType'),
      ),
    ).thenAnswer((invocation) async {
      final cursor = invocation.namedArguments[#cursor] as String?;
      return pages[cursor] ?? const RideListPage(rides: [], nextCursor: null);
    });
  }

  test('requests only completed status — driver scope is enforced server-side',
      () async {
    stubPages({
      null: RideListPage(
        rides: [_ride(id: 'r1', agreedFareMinor: 50000)],
        nextCursor: null,
      ),
    });

    final c = container();
    addTearDown(c.dispose);
    final vm = c.read(driverEarningsViewModelProvider.notifier);
    await vm.loadInitial();

    verify(
      () => listRides(
        limit: 50,
        cursor: null,
        status: 'completed',
        serviceType: null,
      ),
    ).called(1);
    // Non-completed filters must never be sent from this surface.
    verifyNever(
      () => listRides(
        limit: any(named: 'limit'),
        cursor: any(named: 'cursor'),
        status: 'all',
        serviceType: any(named: 'serviceType'),
      ),
    );
  });

  test('totals aggregate verified fares; missing fares are counted', () async {
    stubPages({
      null: RideListPage(
        rides: [
          _ride(id: 'r1', agreedFareMinor: 50000),
          _ride(id: 'r2', agreedFareMinor: 30000),
          _ride(id: 'r3'), // completed, no fare
        ],
        nextCursor: null,
      ),
    });

    final c = container();
    addTearDown(c.dispose);
    await c.read(driverEarningsViewModelProvider.notifier).loadInitial();
    final state = c.read(driverEarningsViewModelProvider);

    expect(state.phase, DriverEarningsPhase.ready);
    final summary = state.summary!;
    expect(summary.completedRideCount, 3);
    expect(summary.allTime.faresMinor, 80000);
    expect(summary.ridesMissingFare, 1);
  });

  test('empty history yields empty phase', () async {
    stubPages({null: const RideListPage(rides: [], nextCursor: null)});

    final c = container();
    addTearDown(c.dispose);
    await c.read(driverEarningsViewModelProvider.notifier).loadInitial();
    expect(
      c.read(driverEarningsViewModelProvider).phase,
      DriverEarningsPhase.empty,
    );
  });

  test('fatal error then retry recovers', () async {
    var calls = 0;
    when(
      () => listRides(
        limit: any(named: 'limit'),
        cursor: any(named: 'cursor'),
        status: any(named: 'status'),
        serviceType: any(named: 'serviceType'),
      ),
    ).thenAnswer((_) async {
      calls++;
      if (calls == 1) throw const AppFailure.network(message: 'offline');
      return RideListPage(
        rides: [_ride(id: 'r1', agreedFareMinor: 10000)],
        nextCursor: null,
      );
    });

    final c = container();
    addTearDown(c.dispose);
    final vm = c.read(driverEarningsViewModelProvider.notifier);
    await vm.loadInitial();
    expect(
      c.read(driverEarningsViewModelProvider).phase,
      DriverEarningsPhase.fatalError,
    );
    expect(
      c.read(driverEarningsViewModelProvider).errorMessage,
      'offline',
    );

    await vm.retry();
    expect(
      c.read(driverEarningsViewModelProvider).phase,
      DriverEarningsPhase.ready,
    );
  });

  test('auto-scan follows pages and marks scanCapped while history remains',
      () async {
    // 5 non-exhausting pages → scan stops at the 200-ride cap with
    // scanCapped true; loadMore continues and clears the flag.
    RideListPage page(int n, String? next) => RideListPage(
          rides: List.generate(
            50,
            (i) => _ride(id: 'p${n}r$i', agreedFareMinor: 100),
          ),
          nextCursor: next,
        );
    stubPages({
      null: page(1, 'c1'),
      'c1': page(2, 'c2'),
      'c2': page(3, 'c3'),
      'c3': page(4, 'c4'),
      'c4': page(5, null),
    });

    final c = container();
    addTearDown(c.dispose);
    final vm = c.read(driverEarningsViewModelProvider.notifier);
    await vm.loadInitial();

    var state = c.read(driverEarningsViewModelProvider);
    expect(state.rides.length, 200); // scan cap
    expect(state.scanCapped, isTrue);
    expect(state.hasMore, isTrue);
    expect(state.summary!.allTime.faresMinor, 20000);

    await vm.loadMore();
    state = c.read(driverEarningsViewModelProvider);
    expect(state.rides.length, 250);
    expect(state.scanCapped, isFalse);
    expect(state.hasMore, isFalse);
  });

  test('refresh re-scans and replaces the list', () async {
    var returnOld = true;
    when(
      () => listRides(
        limit: any(named: 'limit'),
        cursor: any(named: 'cursor'),
        status: any(named: 'status'),
        serviceType: any(named: 'serviceType'),
      ),
    ).thenAnswer(
      (_) async => RideListPage(
        rides: [_ride(id: returnOld ? 'old' : 'new', agreedFareMinor: 100)],
        nextCursor: null,
      ),
    );

    final c = container();
    addTearDown(c.dispose);
    final vm = c.read(driverEarningsViewModelProvider.notifier);
    await vm.loadInitial();
    expect(
      c.read(driverEarningsViewModelProvider).rides.single.rideId,
      'old',
    );

    returnOld = false;
    await vm.refresh();
    expect(
      c.read(driverEarningsViewModelProvider).rides.single.rideId,
      'new',
    );
  });
}
