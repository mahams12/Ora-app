import 'otp_session.dart';
import 'auth_user.dart';

/// Result of Firebase phone verification.
///
/// Android may auto-retrieve the SMS and sign in without a typed code.
/// That path must never invent a verification ID such as `"auto"`.
sealed class PhoneVerificationResult {
  const PhoneVerificationResult();
}

/// SMS sent; the user must enter the code (or wait for auto-retrieval).
final class PhoneCodeSent extends PhoneVerificationResult {
  const PhoneCodeSent(this.session);
  final OtpSession session;
}

/// Android auto-verification signed the user in with the real credential.
final class PhoneAutoSignedIn extends PhoneVerificationResult {
  const PhoneAutoSignedIn(this.user);
  final AuthUser user;
}
