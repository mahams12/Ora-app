import '../repositories/auth_repository.dart';

/// First-time driver application (Switch to Driver onboarding step).
/// Returns the raw response — `data.driverStatus` is 'pending' on success.
class SubmitDriverOnboardingUseCase {
  const SubmitDriverOnboardingUseCase(this._repository);

  final AuthRepository _repository;

  Future<Map<String, dynamic>> call({
    required String vehicleType,
    String? vehicleModel,
    String? plateNumber,
    String? homeCity,
  }) =>
      _repository.submitDriverOnboarding(
        vehicleType: vehicleType,
        vehicleModel: vehicleModel,
        plateNumber: plateNumber,
        homeCity: homeCity,
      );
}
