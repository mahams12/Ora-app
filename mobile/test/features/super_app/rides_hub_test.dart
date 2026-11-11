import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ora/app/router/routes.dart';
import 'package:ora/app/theme/theme.dart';
import 'package:ora/features/ride/domain/models/ride_category_option.dart';
import 'package:ora/features/super_app/recent/recent_activity.dart';
import 'package:ora/features/super_app/domain/ride_type_catalogue.dart';
import 'package:ora/features/super_app/presentation/views/rides_hub_view.dart';

GoRouter _router() => GoRouter(
  initialLocation: AppRoutes.ridesHub,
  routes: [
    GoRoute(
      path: AppRoutes.ridesHub,
      builder: (context, state) => const RidesHubView(),
    ),
    GoRoute(
      path: AppRoutes.rideRequest,
      builder: (context, state) =>
          Scaffold(body: Center(child: Text(state.uri.toString()))),
    ),
    GoRoute(
      path: AppRoutes.logistics,
      builder: (context, state) =>
          Scaffold(body: Center(child: Text(state.uri.toString()))),
    ),
  ],
);

Widget _app(GoRouter router, {double textScale = 1}) => ProviderScope(
  overrides: [
    recentActivityStorageProvider.overrideWithValue(
      InMemoryRecentActivityStorage(),
    ),
  ],
  child: MaterialApp.router(
    theme: OraTheme.dark(),
    routerConfig: router,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
  ),
);

Future<void> _scrollHubTo(
  WidgetTester tester,
  Finder item, {
  int swipes = 1,
}) async {
  final scrollView = find.byType(CustomScrollView).first;
  for (var index = 0; index < swipes; index++) {
    await tester.drag(scrollView, const Offset(0, -360));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(item);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('City and Intercity keep the home tile request URIs', (
    tester,
  ) async {
    final router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('City rides'));
    await tester.pumpAndSettle();
    expect(find.text('/rides/request?'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Intercity'));
    await tester.pumpAndSettle();
    expect(find.text('/rides/request?service=intercity'), findsOneWidget);
  });

  testWidgets('Courier stays coming later and Move opens Logistics', (
    tester,
  ) async {
    final router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    expect(find.text('Coming later'), findsOneWidget);

    await tester.tap(find.text('Courier'));
    await tester.pumpAndSettle();
    expect(find.text('Courier'), findsWidgets);
    expect(
      find.text(
        'Courier is planned for Ora but is not wired to the backend '
        'in this build. Nothing is faked.',
      ),
      findsOneWidget,
    );
    expect(find.text('Got it'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Move'));
    await tester.pumpAndSettle();
    expect(find.text('/logistics'), findsOneWidget);
    expect(find.text('Coming later'), findsNothing);
  });

  test('ride type catalogue keeps typed actions and category IDs', () {
    expect(kRideTypeCatalogue, hasLength(13));
    expect(kRideTypeCatalogue.map((option) => option.name), [
      'Bike',
      'Rickshaw',
      'Mini',
      'AC',
      'Premium',
      'Business class',
      'For Events',
      '6-Seater',
      '7-Seater',
      'Van',
      'Bus',
      'Intercity',
      'Women-Only Rides',
    ]);
    final categoryIds = kRideCategoryOptions.map((option) => option.id).toSet();
    for (final option in kRideTypeCatalogue) {
      final action = option.action;
      if (action is RideCategoryAction) {
        expect(categoryIds, contains(action.categoryId));
      }
    }
    expect(
      kRideTypeCatalogue
          .singleWhere((option) => option.id == 'intercity')
          .action,
      isA<RideIntercityAction>(),
    );
  });

  testWidgets('Rides hub shows all ride types without Saved places', (
    tester,
  ) async {
    final router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Choose a ride'));
    await tester.pumpAndSettle();

    const rideNames = [
      'Bike',
      'Rickshaw',
      'Mini',
      'AC',
      'Premium',
      'Business class',
      'For Events',
      '6-Seater',
      '7-Seater',
      'Van',
      'Bus',
      'Intercity',
      'Women-Only Rides',
    ];
    final seenRideTypes = <String>{};
    final scrollable = find.byType(CustomScrollView).first;
    for (var i = 0; i < 10; i++) {
      for (final name in rideNames) {
        if (find.text(name).evaluate().isNotEmpty) {
          seenRideTypes.add(name);
        }
      }
      await tester.drag(scrollable, const Offset(0, -360));
      await tester.pumpAndSettle();
    }
    expect(seenRideTypes, containsAll(rideNames));
    expect(find.text('Saved places'), findsNothing);
    expect(find.text('Explore Logistics'), findsNothing);
  });

  testWidgets('Rides hub Zip opens its ride request URI', (tester) async {
    final router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();
    await _scrollHubTo(tester, find.text('Bike'));

    await tester.tap(find.text('Bike'));
    await tester.pumpAndSettle();
    expect(find.text('/rides/request?category=zip'), findsOneWidget);
  });

  testWidgets('Rides hub Intercity uses the existing intercity route', (
    tester,
  ) async {
    final router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Intercity').first);
    await tester.pumpAndSettle();
    expect(find.text('/rides/request?service=intercity'), findsOneWidget);
  });

  testWidgets('Rides hub Van opens the coming-later sheet', (tester) async {
    final router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();
    await _scrollHubTo(tester, find.text('Van'), swipes: 5);
    await tester.tap(find.text('Van'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Van is planned for Ora but is not wired to the backend '
        'in this build. Nothing is faked.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Rides hub fits compact and large phone sizes', (tester) async {
    final router = _router();
    addTearDown(router.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final size in <Size>[
      const Size(320, 640),
      const Size(360, 640),
      const Size(430, 932),
    ]) {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = size;

      await tester.pumpWidget(_app(router, textScale: 1.3));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });
}
