import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/views/otp_entry_view.dart';
import '../../features/auth/presentation/views/phone_entry_view.dart';
import '../../features/auth/presentation/views/profile_view.dart';
import '../../features/auth/presentation/views/splash_view.dart';
import '../../features/driver/presentation/views/driver_add_points_view.dart';
import '../../features/driver/presentation/views/driver_assigned_ride_view.dart';
import '../../features/driver/presentation/views/driver_registration_view.dart';
import '../../features/driver/presentation/views/driver_shell_view.dart';
import '../../features/driver/presentation/views/driver_wallet_view.dart';
import '../../features/onboarding/presentation/views/onboarding_view.dart';
import '../../features/maps/poc/maplibre_poc_view.dart';
import '../../features/passenger/presentation/views/home_shell_view.dart';
import '../../features/registration/views/cargo_registration_view.dart';
import '../../features/registration/views/rental_registration_view.dart';
import '../../features/registration/views/service_vendor_registration_view.dart';
import '../../features/logistics_vendor/presentation/views/logistics_shell_view.dart';
import '../../features/rental_vendor/presentation/views/rental_post_property_view.dart';
import '../../features/rental_vendor/presentation/views/rental_vendor_home_view.dart';
import '../../features/vendor/presentation/views/vendor_home_view.dart';
import '../../features/vendor/presentation/views/vendor_post_service_view.dart';
import '../../features/marketplace/data/marketplace_models.dart';
import '../../features/marketplace/presentation/views/my_bookings_view.dart';
import '../../features/marketplace/presentation/views/vendor_bookings_view.dart';
import '../../features/marketplace/logistics/presentation/views/logistics_home_view.dart';
import '../../features/marketplace/rental/presentation/views/rental_category_view.dart';
import '../../features/marketplace/rental/presentation/views/rental_home_view.dart';
import '../../features/marketplace/services/presentation/views/service_providers_view.dart';
import '../../features/marketplace/services/presentation/views/services_category_view.dart';
import '../../features/marketplace/services/presentation/views/services_empty_view.dart';
import '../../features/marketplace/services/presentation/views/services_home_view.dart';
import '../../features/marketplace/services/presentation/views/services_search_results_view.dart';
import '../../features/marketplace/services/presentation/widgets/services_module_navigation.dart';
import '../../features/super_app/presentation/views/rides_hub_view.dart';
import '../../features/ride/presentation/views/active_ride_view.dart';
import '../../features/ride/presentation/views/offers_inbox_view.dart';
import '../../features/ride/presentation/views/ride_history_detail_view.dart';
import '../../features/ride/presentation/views/ride_rating_view.dart';
import '../../features/ride/presentation/views/ride_request_created_view.dart';
import '../../features/ride/presentation/views/ride_request_view.dart';
import 'route_guards.dart';
import 'routes.dart';

