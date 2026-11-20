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

/// Full-app smoke test for the boss-review demo build: real `OraApp`, real
/// router + guards, all demo overrides — no Firebase, no network.
Future<void> _pumpDemoApp(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
        ...oraDemoOverrides(),
      ],
      child: const OraApp(),
    ),
  );
  // Let the splash/bootstrap + router redirects settle.
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

Future<void> _settle(WidgetTester tester) =>
    tester.pumpAndSettle(const Duration(milliseconds: 800));

void main() {
  testWidgets('any phone + OTP 000000 reaches onboarding then home', (
    tester,
  ) async {
    await _pumpDemoApp(tester);

    // Phone entry — the real UI, demo backend underneath.
    expect(find.text('Send code'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField).first,
      '+923001234567',
    );
    await tester.tap(find.text('Send code'));
    await _settle(tester);

    // OTP entry — type the demo code into the first box.
    expect(find.text('Verify & continue'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '000000');
    await tester.tap(find.text('Verify & continue'));
    await _settle(tester);

    // Fresh demo account → real onboarding (name) → home.
    expect(find.text('Continue'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Smoke Tester');
    await tester.tap(find.text('Continue'));
    await _settle(tester);

    expect(find.text('Rides'), findsWidgets);
    expect(find.text('Logistics'), findsWidgets);
    expect(find.text('Rental'), findsWidgets);
    expect(find.text('Services'), findsWidgets);
  });

  testWidgets('approved demo roles unlock every partner dashboard', (
    tester,
  ) async {
    // Pre-seed an approved multi-role demo account (what the app looks like
    // after all four demo registrations auto-approve).
    final storage = InMemorySecureStorage();
    final store = DemoSessionStore(storage);
    await store.createForPhone('+923001234567');
    await store.update(displayName: 'Smoke Tester', markComplete: true);
    await store.approveDriver();
    for (final t in const ['cargo', 'rental', 'service']) {
      await store.approveVendor(t);
    }
    await store.setMode('passenger');

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

    // Restored session → home (profileComplete), approved profile present.
    expect(find.text('Rides'), findsWidgets);
    final profile = container.read(sessionUserProfileProvider);
    expect(profile?.isApprovedDriver, isTrue);
    expect(profile?.isApprovedVendor('service'), isTrue);
    expect(profile?.isApprovedVendor('rental'), isTrue);
    expect(profile?.isApprovedVendor('cargo'), isTrue);

    final router = container.read(appRouterProvider);

    router.go(AppRoutes.driverHome);
    await _settle(tester);
    expect(find.byType(DriverShellView), findsOneWidget);

    router.go(AppRoutes.vendorHome);
    await _settle(tester);
    expect(find.byType(VendorHomeView), findsOneWidget);

    router.go(AppRoutes.rentalVendorHome);
    await _settle(tester);
    expect(find.byType(RentalVendorHomeView), findsOneWidget);

    router.go(AppRoutes.logisticsVendorHome);
    await _settle(tester);
    expect(find.byType(LogisticsShellView), findsOneWidget);
  });
}
