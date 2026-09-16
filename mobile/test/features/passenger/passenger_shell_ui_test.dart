import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/app/router/routes.dart';
import 'package:ora/app/theme/theme.dart';
import 'package:ora/features/auth/domain/entities/auth_user.dart';
import 'package:ora/features/auth/domain/use_cases/get_current_user_use_case.dart';
import 'package:ora/features/auth/domain/use_cases/logout_use_case.dart';
import 'package:ora/features/passenger/presentation/views/home_shell_view.dart';
import 'package:ora/features/passenger/presentation/widgets/passenger_bottom_nav.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';
import 'package:ora/features/ride/domain/use_cases/ride_use_cases.dart';
import 'package:ora/features/ride/presentation/views/ride_request_view.dart';

class MockLogoutUseCase extends Mock implements LogoutUseCase {}

class MockGetCurrentUserUseCase extends Mock implements GetCurrentUserUseCase {}

class MockCreateRideUseCase extends Mock implements CreateRideUseCase {}

class MockListRidesUseCase extends Mock implements ListRidesUseCase {}

Widget _wrapShell({
  List<Override> overrides = const [],
  Size size = const Size(390, 844),
  double textScale = 1,
}) {
  final router = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (_, __) => const HomeShellView(),
      ),
      GoRoute(
        path: AppRoutes.rideRequest,
        builder: (context, state) => RideRequestView(
          initialCategoryId: state.uri.queryParameters['category'],
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: overrides,
    child: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: MaterialApp.router(
        theme: OraTheme.dark(),
        routerConfig: router,
      ),
    ),
  );
}

List<Override> _baseOverrides({
  MockCreateRideUseCase? createRide,
  MockListRidesUseCase? listRides,
}) {
  final logout = MockLogoutUseCase();
  final getUser = MockGetCurrentUserUseCase();
  when(() => logout()).thenAnswer((_) async {});
  when(() => getUser()).thenAnswer(
    (_) async => const AuthUser(
      uid: 'u1',
      phoneNumber: '+923001234567',
      isEmailVerified: false,
      displayName: 'Ayesha Khan',
    ),
  );

  final list = listRides ?? MockListRidesUseCase();
  when(
    () => list(
      limit: any(named: 'limit'),
      cursor: any(named: 'cursor'),
      status: any(named: 'status'),
      serviceType: any(named: 'serviceType'),
    ),
  ).thenAnswer((_) async => const RideListPage(rides: [], nextCursor: null));

  return [
    logoutUseCaseProvider.overrideWithValue(logout),
    getCurrentUserUseCaseProvider.overrideWithValue(getUser),
    listRidesUseCaseProvider.overrideWithValue(list),
    if (createRide != null)
      createRideUseCaseProvider.overrideWithValue(createRide),
  ];
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
    registerFallbackValue('');
  });

  testWidgets('passenger shell renders Home and bottom nav', (tester) async {
    await tester.pumpWidget(_wrapShell(overrides: _baseOverrides()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Ora'), findsWidgets);
    expect(find.textContaining('Hello, Ayesha Khan'), findsOneWidget);
    expect(find.byType(PassengerBottomNav), findsOneWidget);
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Rides'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.textContaining('api'), findsNothing);
    expect(find.textContaining('https://'), findsNothing);
  });

  testWidgets('switching tabs updates selection without leaving shell', (
    tester,
  ) async {
    await tester.pumpWidget(_wrapShell(overrides: _baseOverrides()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rides').last);
    await tester.pumpAndSettle();
    expect(find.text('My rides'), findsOneWidget);
    expect(find.textContaining('not wired yet'), findsNothing);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);

    await tester.tap(find.text('Account').last);
    await tester.pumpAndSettle();
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('+923001234567'), findsNothing);
    expect(find.textContaining('••••'), findsOneWidget);
  });

  testWidgets('ride entry opens compose — no createRide', (tester) async {
    final createRide = MockCreateRideUseCase();
    when(
      () => createRide(
        body: any(named: 'body'),
        operationKey: any(named: 'operationKey'),
      ),
    ).thenThrow(StateError('should not call'));

    await tester.pumpWidget(
      _wrapShell(overrides: _baseOverrides(createRide: createRide)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Where are you headed?'));
    await tester.pumpAndSettle();

    expect(find.text('Where to?'), findsOneWidget);
    expect(find.text('Confirm destination'), findsOneWidget);
    verifyNever(
      () => createRide(
        body: any(named: 'body'),
        operationKey: any(named: 'operationKey'),
      ),
    );
  });

  testWidgets('category tap opens compose with gate intact', (tester) async {
    final createRide = MockCreateRideUseCase();
    await tester.pumpWidget(
      _wrapShell(overrides: _baseOverrides(createRide: createRide)),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Choose a ride'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Zip'));
    await tester.pumpAndSettle();
    expect(find.text('Where to?'), findsOneWidget);
    verifyNever(
      () => createRide(
        body: any(named: 'body'),
        operationKey: any(named: 'operationKey'),
      ),
    );
  });

  testWidgets('wallet quick action is honestly unavailable', (tester) async {
    await tester.pumpWidget(_wrapShell(overrides: _baseOverrides()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Wallet'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -80));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Wallet'));
    await tester.pumpAndSettle();
    expect(find.textContaining('not available in this build'), findsOneWidget);
  });

  testWidgets('no overflow on compact phone with large text', (tester) async {
    await tester.pumpWidget(
      _wrapShell(
        size: const Size(320, 568),
        textScale: 1.3,
        overrides: _baseOverrides(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet width layout has no overflow', (tester) async {
    await tester.pumpWidget(
      _wrapShell(
        size: const Size(768, 1024),
        overrides: _baseOverrides(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Where are you headed?'), findsOneWidget);
  });

  testWidgets('does not show fake fares', (tester) async {
    await tester.pumpWidget(_wrapShell(overrides: _baseOverrides()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Rs '), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Choose a ride'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Price TBD'), findsWidgets);
  });
}
