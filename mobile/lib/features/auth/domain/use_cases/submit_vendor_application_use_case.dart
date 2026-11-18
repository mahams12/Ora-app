import '../entities/user_profile.dart';
import '../repositories/auth_repository.dart';

/// Server-authoritative partner application (cargo / rental host / service
/// provider). Mirrors the driver onboarding gate: submit once → 'pending'
/// until an admin approves. The returned profile already carries the new
/// vendorApplications entry so the session can re-gate immediately.
class SubmitVendorApplicationUseCase {
  const SubmitVendorApplicationUseCase(this._repository);

  final AuthRepository _repository;

  Future<UserProfile> call({
    required String type,
    Map<String, dynamic>? details,
  }) =>
      _repository.submitVendorApplication(type: type, details: details);
}
