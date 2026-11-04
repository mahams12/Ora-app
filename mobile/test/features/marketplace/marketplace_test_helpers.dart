import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ora/app/router/app_router.dart';
import 'package:ora/app/theme/ora_theme.dart';
import 'package:ora/features/marketplace/catalogue/catalogue_models.dart';
import 'package:ora/features/marketplace/catalogue/catalogue_provider.dart';

Future<MarketplaceCatalogue> loadMarketplaceCatalogue() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final source = await rootBundle.loadString(
    'assets/marketplace/catalogue_v1.json',
  );
  return MarketplaceCatalogue.fromJson(
    jsonDecode(source) as Map<String, dynamic>,
  );
}

Future<GoRouter> pumpMarketplaceRoute(
  WidgetTester tester, {
  required String location,
  required MarketplaceCatalogue catalogue,
}) async {
  final router = createAppRouter(initialLocation: location);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [catalogueProvider.overrideWith((ref) async => catalogue)],
      child: MaterialApp.router(theme: OraTheme.dark(), routerConfig: router),
    ),
  );
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return router;
}

void setMarketplaceTestSurface(WidgetTester tester, Size size) {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size;
}

void resetMarketplaceTestSurface(WidgetTester tester) {
  tester.view
    ..resetPhysicalSize()
    ..resetDevicePixelRatio();
}
