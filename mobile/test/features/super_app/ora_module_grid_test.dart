import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ora/app/router/routes.dart';
import 'package:ora/app/theme/theme.dart';
import 'package:ora/features/super_app/presentation/widgets/ora_module_grid.dart';

void main() {
  testWidgets('module grid renders four cards and pushes each module route', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/preview',
      routes: [
        GoRoute(
          path: '/preview',
          builder: (context, state) => const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: OraModuleGrid(),
            ),
          ),
        ),
        for (final path in <String>[
          AppRoutes.ridesHub,
          AppRoutes.logistics,
          AppRoutes.rental,
          AppRoutes.services,
        ])
          GoRoute(
            path: path,
            builder: (context, state) =>
                Scaffold(body: Center(child: Text('Route $path'))),
          ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: OraTheme.dark(), routerConfig: router),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rides'), findsOneWidget);
    expect(find.text('Logistics'), findsOneWidget);
    expect(find.text('Rental'), findsOneWidget);
    expect(find.text('Services'), findsOneWidget);

    const destinations = <(String, String)>[
      ('Rides', AppRoutes.ridesHub),
      ('Logistics', AppRoutes.logistics),
      ('Rental', AppRoutes.rental),
      ('Services', AppRoutes.services),
    ];

    for (final (title, path) in destinations) {
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(find.text('Route $path'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('module grid fits compact and large phone sizes', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final size in <Size>[const Size(320, 640), const Size(430, 932)]) {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = size;

      await tester.pumpWidget(
        MaterialApp(
          theme: OraTheme.dark(),
          home: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: OraModuleGrid(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });
}
