// Driver design screenshots — pumps the driver shell and detail view with
// fixed view-model states so the new orange/3D screens can be captured on a
// real device without auth or a backend. Dev-only harness; nothing ships.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/app/router/routes.dart';
import 'package:ora/app/theme/ora_colors.dart';
import 'package:ora/app/theme/ora_theme.dart';
import 'package:ora/app/theme/widgets/ora_floaty.dart';
import 'package:ora/features/auth/presentation/view_models/session_user_profile.dart';
import 'package:ora/features/driver/presentation/views/driver_add_points_view.dart';
import 'package:ora/features/driver/presentation/views/driver_assigned_ride_view.dart';
import 'package:ora/features/driver/presentation/views/driver_shell_view.dart';
import 'package:ora/features/driver/presentation/views/driver_wallet_view.dart';
import 'package:ora/features/driver/presentation/widgets/driver_ui_kit.dart';
import 'package:ora/features/ride/presentation/widgets/ride_card/ride_card.dart';
import 'package:ora/features/logistics_vendor/presentation/views/logistics_shell_view.dart';
import 'package:ora/features/marketplace/logistics/presentation/views/logistics_home_view.dart';
import 'package:ora/features/marketplace/data/marketplace_models.dart';
import 'package:ora/features/marketplace/data/marketplace_providers.dart';
import 'package:ora/features/marketplace/rental/presentation/views/rental_category_view.dart';
import 'package:ora/features/marketplace/services/presentation/views/service_providers_view.dart';
import 'package:ora/features/passenger/presentation/view_models/home_view_model.dart';
import 'package:ora/features/passenger/presentation/views/home_shell_view.dart';
import 'package:ora/features/ride/presentation/view_models/ride_history_view_model.dart';
import 'package:ora/features/wallet/partner_wallet.dart';
import 'package:ora/features/rental_vendor/presentation/views/rental_post_property_view.dart';
import 'package:ora/features/rental_vendor/presentation/views/rental_vendor_home_view.dart';
import 'package:ora/features/vendor/presentation/views/vendor_home_view.dart';
import 'package:ora/features/vendor/presentation/views/vendor_post_service_view.dart';

import 'package:ora/demo/driver_seed.dart';

final _demoDate = DateTime(2026, 3, 1);

// Passenger-shell fakes — keep HomeShellView off Firebase/backend in the
// screenshot harness (same pattern as the driver fake VMs in the seed).
class _FakeHomeVm extends HomeViewModel {
  @override
  HomeUiState build() => const HomeUiState(
    loadStatus: HomeLoadStatus.ready,
    displayName: 'Ahmed',
  );

  @override
  Future<void> loadProfile() async {}

  @override
  Future<void> logout() async {}
}

class _FakeRideHistoryVm extends RideHistoryViewModel {
  @override
  RideHistoryUiState build() =>
      const RideHistoryUiState(phase: RideHistoryPhase.ready);

  @override
  Future<void> loadInitial() async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<void> loadMore() async {}

  @override
  Future<void> setStatus(String status) async {}

  @override
  Future<void> setServiceType(String? serviceType) async {}

  @override
  Future<void> retry() async {}
}

/// Demo wallet state — the shared partner wallet rendered identically in
/// every partner shell (real screens read it from /v1/wallet).
PartnerWalletState get _demoWallet => const PartnerWalletState(
  balancePoints: 5750,
  transactions: [
    PartnerWalletTxn(
      id: 'txn-1',
      kind: PartnerWalletTxnKind.topUp,
      title: 'Points Added',
      subtitle: 'via Easypaisa • Top-up',
      timeLabel: 'Today, 2:45 PM',
      points: 2000,
    ),
    PartnerWalletTxn(
      id: 'txn-2',
      kind: PartnerWalletTxnKind.commission,
      title: 'Commission Deducted',
      subtitle: 'Ride • #RD4582',
      timeLabel: 'Today, 1:20 PM',
      points: -85,
    ),
    PartnerWalletTxn(
      id: 'txn-3',
      kind: PartnerWalletTxnKind.commission,
      title: 'Commission Deducted',
      subtitle: 'Service • #SV1134',
      timeLabel: 'Yesterday, 6:10 PM',
      points: -120,
    ),
  ],
  topups: [
    WalletTopup(
      topupId: 'topup-demo-1',
      kind: 'credit',
      points: 2000,
      method: 'easypaisa',
      status: 'PENDING',
      createdAt: '2026-01-01T10:00:00Z',
    ),
  ],
  roles: ['driver'],
  commissionBps: {'driver': 1000},
  lowBalance: false,
  acceptBlocked: false,
);

