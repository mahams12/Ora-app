import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/app/router/routes.dart';
import 'package:ora/app/theme/theme.dart';
import 'package:ora/core/errors/app_failure.dart';
import 'package:ora/core/errors/failure_mapper.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';
import 'package:ora/features/ride/domain/use_cases/ride_use_cases.dart';
import 'package:ora/features/ride/presentation/views/ride_history_view.dart';

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
    pickup: const LatLngPoint(lat: 1, lng: 2, address: 'Gulberg'),
    destination: const LatLngPoint(lat: 3, lng: 4, address: 'Liberty'),
    pricingSnapshotId: 'snap',
    recommendedFareMinor: 20000,
    passengerOfferMinor: 20000,
    paymentMethod: 'CASH',
    passengerCount: 1,
    expiresAt: '2099-01-01T00:00:00.000Z',
    createdAt: '2026-01-01T12:00:00.000Z',
    updatedAt: '2026-01-01T12:00:00.000Z',
    agreedFareMinor: agreedFareMinor,
    agreedFareCurrency: agreedFareMinor != null ? 'PKR' : null,
  );
}

void main() {
  late MockListRidesUseCase listRides;
  late List<String> navigated;

  setUpAll(() {
    registerFallbackValue('');
  });

  setUp(() {
    listRides = MockListRidesUseCase();
    navigated = [];
  });

  Widget wrap(Widget child) {
    final router = GoRouter(
      initialLocation: '/history',
      routes: [
        GoRoute(path: '/history', builder: (_, __) => child),
        GoRoute(
          path: AppRoutes.offersInbox,
          builder: (_, state) {
            navigated.add('offers:${state.pathParameters['rideId']}');
            return const Scaffold(body: Text('offers'));
          },
        ),
        GoRoute(
          path: AppRoutes.activeRide,
          builder: (_, state) {
            navigated.add('active:${state.pathParameters['rideId']}');
            return const Scaffold(body: Text('active'));
          },
        ),
        GoRoute(
          path: AppRoutes.rideHistoryDetail,
          builder: (_, state) {
            navigated.add('detail:${state.pathParameters['rideId']}');
            return const Scaffold(body: Text('detail'));
          },
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        listRidesUseCaseProvider.overrideWithValue(listRides),
        failureMapperProvider.overrideWithValue(
          const _PassthroughFailureMapper(),
        ),
      ],
      child: MaterialApp.router(
        theme: OraTheme.dark(),
        routerConfig: router,
      ),
    );
  }

  testWidgets('renders rides and honest filters — no fake rating/map/ETA', (
    tester,
  ) async {
    when(
      () => listRides(
        limit: any(named: 'limit'),
        cursor: any(named: 'cursor'),
        status: any(named: 'status'),
        serviceType: any(named: 'serviceType'),
      ),
    ).thenAnswer(
      (_) async => RideListPage(
        rides: [
          _ride(id: 'r1', state: 'RIDE_CLOSED', agreedFareMinor: 21000),
        ],
        nextCursor: null,
      ),
    );

    await tester.pumpWidget(wrap(const RideHistoryView(active: true)));
    await tester.pumpAndSettle();

    expect(find.text('My rides'), findsOneWidget);
    expect(find.textContaining('not wired yet'), findsNothing);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('Closed'), findsOneWidget);
    expect(find.textContaining('Gulberg'), findsOneWidget);
    expect(find.textContaining('Agreed fare'), findsOneWidget);
    expect(find.textContaining('4.9'), findsNothing);
    expect(find.textContaining('ETA'), findsNothing);
    expect(find.text('Submit rating'), findsNothing);
    expect(find.textContaining('km away'), findsNothing);
  });

  testWidgets('empty state', (tester) async {
    when(
      () => listRides(
        limit: any(named: 'limit'),
        cursor: any(named: 'cursor'),
        status: any(named: 'status'),
        serviceType: any(named: 'serviceType'),
      ),
    ).thenAnswer((_) async => const RideListPage(rides: [], nextCursor: null));

    await tester.pumpWidget(wrap(const RideHistoryView(active: true)));
    await tester.pumpAndSettle();
    expect(find.text('No rides here'), findsOneWidget);
  });

  testWidgets('error state with retry', (tester) async {
    when(
      () => listRides(
        limit: any(named: 'limit'),
        cursor: any(named: 'cursor'),
        status: any(named: 'status'),
        serviceType: any(named: 'serviceType'),
      ),
    ).thenThrow(const AppFailure.network(message: 'offline'));

    await tester.pumpWidget(wrap(const RideHistoryView(active: true)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Couldn’t load rides'), findsOneWidget);
  });

  testWidgets('load more works', (tester) async {
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
          nextCursor: 'next',
        );
      }
      return RideListPage(rides: [_ride(id: 'r2')], nextCursor: null);
    });

    await tester.pumpWidget(wrap(const RideHistoryView(active: true)));
    await tester.pumpAndSettle();
    expect(find.text('Load more'), findsOneWidget);

    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.text('End of list from server'), findsOneWidget);
  });

  testWidgets('navigation by server state — offers and active', (tester) async {
    when(
      () => listRides(
        limit: any(named: 'limit'),
        cursor: any(named: 'cursor'),
        status: any(named: 'status'),
        serviceType: any(named: 'serviceType'),
      ),
    ).thenAnswer(
      (_) async => RideListPage(
        rides: [_ride(id: 'o1', state: 'OFFERS_AVAILABLE')],
        nextCursor: null,
      ),
    );

    await tester.pumpWidget(wrap(const RideHistoryView(active: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Gulberg'));
    await tester.pumpAndSettle();
    expect(navigated, ['offers:o1']);
  });

  testWidgets('terminal ride navigates to detail via address tap', (
    tester,
  ) async {
    when(
      () => listRides(
        limit: any(named: 'limit'),
        cursor: any(named: 'cursor'),
        status: any(named: 'status'),
        serviceType: any(named: 'serviceType'),
      ),
    ).thenAnswer(
      (_) async => RideListPage(
        rides: [_ride(id: 'd1', state: 'EXPIRED')],
        nextCursor: null,
      ),
    );

    await tester.pumpWidget(wrap(const RideHistoryView(active: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Gulberg'));
    await tester.pumpAndSettle();
    expect(navigated, ['detail:d1']);
  });

  testWidgets('active ride navigates to active route', (tester) async {
    when(
      () => listRides(
        limit: any(named: 'limit'),
        cursor: any(named: 'cursor'),
        status: any(named: 'status'),
        serviceType: any(named: 'serviceType'),
      ),
    ).thenAnswer(
      (_) async => RideListPage(
        rides: [_ride(id: 'a1', state: 'RIDE_STARTED')],
        nextCursor: null,
      ),
    );

    await tester.pumpWidget(wrap(const RideHistoryView(active: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Gulberg'));
    await tester.pumpAndSettle();
    expect(navigated, ['active:a1']);
  });

  testWidgets('offers state navigates to offers route', (tester) async {
    when(
      () => listRides(
        limit: any(named: 'limit'),
        cursor: any(named: 'cursor'),
        status: any(named: 'status'),
        serviceType: any(named: 'serviceType'),
      ),
    ).thenAnswer(
      (_) async => RideListPage(
        rides: [_ride(id: 'o1', state: 'SEARCHING')],
        nextCursor: null,
      ),
    );

    await tester.pumpWidget(wrap(const RideHistoryView(active: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Gulberg'));
    await tester.pumpAndSettle();
    expect(navigated, ['offers:o1']);
  });

  testWidgets('status filter chip triggers completed query', (tester) async {
    final statuses = <String?>[];
    when(
      () => listRides(
        limit: any(named: 'limit'),
        cursor: any(named: 'cursor'),
        status: any(named: 'status'),
        serviceType: any(named: 'serviceType'),
      ),
    ).thenAnswer((invocation) async {
      statuses.add(invocation.namedArguments[#status] as String?);
      return const RideListPage(rides: [], nextCursor: null);
    });

    await tester.pumpWidget(wrap(const RideHistoryView(active: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    expect(statuses, contains('completed'));
  });
}
