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

  /// Driver shell (Slice L) — approved drivers only.
  static const driverHome = '/driver';

  /// Driver assigned rides list (GET /v1/rides as approved driver).
  static const driverRides = '/driver/rides';

  /// Driver assigned-job detail. Use [driverRidePath].
  static const driverRide = '/driver/rides/:rideId';

  /// Direct offer by known rideId (lab/direct — not marketplace).
  static const driverDirectOffer = '/driver/offer';

  static String offersInboxPath(String rideId) =>
      '/rides/${Uri.encodeComponent(rideId)}/offers';

  static String activeRidePath(String rideId) =>
      '/rides/${Uri.encodeComponent(rideId)}/active';

  static String rideHistoryDetailPath(String rideId) =>
      '/rides/${Uri.encodeComponent(rideId)}/detail';

  static String rideRatingPath(String rideId) =>
      '/rides/${Uri.encodeComponent(rideId)}/rate';

  static String driverRidePath(String rideId) =>
      '/driver/rides/${Uri.encodeComponent(rideId)}';
}
