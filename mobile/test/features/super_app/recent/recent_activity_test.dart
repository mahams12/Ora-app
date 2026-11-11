import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ora/app/theme/ora_theme.dart';
import 'package:ora/features/super_app/presentation/widgets/recent_activity_section.dart';
import 'package:ora/features/super_app/recent/recent_activity.dart';

RecentActivity _activity({
  required String id,
  required String title,
  required int atMs,
  String route = '/destination',
}) => RecentActivity(
  kind: RecentActivityKind.ride,
  id: id,
  title: title,
  subtitle: 'Book a ride',
  imageAsset: 'assets/marketplace/modules/rides.webp',
  route: route,
  atMs: atMs,
);

GoRouter _router() => GoRouter(
  initialLocation: '/recent',
  routes: [
    GoRoute(
      path: '/recent',
      builder: (context, state) => const Scaffold(
        body: SingleChildScrollView(child: RecentActivitySection()),
      ),
    ),
    GoRoute(
      path: '/destination',
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('Destination opened'))),
    ),
  ],
);

Widget _app(InMemoryRecentActivityStorage storage, GoRouter router) =>
    ProviderScope(
      overrides: [recentActivityStorageProvider.overrideWithValue(storage)],
      child: MaterialApp.router(theme: OraTheme.dark(), routerConfig: router),
    );

void main() {
  testWidgets('Frequently used shows its empty hint', (tester) async {
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(InMemoryRecentActivityStorage(), router));
    await tester.pumpAndSettle();

    expect(find.text('Frequently used'), findsOneWidget);
    expect(
      find.text('Your recent rides, rentals and services will appear here.'),
      findsOneWidget,
    );
  });

  testWidgets('recording four activities displays the newest three', (
    tester,
  ) async {
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(InMemoryRecentActivityStorage(), router));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(RecentActivitySection)),
    );
    final notifier = container.read(recentActivityProvider.notifier);
    await notifier.ready;
    for (var index = 1; index <= 4; index++) {
      notifier.record(
        _activity(id: 'ride-$index', title: 'Ride $index', atMs: index),
      );
    }
    await notifier.flushed;
    await tester.pumpAndSettle();

    expect(find.text('Ride 4'), findsOneWidget);
    expect(find.text('Ride 3'), findsOneWidget);
    expect(find.text('Ride 2'), findsOneWidget);
    expect(find.text('Ride 1'), findsNothing);
    expect(
      find.text('Your recent rides, rentals and services will appear here.'),
      findsNothing,
    );
  });

  testWidgets('recent activity card pushes its saved route', (tester) async {
    final activity = _activity(
      id: 'to-destination',
      title: 'Open destination',
      atMs: 1,
    );
    final storage = InMemoryRecentActivityStorage()
      ..value = jsonEncode([activity.toJson()]);
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(storage, router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open destination'));
    await tester.pumpAndSettle();
    expect(find.text('Destination opened'), findsOneWidget);
  });

  test('recent activity persists and loads through injected storage', () async {
    final storage = InMemoryRecentActivityStorage();
    final firstContainer = ProviderContainer(
      overrides: [recentActivityStorageProvider.overrideWithValue(storage)],
    );
    final firstNotifier = firstContainer.read(recentActivityProvider.notifier);
    await firstNotifier.ready;
    final activity = _activity(
      id: 'persisted',
      title: 'Persisted ride',
      atMs: 10,
    );
    firstNotifier.record(activity);
    await firstNotifier.flushed;
    firstContainer.dispose();

    final secondContainer = ProviderContainer(
      overrides: [recentActivityStorageProvider.overrideWithValue(storage)],
    );
    addTearDown(secondContainer.dispose);
    final secondNotifier = secondContainer.read(
      recentActivityProvider.notifier,
    );
    await secondNotifier.ready;

    expect(
      secondContainer.read(recentActivityProvider).single.toJson(),
      activity.toJson(),
    );
  });
}
