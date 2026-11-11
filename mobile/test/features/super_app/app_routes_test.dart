import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ora/app/router/app_router.dart';
import 'package:ora/app/router/routes.dart';

void main() {
  test('ride request URI matches the passenger home links', () {
    expect(AppRoutes.rideRequestUri(), '/rides/request?');
    expect(
      AppRoutes.rideRequestUri(service: 'intercity'),
      '/rides/request?service=intercity',
    );
    expect(
      AppRoutes.rideRequestUri(category: 'zip', service: 'intercity'),
      '/rides/request?category=zip&service=intercity',
    );
  });

  test('rides hub does not shadow ride request or active ride routes', () {
    final router = createAppRouter();
    addTearDown(router.dispose);

    final cases = <String, String>{
      '/rides': AppRoutes.ridesHub,
      '/rides/request': AppRoutes.rideRequest,
      '/rides/abc/active': AppRoutes.activeRide,
    };

    for (final entry in cases.entries) {
      final match = router.configuration.findMatch(Uri.parse(entry.key));
      expect(match.error, isNull, reason: entry.key);
      expect(match.fullPath, entry.value, reason: entry.key);
    }
  });

  test('module routes are registered', () {
    final router = createAppRouter();
    addTearDown(router.dispose);
    final paths = <String>[];

    void collect(GoRoute route) {
      paths.add(route.path);
      for (final child in route.routes) {
        if (child is GoRoute) collect(child);
      }
    }

    for (final route in router.configuration.routes) {
      if (route is GoRoute) collect(route);
    }

    expect(
      paths,
      containsAll([
        AppRoutes.ridesHub,
        AppRoutes.logistics,
        AppRoutes.rental,
        AppRoutes.rentalCategory,
        AppRoutes.services,
      ]),
    );
  });

  test('rental category route preserves selected subcategory', () {
    expect(
      AppRoutes.rentalCategoryPath('events', subcategoryId: 'wedding_halls'),
      '/rental/category/events?subcategory=wedding_halls',
    );
  });
}
