import '../entities/user_profile.dart';
import '../repositories/auth_repository.dart';

/// Server-authoritative Passenger ⇄ Driver mode switch.
///
/// Conflict codes surfaced via AppFailure: DRIVER_ONBOARDING_REQUIRED,
/// DRIVER_APPROVAL_PENDING, ACTIVE_JOB; forbidden for DRIVER_SUSPENDED.
class SwitchModeUseCase {
  const SwitchModeUseCase(this._repository);

  final AuthRepository _repository;

  Future<UserProfile> call({required String mode}) =>
      _repository.switchMode(mode: mode);
}
