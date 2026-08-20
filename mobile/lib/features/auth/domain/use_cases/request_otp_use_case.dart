import '../entities/otp_session.dart';
import '../repositories/auth_repository.dart';

/// Initiates a phone OTP request.
///
/// Validation of E.164 format is performed on the server; the use case
/// passes through all [AppFailure] variants thrown by the repository.
class RequestOtpUseCase {
  const RequestOtpUseCase(this._repository);

  final AuthRepository _repository;

  Future<OtpSession> call({required String phoneE164}) =>
      _repository.requestOtp(phoneE164: phoneE164);
}
