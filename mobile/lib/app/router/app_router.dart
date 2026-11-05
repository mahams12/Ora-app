import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/views/otp_entry_view.dart';
import '../../features/auth/presentation/views/phone_entry_view.dart';
import '../../features/auth/presentation/views/splash_view.dart';
import '../../features/driver/presentation/views/driver_assigned_ride_view.dart';
import '../../features/driver/presentation/views/driver_shell_view.dart';
import '../../features/onboarding/presentation/views/onboarding_view.dart';
import '../../features/maps/poc/maplibre_poc_view.dart';
import '../../features/passenger/presentation/views/home_shell_view.dart';
import '../../features/marketplace/logistics/presentation/views/logistics_category_view.dart';
import '../../features/marketplace/logistics/presentation/views/logistics_home_view.dart';
import '../../features/marketplace/logistics/presentation/views/logistics_search_results_view.dart';
import '../../features/marketplace/logistics/presentation/views/quote_request_form.dart';
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
        path: AppRoutes.ridesHub,
        name: 'rides-hub',
        builder: (context, state) => const RidesHubView(),
      ),
      GoRoute(
        path: AppRoutes.logisticsSearch,
        name: 'logistics-search',
        builder: (context, state) => LogisticsSearchResultsView(
          query: state.uri.queryParameters['q'] ?? '',
        ),
      ),
      GoRoute(
        path: AppRoutes.logisticsQuote,
        name: 'logistics-quote',
        builder: (context, state) => QuoteRequestForm(
          categoryId: state.pathParameters['categoryId'] ?? '',
          typeId: state.pathParameters['typeId'] ?? '',
        ),
      ),
      GoRoute(
        path: AppRoutes.logisticsCategory,
        name: 'logistics-category',
        builder: (context, state) => LogisticsCategoryView(
          categoryId: state.pathParameters['categoryId'] ?? '',
        ),
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
        path: AppRoutes.driverDirectOffer,
        name: 'driver-direct-offer',
        builder: (context, state) =>
            const DriverShellView(initialTab: DriverShellPage.offer),
      ),
    ],
    errorBuilder: (context, state) =>
        Scaffold(body: Center(child: Text('Route not found: ${state.uri}'))),
  );
}
