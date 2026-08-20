import '../../domain/entities/auth_user.dart';
import '../../domain/entities/otp_session.dart';

/// Top-level auth flow status used by route guards.
enum AuthStatus {
  /// Session check not yet complete (app start).
  unknown,

  /// No valid Firebase session; user must sign in.
  unauthenticated,

  /// Firebase signed in but profile check not yet done.
  authenticated,

  /// Authenticated; profile bootstrap required before home.
  onboardingRequired,

  /// Fully authenticated and profile is complete.
  authenticatedReady,
}

/// View state for the OTP-based sign-in flow.
///
/// All subtypes are public so view/viewmodel files can pattern-match on them.
sealed class AuthFlowState {
  const AuthFlowState();
}

/// Default state before the auth flow starts.
final class AuthFlowIdle extends AuthFlowState {
  const AuthFlowIdle();
}

/// User is entering their phone number.
final class AuthFlowPhoneEntry extends AuthFlowState {
  const AuthFlowPhoneEntry();
}

/// OTP request in flight.
final class AuthFlowRequestingOtp extends AuthFlowState {
  const AuthFlowRequestingOtp();
}

/// OTP sent; user must enter the code.
final class AuthFlowOtpSent extends AuthFlowState {
  const AuthFlowOtpSent({required this.session});
  final OtpSession session;
}

/// Verifying the entered code.
final class AuthFlowVerifyingOtp extends AuthFlowState {
  const AuthFlowVerifyingOtp({required this.session});
  final OtpSession session;
}

/// Resend request in flight.
final class AuthFlowResendingOtp extends AuthFlowState {
  const AuthFlowResendingOtp({required this.session});
  final OtpSession session;
}

/// Resend blocked by cooldown — remaining tick drives the UI countdown.
final class AuthFlowResendCooldown extends AuthFlowState {
  const AuthFlowResendCooldown({
    required this.session,
    required this.remaining,
  });
  final OtpSession session;
  final Duration remaining;
}

/// OTP verified; user signed in.
final class AuthFlowAuthenticated extends AuthFlowState {
  const AuthFlowAuthenticated({required this.user});
  final AuthUser user;
}

/// A recoverable error in the auth flow.
final class AuthFlowError extends AuthFlowState {
  const AuthFlowError({required this.message, this.previousState});
  final String message;
  final AuthFlowState? previousState;
}
