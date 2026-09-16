import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/core/errors/app_failure.dart';
import 'package:ora/core/errors/failure_mapper.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';
import 'package:ora/features/ride/domain/use_cases/ride_use_cases.dart';
import 'package:ora/features/ride/presentation/history/ride_history_display.dart';
import 'package:ora/features/ride/presentation/view_models/ride_history_view_model.dart';

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
        failureMapperProvider.overrideWithValue(const _PassthroughFailureMapper()),
      ],
    );
  }

  Future<RideHistoryViewModel> boot(ProviderContainer c) async {
    final vm = c.read(rideHistoryViewModelProvider.notifier);
    await vm.loadInitial();
    return vm;
  }

  test('destination helpers', () {
    expect(
      rideHistoryDestinationFor('OFFERS_AVAILABLE'),
      RideHistoryDestination.offers,
    );
    expect(
      rideHistoryDestinationFor('DRIVER_EN_ROUTE'),
      RideHistoryDestination.active,
    );
    expect(
      rideHistoryDestinationFor('RIDE_CLOSED'),
      RideHistoryDestination.detail,
    );
    expect(rideHistoryDestinationFor('EXPIRED'), RideHistoryDestination.detail);
  });

  test('initial load success', () async {
    when(
      () => listRides(
        limit: any(named: 'limit'),
        cursor: any(named: 'cursor'),
        status: any(named: 'status'),
        serviceType: any(named: 'serviceType'),
      ),
    ).thenAnswer(
      (_) async => RideListPage(rides: [_ride(id: 'r1')], nextCursor: null),
    );

    final c = container();
    addTearDown(c.dispose);
    await boot(c);
    final state = c.read(rideHistoryViewModelProvider);

    expect(state.phase, RideHistoryPhase.ready);
    expect(state.rides.single.rideId, 'r1');
    expect(state.rides.single.state, 'RIDE_CLOSED');
    expect(state.hasMore, isFalse);
    verify(
      () => listRides(
        limit: 10,
        cursor: null,
        status: 'all',
        serviceType: null,
      ),
    ).called(1);
  });

  test('empty list', () async {
    when(
      () => listRides(
        limit: any(named: 'limit'),
        cursor: any(named: 'cursor'),
        status: any(named: 'status'),
        serviceType: any(named: 'serviceType'),
      ),
    ).thenAnswer((_) async => const RideListPage(rides: [], nextCursor: null));

    final c = container();
    addTearDown(c.dispose);
    await boot(c);
    expect(c.read(rideHistoryViewModelProvider).phase, RideHistoryPhase.empty);
  });

  test('failure then retry', () async {
    var calls = 0;
    when(
      () => listRides(
        limit: any(named: 'limit'),
        cursor: any(named: 'cursor'),
        status: any(named: 'status'),
        serviceType: any(named: 'serviceType'),
      ),
    ).thenAnswer((_) async {
      calls += 1;
      if (calls == 1) {
        throw const AppFailure.network(message: 'offline');
      }
      return RideListPage(rides: [_ride(id: 'r2')], nextCursor: null);
    });

    final c = container();
    addTearDown(c.dispose);
    final vm = await boot(c);
    expect(c.read(rideHistoryViewModelProvider).phase, RideHistoryPhase.fatalError);

    await vm.retry();
    expect(c.read(rideHistoryViewModelProvider).phase, RideHistoryPhase.ready);
    expect(c.read(rideHistoryViewModelProvider).rides.single.rideId, 'r2');
  });

  test('pull-to-refresh replaces list', () async {
    when(
      () => listRides(
        limit: any(named: 'limit'),
        cursor: any(named: 'cursor'),
        status: any(named: 'status'),
        serviceType: any(named: 'serviceType'),
      ),
    ).thenAnswer((invocation) async {
      final cursor = invocation.namedArguments[#cursor] as String?;
      if (cursor == null) {
        return RideListPage(rides: [_ride(id: 'old')], nextCursor: null);
      }
      return const RideListPage(rides: [], nextCursor: null);
    });

    final c = container();
    addTearDown(c.dispose);
    final vm = await boot(c);
    expect(c.read(rideHistoryViewModelProvider).rides.single.rideId, 'old');

    when(
      () => listRides(
        limit: any(named: 'limit'),
        cursor: any(named: 'cursor'),
        status: any(named: 'status'),
        serviceType: any(named: 'serviceType'),
      ),
    ).thenAnswer(
      (_) async => RideListPage(rides: [_ride(id: 'new')], nextCursor: null),
    );

    await vm.refresh();
    expect(c.read(rideHistoryViewModelProvider).rides.single.rideId, 'new');
  });

  test('pagination appends and stops when nextCursor null', () async {
    when(
      () => listRides(
        limit: any(named: 'limit'),
        cursor: any(named: 'cursor'),
        status: any(named: 'status'),
        serviceType: any(named: 'serviceType'),
      ),
    ).thenAnswer((invocation) async {
      final cursor = invocation.namedArguments[#cursor] as String?;
      if (cursor == null) {
        return RideListPage(
          rides: [_ride(id: 'r1')],
          nextCursor: 'cursor-a',
        );
      }
      expect(cursor, 'cursor-a');
      return RideListPage(rides: [_ride(id: 'r2')], nextCursor: null);
    });

    final c = container();
    addTearDown(c.dispose);
    final vm = await boot(c);
    expect(c.read(rideHistoryViewModelProvider).hasMore, isTrue);

    await vm.loadMore();
    final state = c.read(rideHistoryViewModelProvider);
    expect(state.rides.map((r) => r.rideId), ['r1', 'r2']);
    expect(state.hasMore, isFalse);

    await vm.loadMore(); // no-op
    verify(
      () => listRides(
        limit: any(named: 'limit'),
        cursor: any(named: 'cursor'),
        status: any(named: 'status'),
        serviceType: any(named: 'serviceType'),
      ),
    ).called(2);
  });

  test('duplicate load-more prevention', () async {
    final gate = Completer<RideListPage>();
    when(
      () => listRides(
        limit: any(named: 'limit'),
        cursor: any(named: 'cursor'),
        status: any(named: 'status'),
        serviceType: any(named: 'serviceType'),
      ),
    ).thenAnswer((invocation) async {
      final cursor = invocation.namedArguments[#cursor] as String?;
      if (cursor == null) {
        return RideListPage(
          rides: [_ride(id: 'r1')],
          nextCursor: 'c1',
        );
      }
      return gate.future;
    });

    final c = container();
    addTearDown(c.dispose);
    final vm = await boot(c);

    final first = vm.loadMore();
    final second = vm.loadMore();
    gate.complete(RideListPage(rides: [_ride(id: 'r2')], nextCursor: null));
    await Future.wait([first, second]);

    verify(
      () => listRides(
        limit: any(named: 'limit'),
        cursor: 'c1',
        status: any(named: 'status'),
        serviceType: any(named: 'serviceType'),
      ),
    ).called(1);
  });

  test('status filter resets cursor and requeries', () async {
    final statuses = <String?>[];
    final cursors = <String?>[];
    when(
      () => listRides(
        limit: any(named: 'limit'),
        cursor: any(named: 'cursor'),
        status: any(named: 'status'),
        serviceType: any(named: 'serviceType'),
      ),
    ).thenAnswer((invocation) async {
      statuses.add(invocation.namedArguments[#status] as String?);
      cursors.add(invocation.namedArguments[#cursor] as String?);
      return RideListPage(
        rides: [_ride(id: 'r-${statuses.length}')],
        nextCursor: statuses.length == 1 ? 'keep' : null,
      );
    });

    final c = container();
    addTearDown(c.dispose);
    final vm = await boot(c);
    expect(c.read(rideHistoryViewModelProvider).nextCursor, 'keep');

    await vm.setStatus('completed');
    expect(statuses, ['all', 'completed']);
    expect(cursors.last, isNull);
    expect(c.read(rideHistoryViewModelProvider).status, 'completed');
    expect(c.read(rideHistoryViewModelProvider).nextCursor, isNull);
  });

  test('serviceType filter resets cursor', () async {
    final types = <String?>[];
    when(
      () => listRides(
        limit: any(named: 'limit'),
        cursor: any(named: 'cursor'),
        status: any(named: 'status'),
        serviceType: any(named: 'serviceType'),
      ),
    ).thenAnswer((invocation) async {
      types.add(invocation.namedArguments[#serviceType] as String?);
      return RideListPage(rides: [_ride(id: 'r')], nextCursor: 'x');
    });

    final c = container();
    addTearDown(c.dispose);
    final vm = await boot(c);
    await vm.setServiceType('courier');
    expect(types, [null, 'courier']);
    expect(c.read(rideHistoryViewModelProvider).serviceType, 'courier');
  });

  test('preserves server state exactly', () async {
    when(
      () => listRides(
        limit: any(named: 'limit'),
        cursor: any(named: 'cursor'),
        status: any(named: 'status'),
        serviceType: any(named: 'serviceType'),
      ),
    ).thenAnswer(
      (_) async => RideListPage(
        rides: [_ride(id: 'r1', state: 'NO_SHOW')],
        nextCursor: null,
      ),
    );

    final c = container();
    addTearDown(c.dispose);
    await boot(c);
    expect(c.read(rideHistoryViewModelProvider).rides.single.state, 'NO_SHOW');
  });
}