List<Override> get _walletOverrides => [
  partnerWalletProvider.overrideWith((ref) async => _demoWallet),
];

Widget _shotApp({required Widget child}) {
  return MaterialApp(
    title: 'ORA Driver',
    debugShowCheckedModeBanner: false,
    theme: OraTheme.light(),
    themeMode: ThemeMode.light,
    builder: (context, c) => DecoratedBox(
      decoration: const BoxDecoration(gradient: OraColors.backgroundGradient),
      child: c ?? const SizedBox.shrink(),
    ),
    home: child,
  );
}

Widget _shotRouterApp() {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const DriverAssignedRideView(rideId: 'book-1'),
      ),
      GoRoute(
        path: AppRoutes.driverHome,
        builder: (_, __) => const Scaffold(body: SizedBox.shrink()),
      ),
    ],
  );
  return MaterialApp.router(
    debugShowCheckedModeBanner: false,
    theme: OraTheme.light(),
    themeMode: ThemeMode.light,
    routerConfig: router,
    builder: (context, c) => DecoratedBox(
      decoration: const BoxDecoration(gradient: OraColors.backgroundGradient),
      child: c ?? const SizedBox.shrink(),
    ),
  );
}

Widget _shotLogisticsRouterApp() {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const DriverAssignedRideView(
          rideId: 'book-1',
          title: 'Active Delivery',
          subtitle: 'Manage your current delivery',
          homeRoute: AppRoutes.logisticsVendorHome,
        ),
      ),
      GoRoute(
        path: AppRoutes.logisticsVendorHome,
        builder: (_, __) => const Scaffold(body: SizedBox.shrink()),
      ),
    ],
  );
  return MaterialApp.router(
    debugShowCheckedModeBanner: false,
    theme: OraTheme.light(),
    themeMode: ThemeMode.light,
    routerConfig: router,
    builder: (context, c) => DecoratedBox(
      decoration: const BoxDecoration(gradient: OraColors.backgroundGradient),
      child: c ?? const SizedBox.shrink(),
    ),
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Same as test/flutter_test_config.dart — stop looping float animations so
  // pumps settle and screenshots are deterministic.
  OraFloaty.debugSkipRepeat = true;

  // convertFlutterSurfaceToImage asserts if called twice per test — reset
  // this flag at the top of each testWidgets body.
  var surfaceConverted = false;

  // PNG bytes flow back to the host driver via reportData — the driver
  // (test_driver/driver_screenshots.dart) writes them to
  // test_outputs/driver_shots/.
  Future<void> shot(WidgetTester tester, String name) async {
    if (!surfaceConverted) {
      await binding.convertFlutterSurfaceToImage();
      surfaceConverted = true;
    }
    await tester.pump();
    await binding.takeScreenshot(name);
  }

  Future<void> popSheet(
    WidgetTester tester, {
    String title = 'New Ride Request',
  }) async {
    final finder = find.text(title);
    if (finder.evaluate().isEmpty) return;
    Navigator.of(tester.element(finder.first)).pop();
    await tester.pumpAndSettle();
  }

  testWidgets('driver shell screens', (tester) async {
    surfaceConverted = false;
    final container = ProviderContainer(overrides: driverDemoOverrides());
    addTearDown(container.dispose);
    container.read(sessionUserProfileProvider.notifier).setProfile(demoProfile);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _shotApp(child: const DriverShellView()),
      ),
    );
    await tester.pumpAndSettle();
    await shot(tester, 'driver_01_home');

    // Ride Requests page (quick tile on home — not the offstage page
    // header, which shares the same label).
    await tester.tap(
      find.widgetWithText(DriverQuickTile, 'Open ride requests'),
    );
    await tester.pumpAndSettle();
    await shot(tester, 'driver_02_requests');

    // New Ride Request sheet — first RideCard is the top invite.
    await tester.tap(find.byType(RideCard).first);
    await tester.pumpAndSettle();
    await shot(tester, 'driver_03_request_sheet');
    await popSheet(tester);

    // Offer sheet — open-ride cards sit below the invites; scroll the
    // page list to the first one (keyed open_ride_<id>) and tap it.
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('open_ride_open-1')),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open_ride_open-1')));
    await tester.pumpAndSettle();
    await shot(tester, 'driver_04_offer_sheet');
    await popSheet(tester);

    // My Bookings tab (icon is unique — the home 'Earnings' tile would
    // collide with the nav label).
    await tester.tap(find.byIcon(Icons.directions_car_outlined));
    await tester.pumpAndSettle();
    await shot(tester, 'driver_05_bookings');

    // My Earnings tab.
    await tester.tap(find.byIcon(Icons.account_balance_wallet_outlined));
    await tester.pumpAndSettle();
    await shot(tester, 'driver_06_earnings');

    // My Profile tab.
    await tester.tap(find.byIcon(Icons.person_outline_rounded));
    await tester.pumpAndSettle();
    await shot(tester, 'driver_09_profile');
  });

  testWidgets('driver detail', (tester) async {
    surfaceConverted = false;
    final container = ProviderContainer(overrides: driverDemoOverrides());
    addTearDown(container.dispose);
    container.read(sessionUserProfileProvider.notifier).setProfile(demoProfile);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _shotRouterApp()),
    );
    await tester.pumpAndSettle();
    await shot(tester, 'driver_07_active_ride');
  });

  // Vendor side — home, post-a-service form, and the passenger providers
  // page showing a seeded vendor listing under its exact category.
  testWidgets('vendor screens', (tester) async {
    surfaceConverted = false;
    final serviceListing = MarketplaceListing(
      listingId: 'vnd-demo-1',
      vendorId: 'vnd-demo',
      vendorName: 'Ahmed Services',
      type: 'service',
      categoryId: 'home_repair',
      subcategoryId: 'ac',
      title: 'AC Installation & Repair Service',
      description:
          'Complete AC installation, repair and gas charging. '
          'On-site service across Lahore with 30-day warranty.',
      price: 2500,
      priceUnit: 'Per Service',
      location: 'DHA Phase 5, Lahore',
      details: {
        'features': ['On-site Service', 'Warranty'],
        'timing': '9:00 AM – 6:00 PM',
      },
      photos: [],
      contactNumber: '0300 1234567',
      status: 'published',
      createdAt: _demoDate,
    );
    final container = ProviderContainer(
      overrides: [
        ...driverDemoOverrides(),
        myListingsProvider(
          'service',
        ).overrideWith((ref) async => [serviceListing]),
        bookingsProvider(
          const BookingsQuery(role: 'vendor', type: 'service'),
        ).overrideWith((ref) async => <MarketplaceBooking>[]),
        publishedListingsProvider(
          const PublishedQuery(
            type: 'service',
            categoryId: 'home_repair',
            subcategoryId: 'ac',
          ),
        ).overrideWith((ref) async => [serviceListing]),
      ],
    );
    addTearDown(container.dispose);
    container.read(sessionUserProfileProvider.notifier).setProfile(demoProfile);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _shotApp(child: const VendorHomeView()),
      ),
    );
    await tester.pumpAndSettle();
    await shot(tester, 'vendor_01_home');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _shotApp(child: const VendorPostServiceView()),
      ),
    );
    await tester.pumpAndSettle();
    await shot(tester, 'vendor_02_post_service');

    await tester.drag(
      find.byType(ListView).first,
      const Offset(0, -1600),
    );
    await tester.pumpAndSettle();
    await shot(tester, 'vendor_02_post_bottom');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _shotApp(
          child: const ServiceProvidersView(
            categoryId: 'home_repair',
            subcategoryId: 'ac',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await shot(tester, 'vendor_03_passenger_listing');
  });

  // Logistics partner side — the driver-clone shell fed by the same fake
  // view-model states (seeded as `move` deliveries) so every logistics
  // screen mirrors its driver counterpart.
  testWidgets('logistics partner screens', (tester) async {
    surfaceConverted = false;
    final container = ProviderContainer(
      overrides: [
        ...driverDemoOverrides(serviceType: 'move'),
        ..._walletOverrides,
      ],
    );
    addTearDown(container.dispose);
    container.read(
      sessionUserProfileProvider.notifier,
    ).setProfile(demoLogisticsProfile);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _shotApp(child: const LogisticsShellView()),
      ),
    );
    await tester.pumpAndSettle();
    await shot(tester, 'logistics_01_home');

    // Delivery Requests page (quick tile on home).
    await tester.tap(
      find.widgetWithText(DriverQuickTile, 'Delivery requests'),
    );
    await tester.pumpAndSettle();
    await shot(tester, 'logistics_02_requests');

    // New Delivery Request sheet — first RideCard is the top invite.
    await tester.tap(find.byType(RideCard).first);
    await tester.pumpAndSettle();
    await shot(tester, 'logistics_03_request_sheet');
    await popSheet(tester, title: 'New Delivery Request');

    // Offer sheet — open-request cards sit below the invites.
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('open_ride_open-1')),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open_ride_open-1')));
    await tester.pumpAndSettle();
    await shot(tester, 'logistics_04_offer_sheet');
    await popSheet(tester, title: 'New Delivery Request');

    // Jobs tab (icon is unique — same car glyph the driver Trips tab uses).
    await tester.tap(find.byIcon(Icons.directions_car_outlined));
    await tester.pumpAndSettle();
    await shot(tester, 'logistics_05_deliveries');

    // My Earnings tab.
    await tester.tap(find.byIcon(Icons.account_balance_wallet_outlined));
    await tester.pumpAndSettle();
    await shot(tester, 'logistics_06_earnings');

    // Wallet tab.
    await tester.tap(find.byIcon(Icons.account_balance_outlined));
    await tester.pumpAndSettle();
    await shot(tester, 'logistics_10_wallet');

    // My Profile tab.
    await tester.tap(find.byIcon(Icons.person_outline_rounded));
    await tester.pumpAndSettle();
    await shot(tester, 'logistics_09_profile');
  });

  testWidgets('logistics delivery detail', (tester) async {
    surfaceConverted = false;
    final container = ProviderContainer(
      overrides: [
        ...driverDemoOverrides(serviceType: 'move'),
        ..._walletOverrides,
      ],
    );
    addTearDown(container.dispose);
    container.read(
      sessionUserProfileProvider.notifier,
    ).setProfile(demoLogisticsProfile);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _shotLogisticsRouterApp(),
      ),
    );
    await tester.pumpAndSettle();
    await shot(tester, 'logistics_07_active_delivery');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _shotApp(
          child: const DriverAddPointsView(
            walletRoute: AppRoutes.logisticsVendorWallet,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await shot(tester, 'logistics_11_add_points');
  });

  // Passenger logistics module — rides-style booking entry (service
  // tiles + vehicle picker) that deep-links into the shared request
  // composer; the old listing/category browsing is gone.
  testWidgets('passenger logistics home', (tester) async {
    surfaceConverted = false;
    final container = ProviderContainer(overrides: driverDemoOverrides());
    addTearDown(container.dispose);
    container.read(sessionUserProfileProvider.notifier).setProfile(demoProfile);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _shotApp(child: const LogisticsHomeView()),
      ),
    );
    await tester.pumpAndSettle();
    await shot(tester, 'logistics_passenger_01_home');

    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    await shot(tester, 'logistics_passenger_02_vehicles');
  });

  // Rental vendor side — home, post-a-property form, and the passenger
  // category page showing a seeded listing under its exact property type.
  testWidgets('rental vendor screens', (tester) async {
    surfaceConverted = false;
    final rentalListing = MarketplaceListing(
      listingId: 'rnv-demo-1',
      vendorId: 'vnd-demo',
      vendorName: 'Ahmed Properties',
      type: 'rental',
      categoryId: 'residential',
      subcategoryId: 'apartments_flats',
      title: '2-Bed Apartment in Gulberg, Lahore',
      description:
          'Furnished 2-bedroom apartment with attached baths, lift '
          'access and covered parking near Main Boulevard.',
      price: 85000,
      priceUnit: 'Per Month',
      location: 'Gulberg III, Lahore',
      details: const {
        'subcategoryName': 'Apartments & Flats',
        'amenities': ['Wi-Fi', 'AC', 'Parking', 'Furnished'],
        'availableFrom': '01/04/2026',
        'email': 'ahmed@example.com',
      },
      photos: const [],
      contactNumber: '0300 1234567',
      status: 'published',
      createdAt: _demoDate,
    );
    final container = ProviderContainer(
      overrides: [
        ...driverDemoOverrides(),
        myListingsProvider(
          'rental',
        ).overrideWith((ref) async => [rentalListing]),
        bookingsProvider(
          const BookingsQuery(role: 'vendor', type: 'rental'),
        ).overrideWith((ref) async => <MarketplaceBooking>[]),
        publishedListingsProvider(
          const PublishedQuery(
            type: 'rental',
            categoryId: 'residential',
            subcategoryId: 'apartments_flats',
          ),
        ).overrideWith((ref) async => [rentalListing]),
        publishedListingsProvider(
          const PublishedQuery(type: 'rental'),
        ).overrideWith((ref) async => [rentalListing]),
      ],
    );
    addTearDown(container.dispose);
    container.read(sessionUserProfileProvider.notifier).setProfile(demoProfile);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _shotApp(child: const RentalVendorHomeView()),
      ),
    );
    await tester.pumpAndSettle();
    await shot(tester, 'rental_vendor_01_home');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _shotApp(child: const RentalPostPropertyView()),
      ),
    );
    await tester.pumpAndSettle();
    await shot(tester, 'rental_vendor_02_post_property');

    await tester.drag(
      find.byType(ListView).first,
      const Offset(0, -2200),
    );
    await tester.pumpAndSettle();
    await shot(tester, 'rental_vendor_02_post_bottom');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _shotApp(
          child: const RentalCategoryView(
            categoryId: 'residential',
            subcategoryId: 'apartments_flats',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -1400),
    );
    await tester.pumpAndSettle();
    await shot(tester, 'rental_vendor_03_passenger_listing');
  });

  // Driver wallet (inDrive-style points wallet) + the passenger sidebar's
  // combined "Earn on ORA" entry and its four-option sheet.
  testWidgets('wallet + earn sheet', (tester) async {
    surfaceConverted = false;
    final container = ProviderContainer(
      overrides: [
        ...driverDemoOverrides(),
        ..._walletOverrides,
        homeViewModelProvider.overrideWith(() => _FakeHomeVm()),
        rideHistoryViewModelProvider.overrideWith(
          () => _FakeRideHistoryVm(),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(sessionUserProfileProvider.notifier).setProfile(demoProfile);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _shotApp(child: const DriverWalletView()),
      ),
    );
    await tester.pumpAndSettle();
    await shot(tester, 'driver_10_wallet');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _shotApp(child: const DriverAddPointsView()),
      ),
    );
    await tester.pumpAndSettle();
    await shot(tester, 'driver_11_add_points');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _shotApp(child: const HomeShellView()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Menu').first);
    await tester.pumpAndSettle();
    await shot(tester, 'earn_01_drawer');
    await tester.ensureVisible(find.text('Earn on ORA'));
    await tester.tap(find.text('Earn on ORA'));
    await tester.pumpAndSettle();
    await shot(tester, 'earn_02_sheet');
  });
}
