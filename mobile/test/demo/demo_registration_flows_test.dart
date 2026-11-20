import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora/app/app.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/app/router/routes.dart';
import 'package:ora/core/storage/secure_storage.dart';
import 'package:ora/demo/demo_overrides.dart';
import 'package:ora/demo/demo_session_store.dart';
import 'package:ora/features/auth/presentation/view_models/session_user_profile.dart';
import 'package:ora/features/driver/presentation/views/driver_shell_view.dart';
import 'package:ora/features/logistics_vendor/presentation/views/logistics_shell_view.dart';
import 'package:ora/features/rental_vendor/presentation/views/rental_vendor_home_view.dart';
import 'package:ora/features/vendor/presentation/views/vendor_home_view.dart';

/// End-to-end demo registration flows: the real forms, real validation,
/// real submit handlers — against the demo repositories that auto-approve.
/// Proves each partner role unlocks its dashboard after submitting.

Future<DemoSessionStore> _seededPassenger(InMemorySecureStorage storage) async {
  final store = DemoSessionStore(storage);
  await store.createForPhone('+923001234567');
  await store.update(displayName: 'Smoke Tester', markComplete: true);
  return store;
}

Future<ProviderContainer> _pumpDemoApp(
  WidgetTester tester, {
  required InMemorySecureStorage storage,
  required DemoSessionStore store,
}) async {
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        demoSessionStoreProvider.overrideWithValue(store),
        ...oraDemoOverrides(),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          return const OraApp();
        },
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 2));
  return container;
}

Future<void> _settle(WidgetTester tester) =>
    tester.pumpAndSettle(const Duration(milliseconds: 800));

Future<void> _enter(
  WidgetTester tester,
  String tileKey,
  String text,
) async {
  final tile = find.byKey(ValueKey(tileKey));
  await tester.ensureVisible(tile);
  await _settle(tester);
  await tester.enterText(tile, text);
}

Future<void> _pick(
  WidgetTester tester,
  String tileKey,
  String optionText,
) async {
  final tile = find.byKey(ValueKey(tileKey));
  await tester.ensureVisible(tile);
  await _settle(tester);
  await tester.tap(tile);
  await _settle(tester);
  await tester.tap(
    find.descendant(
      of: find.byType(ListTile),
      matching: find.text(optionText),
    ),
  );
  await _settle(tester);
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await _settle(tester);
  await tester.tap(finder);
  await _settle(tester);
}

Future<void> _submit(WidgetTester tester) async {
  final button = find.text('Submit Registration');
  await tester.ensureVisible(button);
  await _settle(tester);
  await tester.tap(button);
  await _settle(tester);
}

/// Vendor forms always show the "application received" sheet then go home.
Future<void> _dismissReceivedSheet(WidgetTester tester) async {
  await tester.tap(find.text('Back to Home'));
  await _settle(tester);
}

