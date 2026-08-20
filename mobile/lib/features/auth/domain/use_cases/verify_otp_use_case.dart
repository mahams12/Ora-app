import '../entities/auth_user.dart';
import '../entities/otp_session.dart';
import '../repositories/auth_repository.dart';

/// Verifies the 6-digit OTP entered by the user.
///
/// On success the repository handles Firebase sign-in and, if this is a new
/// user, triggers the `POST /v1/auth/register` backend call.
class VerifyOtpUseCase {
  const VerifyOtpUseCase(this._repository);

  final AuthRepository _repository;

  Future<AuthUser> call({
    required OtpSession session,
    required String otpCode,
  }) =>
      _repository.verifyOtp(session: session, otpCode: otpCode);
}
