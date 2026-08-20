import '../entities/otp_session.dart';
import '../repositories/auth_repository.dart';

/// Requests a new OTP code for the same phone number.
/// Firebase owns OTP quotas (ADR-016). Ora client applies a 30s UX cooldown.
class ResendOtpUseCase {
  const ResendOtpUseCase(this._repository);

  final AuthRepository _repository;

  Future<OtpSession> call({required OtpSession session}) =>
      _repository.resendOtp(session: session);
}
