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
import 'package:ora/features/ride/domain/entities/ride.dart';
import 'package:ora/features/ride/domain/use_cases/ride_use_cases.dart';
import 'package:ora/features/ride/presentation/views/ride_request_view.dart';
import 'package:ora/features/super_app/recent/recent_activity.dart';
import 'package:ora/features/super_app/presentation/views/rides_hub_view.dart';
import 'package:ora/features/super_app/presentation/widgets/ora_module_bottom_bar.dart';

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
      GoRoute(path: AppRoutes.home, builder: (_, __) => const HomeShellView()),
      GoRoute(
        path: AppRoutes.ridesHub,
        builder: (_, __) => const RidesHubView(),
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
      child: MaterialApp.router(theme: OraTheme.dark(), routerConfig: router),
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
    recentActivityStorageProvider.overrideWithValue(
      InMemoryRecentActivityStorage(),
    ),
    if (createRide != null)
      createRideUseCaseProvider.overrideWithValue(createRide),
  ];
}

Future<void> _openDrawer(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Menu').first);
  await tester.pumpAndSettle();
}

Future<void> _scrollDrawerTo(WidgetTester tester, Finder item) async {
  await tester.scrollUntilVisible(
    item,
    80,
    scrollable: find
        .descendant(
          of: find.byType(OraDrawerShell),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
    registerFallbackValue('');
  });

  testWidgets('passenger shell renders Home, module bar, and drawer', (
    tester,
  ) async {
    await tester.pumpWidget(_wrapShell(overrides: _baseOverrides()));
    await tester.pumpAndSettle();

    expect(find.text('ORA'), findsWidgets);
    expect(find.text('Where are you headed?'), findsNothing);
    expect(find.text('Explore ORA'), findsOneWidget);
    expect(find.text('Travel beyond the city'), findsOneWidget);
    expect(find.text('Choose a ride'), findsNothing);
    expect(find.text('Logistics'), findsWidgets);
    expect(find.text('Services'), findsWidgets);
    expect(find.text('Wallet'), findsNothing);
    expect(find.byType(OraModuleBottomBar), findsOneWidget);
    expect(find.text('Account'), findsNothing);

    await _openDrawer(tester);
    expect(find.byType(OraDrawerShell), findsOneWidget);
    expect(find.text('Home'), findsWidgets);
    expect(find.text('My rides'), findsWidgets);
    expect(find.text('Saved places'), findsNothing);
    expect(find.text('Wallet'), findsNothing);
    expect(find.text('Safety centre'), findsNothing);
    await _scrollDrawerTo(tester, find.text('Switch to driver mode'));
    expect(find.text('Switch to driver mode'), findsOneWidget);
    expect(find.text('Register your vehicle'), findsOneWidget);
    await _scrollDrawerTo(tester, find.text('Switch to vendor mode'));
    expect(find.text('Switch to driver mode'), findsOneWidget);
    expect(find.text('Switch to vendor mode'), findsOneWidget);
    await _scrollDrawerTo(tester, find.text('Log out'));
    expect(find.text('Log out'), findsOneWidget);
    expect(find.textContaining('api'), findsNothing);
    expect(find.textContaining('https://'), findsNothing);

    await tester.tapAt(const Offset(380, 100));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Your recent rides, rentals and services will appear here.'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Frequently used'), findsOneWidget);
    expect(
      find.text('Your recent rides, rentals and services will appear here.'),
      findsOneWidget,
    );
  });

  testWidgets('drawer My rides opens history without leaving shell', (
    tester,
  ) async {
    await tester.pumpWidget(_wrapShell(overrides: _baseOverrides()));
    await tester.pumpAndSettle();

    await _openDrawer(tester);
    await tester.tap(find.text('My rides'));
    await tester.pumpAndSettle();

    expect(find.text('My rides'), findsWidgets);
    expect(find.textContaining('not wired yet'), findsNothing);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
  });

  testWidgets('passenger home fits 360px with larger text', (tester) async {
    await tester.pumpWidget(
      _wrapShell(
        overrides: _baseOverrides(),
        size: const Size(360, 640),
        textScale: 1.3,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(OraModuleBottomBar), findsOneWidget);
  });

  testWidgets('drawer Log out is available', (tester) async {
    await tester.pumpWidget(_wrapShell(overrides: _baseOverrides()));
    await tester.pumpAndSettle();

    await _openDrawer(tester);
    await _scrollDrawerTo(tester, find.text('Log out'));
    expect(find.text('Log out'), findsOneWidget);
    expect(find.text('+923001234567'), findsNothing);
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

    await tester.ensureVisible(find.text('Travel beyond the city'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Travel beyond the city'));
    await tester.pumpAndSettle();

    expect(find.byType(RideRequestView), findsOneWidget);
    verifyNever(
      () => createRide(
        body: any(named: 'body'),
        operationKey: any(named: 'operationKey'),
      ),
    );
  });

  testWidgets('Rides module opens the hub category flow', (tester) async {
    final createRide = MockCreateRideUseCase();
    await tester.pumpWidget(
      _wrapShell(overrides: _baseOverrides(createRide: createRide)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rides').first);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(CustomScrollView).last,
      const Offset(0, -360),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Bike'));
    await tester.tap(find.text('Bike'));
    await tester.pumpAndSettle();
    expect(find.byType(RideRequestView), findsOneWidget);
    verifyNever(
      () => createRide(
        body: any(named: 'body'),
        operationKey: any(named: 'operationKey'),
      ),
    );
  });

  testWidgets('vendor drawer entry shows the coming-soon sheet', (
    tester,
  ) async {
    await tester.pumpWidget(_wrapShell(overrides: _baseOverrides()));
    await tester.pumpAndSettle();

    await _openDrawer(tester);
    await _scrollDrawerTo(tester, find.text('Switch to vendor mode'));
    expect(find.text('Switch to driver mode'), findsOneWidget);
    expect(find.text('Switch to vendor mode'), findsOneWidget);
    expect(find.text('Vendor web portal'), findsOneWidget);
    expect(find.text('Saved places'), findsNothing);
    expect(find.text('Wallet'), findsNothing);
    expect(find.text('Safety centre'), findsNothing);
    await tester.tap(find.text('Switch to vendor mode'));
    await tester.pumpAndSettle();
    expect(find.text('COMING SOON'), findsOneWidget);
    expect(find.text('Vendor portal'), findsOneWidget);
    expect(
      find.text(
        'Vendors will manage listings and bookings from the ORA vendor web '
        'app. Coming soon.',
      ),
      findsOneWidget,
    );
    expect(find.text('Got it'), findsOneWidget);
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
      _wrapShell(size: const Size(768, 1024), overrides: _baseOverrides()),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Where are you headed?'), findsNothing);
  });

  testWidgets('does not show fake fares', (tester) async {
    await tester.pumpWidget(_wrapShell(overrides: _baseOverrides()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Rs '), findsNothing);
    expect(find.text('Choose a ride'), findsNothing);
    expect(find.text('Fare on request'), findsNothing);
  });
}
