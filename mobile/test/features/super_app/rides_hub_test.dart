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

    await tester.tap(
      find.text('Logistics — trucks, cargo & freight catalogue'),
    );
    await tester.pumpAndSettle();
    expect(find.text('/logistics'), findsOneWidget);
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
