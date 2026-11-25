class AppRoutes {
  AppRoutes._();

  static const splash = '/';

  // Auth flow
  static const phoneEntry = '/auth/phone';
  static const otpEntry = '/auth/otp';

  // Onboarding (foundation — full flow in later phase)
  static const onboarding = '/onboarding';

  // Protected
  static const home = '/home';
  static const profile = '/profile';
  static const driverRegistration = '/become-driver';

  /// Partner/vendor registrations (single-scroll forms).
  static const cargoRegistration = '/register/cargo';
  static const rentalRegistration = '/register/rental';
  static const serviceVendorRegistration = '/register/services';

  /// Registered service-vendor area (post & manage marketplace services).
  static const vendorHome = '/vendor';
  static const vendorPostService = '/vendor/post-service';
  static const vendorBookingsService = '/vendor/bookings';

  /// Shared partner wallet under the services-vendor area.
  static const vendorWallet = '/vendor/wallet';
  static const vendorWalletAddPoints = '/vendor/wallet/add-points';

  /// Approved logistics-partner area — a driver-style shell that receives
  /// realtime delivery offers through the shared rides pipeline.
  static const logisticsVendorHome = '/logistics-vendor';

  /// Logistics assigned-job detail. Use [logisticsDeliveryPath].
  static const logisticsDelivery = '/logistics-vendor/deliveries/:rideId';

  /// Shared vendor wallet under the logistics shell.
  static const logisticsVendorWallet = '/logistics-vendor/wallet';
  static const logisticsVendorWalletAddPoints =
      '/logistics-vendor/wallet/add-points';

  /// Registered rental-vendor area (post & manage properties that
  /// surface on the passenger Rental pages).
  static const rentalVendorHome = '/rental-vendor';
  static const rentalVendorPost = '/rental-vendor/post-property';
  static const vendorBookingsRental = '/rental-vendor/bookings';

  /// Shared partner wallet under the rental-vendor area.
  static const rentalVendorWallet = '/rental-vendor/wallet';
  static const rentalVendorWalletAddPoints =
      '/rental-vendor/wallet/add-points';

  /// Customer marketplace bookings/requests history.
  static const myBookings = '/bookings';

  /// Passenger's ride services hub.
  static const ridesHub = '/rides';
  static const logistics = '/logistics';
  static const rental = '/rental';
  static const rentalCategory = '/rental/category/:categoryId';
  static const services = '/services';
  static const servicesSearch = '/services/search';
  static const servicesBookings = '/services/bookings';
  static const servicesSaved = '/services/saved';
  static const servicesCategory = '/services/:categoryId';
  static const servicesSubcategory = '/services/:categoryId/:subId';

  /// Passenger ride compose (Slice D).
  static const rideRequest = '/rides/request';

  /// Honest post-create state.
  static const rideRequestCreated = '/rides/requested';

  /// Passenger offers inbox (Slice E). Use [offersInboxPath].
  static const offersInbox = '/rides/:rideId/offers';

  /// Passenger active ride (Slice F). Use [activeRidePath].
  static const activeRide = '/rides/:rideId/active';

  /// Ride chat — passenger side. Use [rideChatPath].
  static const rideChat = '/rides/:rideId/chat';

  /// Ride chat — driver side. Use [driverRideChatPath].
  static const driverRideChat = '/driver/rides/:rideId/chat';

  /// Past ride detail (Slice H). Use [rideHistoryDetailPath].
  static const rideHistoryDetail = '/rides/:rideId/detail';

  /// Passenger stars rating (Slice I). Use [rideRatingPath].
  static const rideRating = '/rides/:rideId/rate';

  /// Disposable MapLibre renderer PoC — NOT production map / NOT ride flow.
  static const mapLibrePoc = '/devtools/maplibre-poc';

  /// Driver shell (Slice L) — approved drivers only.
  static const driverHome = '/driver';

  /// Driver open ride requests (GET /v1/rides/open).
  static const driverOpen = '/driver/open';

  /// Driver assigned rides list (GET /v1/rides as approved driver).
  static const driverRides = '/driver/rides';

  /// Driver assigned-job detail. Use [driverRidePath].
  static const driverRide = '/driver/rides/:rideId';

  /// Driver vendor wallet — points balance, top-up and withdrawals.
  static const driverWallet = '/driver/wallet';

  /// Wallet top-up screen — amount, payment method, summary.
  static const driverWalletAddPoints = '/driver/wallet/add-points';

  static String offersInboxPath(String rideId) =>
      '/rides/${Uri.encodeComponent(rideId)}/offers';

  static String rideRequestUri({String? category, String? service}) => Uri(
    path: rideRequest,
    queryParameters: {
      if (category != null && category.isNotEmpty) 'category': category,
      if (service != null && service.isNotEmpty) 'service': service,
    },
  ).toString();

  static String rentalCategoryPath(
    String categoryId, {
    String? subcategoryId,
  }) => Uri(
    path: '/rental/category/${Uri.encodeComponent(categoryId)}',
    queryParameters: {
      if (subcategoryId != null && subcategoryId.isNotEmpty)
        'subcategory': subcategoryId,
    },
  ).toString();

  static String servicesCategoryPath(String categoryId) =>
      '/services/${Uri.encodeComponent(categoryId)}';

  static String servicesSubcategoryPath(String categoryId, String subId) =>
      '/services/${Uri.encodeComponent(categoryId)}/'
      '${Uri.encodeComponent(subId)}';

  static String servicesSearchPath(String query) =>
      Uri(path: servicesSearch, queryParameters: {'q': query}).toString();

  static String activeRidePath(String rideId) =>
      '/rides/${Uri.encodeComponent(rideId)}/active';

  static String rideChatPath(String rideId) =>
      '/rides/${Uri.encodeComponent(rideId)}/chat';

  static String driverRideChatPath(String rideId) =>
      '/driver/rides/${Uri.encodeComponent(rideId)}/chat';

  static String rideHistoryDetailPath(String rideId) =>
      '/rides/${Uri.encodeComponent(rideId)}/detail';

  static String rideRatingPath(String rideId) =>
      '/rides/${Uri.encodeComponent(rideId)}/rate';

  static String driverRidePath(String rideId) =>
      '/driver/rides/${Uri.encodeComponent(rideId)}';

  static String logisticsDeliveryPath(String rideId) =>
      '/logistics-vendor/deliveries/${Uri.encodeComponent(rideId)}';
}
