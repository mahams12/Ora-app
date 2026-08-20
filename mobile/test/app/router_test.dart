import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ora/app/router/app_router.dart';
import 'package:ora/app/router/routes.dart';

void main() {
  test('createAppRouter registers splash and home paths', () {
    final router = createAppRouter();
    final paths = <String>[];

    void collect(GoRoute route) {
      paths.add(route.path);
      for (final child in route.routes) {
        if (child is GoRoute) {
          collect(child);
        }
      }
    }

    for (final route in router.configuration.routes) {
      if (route is GoRoute) {
        collect(route);
      }
    }

    expect(paths, containsAll([AppRoutes.splash, AppRoutes.home]));
  });
}
