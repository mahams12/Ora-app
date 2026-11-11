import '../driver_onboarding_application.dart';

abstract interface class DriverOnboardingRepository {
  Future<DriverOnboardingResult> submit(
    DriverOnboardingApplication application,
  );
}
