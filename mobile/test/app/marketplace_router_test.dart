import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ora/app/router/app_router.dart';
import 'package:ora/app/router/routes.dart';

void main() {
  test('marketplace and ride paths resolve without collisions', () {
    final router = createAppRouter();
    addTearDown(router.dispose);

    final cases = <String, String>{
      AppRoutes.logistics: AppRoutes.logistics,
      '/logistics-vendor/deliveries/abc': AppRoutes.logisticsDelivery,
      AppRoutes.logisticsVendorWallet: AppRoutes.logisticsVendorWallet,
      AppRoutes.logisticsVendorWalletAddPoints:
          AppRoutes.logisticsVendorWalletAddPoints,
      AppRoutes.services: AppRoutes.services,
      AppRoutes.servicesSearchPath('wedding'): AppRoutes.servicesSearch,
      AppRoutes.servicesBookings: AppRoutes.servicesBookings,
      AppRoutes.servicesSaved: AppRoutes.servicesSaved,
      AppRoutes.servicesCategoryPath('home_repair'): AppRoutes.servicesCategory,
      AppRoutes.servicesSubcategoryPath('home_repair', 'plumbing'):
          AppRoutes.servicesSubcategory,
      AppRoutes.rental: AppRoutes.rental,
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

  test('search route helpers preserve the complete query', () {
    final services = Uri.parse(AppRoutes.servicesSearchPath('AC gas'));

    expect(services.path, AppRoutes.servicesSearch);
    expect(services.queryParameters['q'], 'AC gas');
  });

  test('no logistics listing routes are registered', () {
    final router = createAppRouter();
    addTearDown(router.dispose);

    expect(
      router.configuration.findMatch(Uri.parse('/logistics/trucks')).error,
      isNotNull,
    );
    expect(
      router.configuration
          .findMatch(Uri.parse('/logistics/search?q=tow'))
          .error,
      isNotNull,
    );
  });

  test('no logistics submission or confirmation routes are registered', () {
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

    expect(paths.where((path) => path.contains('submit')), isEmpty);
    expect(paths.where((path) => path.contains('confirm')), isEmpty);
  });
}
