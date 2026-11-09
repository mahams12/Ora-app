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

  /// Passenger's ride services hub.
  static const ridesHub = '/rides';
  static const logistics = '/logistics';
  static const logisticsSearch = '/logistics/search';
  static const logisticsCategory = '/logistics/:categoryId';
  static const logisticsQuote = '/logistics/:categoryId/:typeId/quote';
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

  /// Direct offer by known rideId (lab/direct — not marketplace).
  static const driverDirectOffer = '/driver/offer';

  static String offersInboxPath(String rideId) =>
      '/rides/${Uri.encodeComponent(rideId)}/offers';

  static String rideRequestUri({String? category, String? service}) => Uri(
    path: rideRequest,
    queryParameters: {
      if (category != null && category.isNotEmpty) 'category': category,
      if (service != null && service.isNotEmpty) 'service': service,
    },
  ).toString();

  static String logisticsCategoryPath(String categoryId) =>
      '/logistics/${Uri.encodeComponent(categoryId)}';

  static String logisticsQuotePath(String categoryId, String typeId) =>
      '/logistics/${Uri.encodeComponent(categoryId)}/'
      '${Uri.encodeComponent(typeId)}/quote';

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

  static String logisticsSearchPath(String query) =>
      Uri(path: logisticsSearch, queryParameters: {'q': query}).toString();

  static String servicesCategoryPath(String categoryId) =>
      '/services/${Uri.encodeComponent(categoryId)}';

  static String servicesSubcategoryPath(String categoryId, String subId) =>
      '/services/${Uri.encodeComponent(categoryId)}/'
      '${Uri.encodeComponent(subId)}';

  static String servicesSearchPath(String query) =>
      Uri(path: servicesSearch, queryParameters: {'q': query}).toString();

  static String activeRidePath(String rideId) =>
      '/rides/${Uri.encodeComponent(rideId)}/active';

  static String rideHistoryDetailPath(String rideId) =>
      '/rides/${Uri.encodeComponent(rideId)}/detail';

  static String rideRatingPath(String rideId) =>
      '/rides/${Uri.encodeComponent(rideId)}/rate';

  static String driverRidePath(String rideId) =>
      '/driver/rides/${Uri.encodeComponent(rideId)}';
}