/// Creates the app-level [GoRouter].
///
/// Destination is owned by [AuthRouteGuard]. Pass [refreshListenable] so
/// auth-status changes re-evaluate redirects without rebuilding a new router.
GoRouter createAppRouter({
  String initialLocation = AppRoutes.splash,
  Ref? ref,
  Listenable? refreshListenable,
}) {
  final guard = ref != null ? AuthRouteGuard(ref) : null;

  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: refreshListenable,
    redirect: guard != null
        ? (context, state) => guard.redirect(state)
        : (context, state) => null,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        name: 'splash',
        builder: (context, state) => const SplashView(),
      ),
      GoRoute(
        path: AppRoutes.phoneEntry,
        name: 'phone-entry',
        builder: (context, state) => const PhoneEntryView(),
      ),
      GoRoute(
        path: AppRoutes.otpEntry,
        name: 'otp-entry',
        builder: (context, state) => const OtpEntryView(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        name: 'onboarding',
        builder: (context, state) => const OnboardingView(),
      ),
      GoRoute(
        path: AppRoutes.home,
        name: 'home',
        builder: (context, state) => const HomeShellView(),
      ),
      GoRoute(
        path: AppRoutes.profile,
        name: 'profile',
        builder: (context, state) => const ProfileView(),
      ),
      GoRoute(
        path: AppRoutes.driverRegistration,
        name: 'driver-registration',
        builder: (context, state) => const DriverRegistrationView(),
      ),
      GoRoute(
        path: AppRoutes.cargoRegistration,
        name: 'cargo-registration',
        builder: (context, state) => const CargoRegistrationView(),
      ),
      GoRoute(
        path: AppRoutes.rentalRegistration,
        name: 'rental-registration',
        builder: (context, state) => const RentalRegistrationView(),
      ),
      GoRoute(
        path: AppRoutes.serviceVendorRegistration,
        name: 'service-vendor-registration',
        builder: (context, state) => const ServiceVendorRegistrationView(),
      ),
      GoRoute(
        path: AppRoutes.vendorPostService,
        name: 'vendor-post-service',
        builder: (context, state) =>
            VendorPostServiceView(existing: state.extra as MarketplaceListing?),
      ),
      GoRoute(
        path: AppRoutes.vendorHome,
        name: 'vendor-home',
        builder: (context, state) => const VendorHomeView(),
      ),
      GoRoute(
        path: AppRoutes.vendorBookingsService,
        name: 'vendor-bookings-service',
        builder: (context, state) => const VendorBookingsView(type: 'service'),
      ),
      GoRoute(
        path: AppRoutes.vendorWallet,
        name: 'vendor-wallet',
        builder: (context, state) => const DriverWalletView(
          homeRoute: AppRoutes.vendorHome,
          addPointsRoute: AppRoutes.vendorWalletAddPoints,
        ),
      ),
      GoRoute(
        path: AppRoutes.vendorWalletAddPoints,
        name: 'vendor-wallet-add-points',
        builder: (context, state) => const DriverAddPointsView(
          walletRoute: AppRoutes.vendorWallet,
        ),
      ),
      GoRoute(
        path: AppRoutes.vendorBookingsRental,
        name: 'vendor-bookings-rental',
        builder: (context, state) => const VendorBookingsView(type: 'rental'),
      ),
      GoRoute(
        path: AppRoutes.myBookings,
        name: 'my-bookings',
        builder: (context, state) => const MyBookingsView(),
      ),
      GoRoute(
        path: AppRoutes.logisticsVendorHome,
        name: 'logistics-vendor-home',
        builder: (context, state) => const LogisticsShellView(),
      ),
      GoRoute(
        path: AppRoutes.logisticsDelivery,
        name: 'logistics-delivery',
        builder: (context, state) {
          final rideId = state.pathParameters['rideId'] ?? '';
          return DriverAssignedRideView(
            rideId: rideId,
            title: 'Active Delivery',
            subtitle: 'Manage your current delivery',
            homeRoute: AppRoutes.logisticsVendorHome,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.logisticsVendorWallet,
        name: 'logistics-vendor-wallet',
        builder: (context, state) => const DriverWalletView(
          homeRoute: AppRoutes.logisticsVendorHome,
          addPointsRoute: AppRoutes.logisticsVendorWalletAddPoints,
        ),
      ),
      GoRoute(
        path: AppRoutes.logisticsVendorWalletAddPoints,
        name: 'logistics-vendor-wallet-add-points',
        builder: (context, state) => const DriverAddPointsView(
          walletRoute: AppRoutes.logisticsVendorWallet,
        ),
      ),
      GoRoute(
        path: AppRoutes.rentalVendorHome,
        name: 'rental-vendor-home',
        builder: (context, state) => const RentalVendorHomeView(),
      ),
      GoRoute(
        path: AppRoutes.rentalVendorPost,
        name: 'rental-vendor-post',
        builder: (context, state) => RentalPostPropertyView(
          existing: state.extra as MarketplaceListing?,
        ),
      ),
      GoRoute(
        path: AppRoutes.rentalVendorWallet,
        name: 'rental-vendor-wallet',
        builder: (context, state) => const DriverWalletView(
          homeRoute: AppRoutes.rentalVendorHome,
          addPointsRoute: AppRoutes.rentalVendorWalletAddPoints,
        ),
      ),
      GoRoute(
        path: AppRoutes.rentalVendorWalletAddPoints,
        name: 'rental-vendor-wallet-add-points',
        builder: (context, state) => const DriverAddPointsView(
          walletRoute: AppRoutes.rentalVendorWallet,
        ),
      ),
      GoRoute(
        path: AppRoutes.ridesHub,
        name: 'rides-hub',
        builder: (context, state) => const RidesHubView(),
      ),
      GoRoute(
        path: AppRoutes.logistics,
        name: 'logistics',
        builder: (context, state) => const LogisticsHomeView(),
      ),
      GoRoute(
        path: AppRoutes.servicesSearch,
        name: 'services-search',
        builder: (context, state) => ServicesSearchResultsView(
          query: state.uri.queryParameters['q'] ?? '',
        ),
      ),
      GoRoute(
        path: AppRoutes.servicesBookings,
        name: 'services-bookings',
        builder: (context, state) => const ServicesEmptyView(
          destination: ServicesNavigationDestination.bookings,
        ),
      ),
      GoRoute(
        path: AppRoutes.servicesSaved,
        name: 'services-saved',
        builder: (context, state) => const ServicesEmptyView(
          destination: ServicesNavigationDestination.saved,
        ),
      ),
      GoRoute(
        path: AppRoutes.servicesSubcategory,
        name: 'services-subcategory',
        builder: (context, state) => ServiceProvidersView(
          categoryId: state.pathParameters['categoryId'] ?? '',
          subcategoryId: state.pathParameters['subId'] ?? '',
          providers: const [],
        ),
      ),
      GoRoute(
        path: AppRoutes.servicesCategory,
        name: 'services-category',
        builder: (context, state) => ServicesCategoryView(
          categoryId: state.pathParameters['categoryId'] ?? '',
        ),
      ),
      GoRoute(
        path: AppRoutes.services,
        name: 'services',
        builder: (context, state) => const ServicesHomeView(),
      ),
      GoRoute(
        path: AppRoutes.rentalCategory,
        name: 'rental-category',
        builder: (context, state) => RentalCategoryView(
          categoryId: state.pathParameters['categoryId'] ?? '',
          subcategoryId: state.uri.queryParameters['subcategory'],
        ),
      ),
      GoRoute(
        path: AppRoutes.rental,
        name: 'rental',
        builder: (context, state) => const RentalHomeView(),
      ),
      GoRoute(
        path: AppRoutes.mapLibrePoc,
        name: 'maplibre-poc',
        builder: (context, state) => const MapLibrePoCView(),
      ),
      GoRoute(
        path: AppRoutes.rideRequest,
        name: 'ride-request',
        builder: (context, state) => RideRequestView(
          initialCategoryId: state.uri.queryParameters['category'],
          initialServiceType: state.uri.queryParameters['service'],
        ),
      ),
      GoRoute(
        path: AppRoutes.rideRequestCreated,
        name: 'ride-requested',
        builder: (context, state) {
          final rideId = state.uri.queryParameters['rideId'] ?? '';
          final rideState = state.uri.queryParameters['state'] ?? 'SEARCHING';
          return RideRequestCreatedView(rideId: rideId, serverState: rideState);
        },
      ),
      GoRoute(
        path: AppRoutes.offersInbox,
        name: 'offers-inbox',
        builder: (context, state) {
          final rideId = state.pathParameters['rideId'] ?? '';
          return OffersInboxView(rideId: rideId);
        },
      ),
      GoRoute(
        path: AppRoutes.activeRide,
        name: 'active-ride',
        builder: (context, state) {
          final rideId = state.pathParameters['rideId'] ?? '';
          return ActiveRideView(rideId: rideId);
        },
      ),
      GoRoute(
        path: AppRoutes.rideHistoryDetail,
        name: 'ride-history-detail',
        builder: (context, state) {
          final rideId = state.pathParameters['rideId'] ?? '';
          return RideHistoryDetailView(rideId: rideId);
        },
      ),
      GoRoute(
        path: AppRoutes.rideRating,
        name: 'ride-rating',
        builder: (context, state) {
          final rideId = state.pathParameters['rideId'] ?? '';
          return RideRatingView(rideId: rideId);
        },
      ),
      GoRoute(
        path: AppRoutes.driverHome,
        name: 'driver-home',
        builder: (context, state) =>
            const DriverShellView(initialTab: DriverShellPage.home),
      ),
      GoRoute(
        path: AppRoutes.driverOpen,
        name: 'driver-open',
        builder: (context, state) =>
            const DriverShellView(initialTab: DriverShellPage.open),
      ),
      GoRoute(
        path: AppRoutes.driverRides,
        name: 'driver-rides',
        builder: (context, state) =>
            const DriverShellView(initialTab: DriverShellPage.assigned),
      ),
      GoRoute(
        path: AppRoutes.driverRide,
        name: 'driver-ride',
        builder: (context, state) {
          final rideId = state.pathParameters['rideId'] ?? '';
          return DriverAssignedRideView(rideId: rideId);
        },
      ),
      GoRoute(
        path: AppRoutes.driverWallet,
        name: 'driver-wallet',
        builder: (context, state) => const DriverWalletView(),
      ),
      GoRoute(
        path: AppRoutes.driverWalletAddPoints,
        name: 'driver-wallet-add-points',
        builder: (context, state) => const DriverAddPointsView(),
      ),
    ],
    errorBuilder: (context, state) =>
        Scaffold(body: Center(child: Text('Route not found: ${state.uri}'))),
  );
}
