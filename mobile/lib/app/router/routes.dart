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
}
