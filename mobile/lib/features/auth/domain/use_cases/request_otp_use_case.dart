import '../entities/phone_verification_result.dart';
import '../repositories/auth_repository.dart';

/// Initiates a phone OTP request (or Android auto-sign-in).
class RequestOtpUseCase {
  const RequestOtpUseCase(this._repository);

  final AuthRepository _repository;

  Future<PhoneVerificationResult> call({required String phoneE164}) =>
      _repository.requestOtp(phoneE164: phoneE164);
}
