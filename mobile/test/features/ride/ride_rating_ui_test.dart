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
import 'package:ora/features/ride/presentation/views/ride_rating_view.dart';

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

  Widget wrap() {
    final router = GoRouter(
      initialLocation: AppRoutes.rideRatingPath('ride-1'),
      routes: [
        GoRoute(
          path: AppRoutes.rideRating,
          builder: (_, __) => const RideRatingView(rideId: 'ride-1'),
        ),
        GoRoute(
          path: AppRoutes.home,
          builder: (_, __) => const Scaffold(body: Text('home')),
        ),
      ],
    );

    return ProviderScope(
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
      child: MaterialApp.router(
        theme: OraTheme.dark(),
        routerConfig: router,
      ),
    );
  }

  testWidgets('rating screen renders and submit works', (tester) async {
    when(() => getRide(any())).thenAnswer((_) async => _ride());
    when(() => getMyRating(any()))
        .thenThrow(const AppFailure.notFound());
    when(
      () => submitRating(
        rideId: any(named: 'rideId'),
        stars: any(named: 'stars'),
        operationKey: any(named: 'operationKey'),
      ),
    ).thenAnswer((_) async => _rating(stars: 4));

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Rate your ride'), findsWidgets);
    expect(find.byType(OraStarRating), findsOneWidget);
    expect(find.text('Submit rating'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('4.9'), findsNothing);
    expect(find.textContaining('average'), findsNothing);
    expect(find.textContaining('Comment'), findsNothing);

    await tester.tap(find.byIcon(Icons.star_outline_rounded).at(3));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit rating'));
    await tester.pumpAndSettle();

    expect(find.text('Thanks for rating'), findsOneWidget);
    expect(find.textContaining('submitted'), findsOneWidget);
    expect(find.text('Submit rating'), findsNothing);
  });

  testWidgets('existing rating renders read-only', (tester) async {
    when(() => getRide(any())).thenAnswer((_) async => _ride());
    when(() => getMyRating(any())).thenAnswer((_) async => _rating(stars: 3));

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.textContaining('already rated'), findsOneWidget);
    expect(find.text('Submit rating'), findsNothing);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('ineligible ride state renders honestly', (tester) async {
    when(() => getRide(any()))
        .thenAnswer((_) async => _ride(state: 'CANCELLED'));
    when(() => getMyRating(any()))
        .thenThrow(const AppFailure.notFound());

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Cannot rate this ride'), findsOneWidget);
    expect(find.text('Submit rating'), findsNothing);
  });
}
