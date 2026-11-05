import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ora/app/router/routes.dart';
import 'package:ora/app/theme/theme.dart';
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

Widget _app(GoRouter router) =>
    MaterialApp.router(theme: OraTheme.dark(), routerConfig: router);

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

  testWidgets('Courier and Move keep Coming Later behavior and pills', (
    tester,
  ) async {
    final router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    expect(find.text('Coming later'), findsNWidgets(2));

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
    expect(
      find.text(
        'Move is planned for Ora but is not wired to the backend '
        'in this build. Nothing is faked.',
      ),
      findsOneWidget,
    );
    expect(find.text('Got it'), findsOneWidget);
  });

  testWidgets('Logistics catalogue card opens Logistics', (tester) async {
    final router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    final logisticsCard = find.text(
      'Logistics — trucks, cargo & freight catalogue',
    );
    await tester.ensureVisible(logisticsCard);
    await tester.pumpAndSettle();
    await tester.tap(logisticsCard);
    await tester.pumpAndSettle();
    expect(find.text('/logistics'), findsOneWidget);
  });

  testWidgets('Rides hub shows all categories and Saved places', (
    tester,
  ) async {
    final router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Choose a ride'));
    await tester.pumpAndSettle();
    expect(find.text('6 options'), findsOneWidget);

    const categoryNames = [
      'Zip',
      'Trio',
      'Easy',
      'Breeze',
      'Executive',
      'Premium',
    ];
    final seenCategories = <String>{};
    final categoryList = find.byType(ListView);
    for (var i = 0; i < 8; i++) {
      for (final name in categoryNames) {
        if (find.text(name).evaluate().isNotEmpty) {
          seenCategories.add(name);
        }
      }
      await tester.drag(categoryList, const Offset(-260, 0));
      await tester.pumpAndSettle();
    }
    expect(seenCategories, containsAll(categoryNames));

    await tester.ensureVisible(find.text('Saved places'));
    await tester.pumpAndSettle();
    expect(find.text('Saved places'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
  });

  testWidgets('Rides hub Zip opens its ride request URI', (tester) async {
    final router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Choose a ride'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Zip'));
    await tester.pumpAndSettle();
    expect(find.text('/rides/request?category=zip'), findsOneWidget);
  });

  testWidgets('Rides hub saved places use the unavailable sheet', (
    tester,
  ) async {
    final router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Saved places'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Home is planned for Ora but is not wired to the backend '
        'in this build. Nothing is faked.',
      ),
      findsOneWidget,
    );
    expect(find.text('Got it'), findsOneWidget);
  });

  testWidgets('Rides hub fits compact and large phone sizes', (tester) async {
    final router = _router();
    addTearDown(router.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final size in <Size>[const Size(320, 640), const Size(430, 932)]) {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = size;

      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });
}