void main() {
  testWidgets('driver form submit auto-approves and opens driver shell', (
    tester,
  ) async {
    final storage = InMemorySecureStorage();
    final store = await _seededPassenger(storage);
    final container = await _pumpDemoApp(
      tester,
      storage: storage,
      store: store,
    );
    final router = container.read(appRouterProvider);

    router.go(AppRoutes.driverRegistration);
    await _settle(tester);

    await _enter(tester, 'driver-cnic-number', '35202-1234567-1');
    await _enter(tester, 'driver-home-city', 'Lahore');
    await _pick(tester, 'driver-vehicle-type', 'Mini');
    await _pick(tester, 'driver-vehicle-colour', 'White');
    await _enter(tester, 'driver-plate-number', 'LEA-1234');
    await _enter(tester, 'driver-vehicle-make', 'Toyota');
    await _enter(tester, 'driver-vehicle-model', 'Corolla');
    await _enter(tester, 'driver-vehicle-year', '2021');
    await _enter(tester, 'driver-license-number', 'LIC-99887');

    // Licence expiry — the tile opens a real DatePicker; the default
    // initial date (today + 1 year) is valid, so confirm it.
    await _tapKey(tester, 'driver-license-expiry');
    await tester.tap(find.text('OK'));
    await _settle(tester);

    await _tapKey(tester, 'driver-confirm-details');
    await _submit(tester);

    expect(find.byType(DriverShellView), findsOneWidget);
    expect(
      container.read(sessionUserProfileProvider)?.isApprovedDriver,
      isTrue,
    );
  });

  testWidgets('service vendor form submit auto-approves and unlocks vendor', (
    tester,
  ) async {
    final storage = InMemorySecureStorage();
    final store = await _seededPassenger(storage);
    final container = await _pumpDemoApp(
      tester,
      storage: storage,
      store: store,
    );
    final router = container.read(appRouterProvider);

    router.go(AppRoutes.serviceVendorRegistration);
    await _settle(tester);

    await _enter(tester, 'vendor-business-address', 'DHA Phase 6, Karachi');
    await _pick(tester, 'vendor-business-type', 'Individual');
    await _tapKey(tester, 'vendor-category-plumbing');
    await _pick(tester, 'vendor-service-area', 'Lahore');
    await _pick(tester, 'vendor-experience', '5+ Years');
    await _submit(tester);
    await _dismissReceivedSheet(tester);

    expect(
      container.read(sessionUserProfileProvider)?.isApprovedVendor('service'),
      isTrue,
    );

    router.go(AppRoutes.vendorHome);
    await _settle(tester);
    expect(find.byType(VendorHomeView), findsOneWidget);
  });

  testWidgets('rental host form submit auto-approves and unlocks rental', (
    tester,
  ) async {
    final storage = InMemorySecureStorage();
    final store = await _seededPassenger(storage);
    final container = await _pumpDemoApp(
      tester,
      storage: storage,
      store: store,
    );
    final router = container.read(appRouterProvider);

    router.go(AppRoutes.rentalRegistration);
    await _settle(tester);

    await _enter(tester, 'rental-address', 'Gulberg III, Lahore');
    await _pick(tester, 'rental-property-type', 'Guest House');
    await _enter(tester, 'rental-property-name', 'Grand View Stay');
    await _pick(tester, 'rental-location', 'Gulberg, Lahore');
    await _submit(tester);
    await _dismissReceivedSheet(tester);

    expect(
      container.read(sessionUserProfileProvider)?.isApprovedVendor('rental'),
      isTrue,
    );

    router.go(AppRoutes.rentalVendorHome);
    await _settle(tester);
    expect(find.byType(RentalVendorHomeView), findsOneWidget);
  });

  testWidgets('cargo partner form submit auto-approves and unlocks logistics', (
    tester,
  ) async {
    final storage = InMemorySecureStorage();
    final store = await _seededPassenger(storage);
    final container = await _pumpDemoApp(
      tester,
      storage: storage,
      store: store,
    );
    final router = container.read(appRouterProvider);

    router.go(AppRoutes.cargoRegistration);
    await _settle(tester);

    await _enter(tester, 'cargo-business-name', 'Saeed Transports');
    await _enter(tester, 'cargo-business-address', 'Port Qasim, Karachi');
    await _pick(tester, 'cargo-business-type', 'Transport Company');
    await _pick(tester, 'cargo-vehicle-type', 'Truck / Lorry');
    await _pick(tester, 'cargo-load-capacity', 'Under 1 ton');
    await _enter(tester, 'cargo-registration-number', 'KHI-7788');
    await _pick(tester, 'cargo-vehicle-colour', 'White');
    await _submit(tester);
    await _dismissReceivedSheet(tester);

    expect(
      container.read(sessionUserProfileProvider)?.isApprovedVendor('cargo'),
      isTrue,
    );

    router.go(AppRoutes.logisticsVendorHome);
    await _settle(tester);
    expect(find.byType(LogisticsShellView), findsOneWidget);
  });
}
