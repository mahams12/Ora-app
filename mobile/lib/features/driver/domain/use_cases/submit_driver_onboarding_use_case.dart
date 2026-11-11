import '../driver_onboarding_application.dart';
import '../repositories/driver_onboarding_repository.dart';

class SubmitDriverOnboardingUseCase {
  const SubmitDriverOnboardingUseCase(this._repository);

  final DriverOnboardingRepository _repository;

  Future<DriverOnboardingResult> call(
    DriverOnboardingApplication application,
  ) => _repository.submit(application);
}
