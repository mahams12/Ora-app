import '../entities/auth_user.dart';
import '../entities/otp_session.dart';
import '../entities/phone_verification_result.dart';
import '../entities/user_profile.dart';

/// Domain contract for authentication operations.
///
/// Concrete implementations live in the data layer and are hidden behind
/// this interface.  ViewModels and use cases depend only on this interface.
///
/// Rules enforced here:
/// - All [AppFailure] variants are thrown by the implementation; callers
///   catch them in use cases and map to UI states.
/// - Token management and Firebase internals must NOT leak to callers.
abstract interface class AuthRepository {
  /// Stream of the currently authenticated [AuthUser], or null when
  /// unauthenticated.  Source of truth is Firebase Auth state.
  Stream<AuthUser?> get authStateChanges;

  /// Returns the current authenticated user or null (synchronous snapshot).
  Future<AuthUser?> getCurrentUser();

  /// Requests an OTP for [phoneE164] (E.164 format, e.g. '+923001234567').
  ///
  /// Returns [PhoneCodeSent] for the manual SMS path, or [PhoneAutoSignedIn]
  /// when Android auto-retrieval already signed the user in.
  Future<PhoneVerificationResult> requestOtp({required String phoneE164});

  /// Verifies [otpCode] against the active [session].
  ///
  /// On success, Firebase Auth signs in and the updated [AuthUser] is returned.
  /// Backend registration happens once in [ResolveAuthProfileUseCase].
  ///
  /// Throws [InvalidOtpFailure], [OtpExpiredFailure], [TooManyAttemptsFailure],
  /// [AccountDisabledFailure].
  Future<AuthUser> verifyOtp({
    required OtpSession session,
    required String otpCode,
  });

  /// Requests a new OTP for the same phone in [session].
  Future<PhoneVerificationResult> resendOtp({required OtpSession session});

  /// Restores an existing session from secure storage on app restart.
  ///
  /// Returns the current [AuthUser] if the stored Firebase token is valid
  /// (or was successfully refreshed).  Returns null if no session exists or
  /// refresh failed.
  Future<AuthUser?> restoreSession();

  /// Forces a Firebase ID-token refresh.
  ///
  /// Throws [SessionExpiredFailure] when Firebase cannot refresh.
  Future<String> refreshToken();

  /// Loads the canonical profile for the signed-in user (`GET /v1/auth/me`).
  /// [uid] is ignored by the API; identity comes from the bearer token.
  Future<UserProfile> getUserProfile({required String uid});

  /// Registers a new user document on the backend after first sign-in.
  /// Failures propagate — callers must not swallow them.
  Future<void> registerUser({required String uid});

  /// Updates the authenticated user's displayName (`PATCH /v1/auth/profile`).
  Future<UserProfile> updateDisplayName({required String displayName});

  /// Clears all auth state: Firebase sign-out, secure storage wipe.
  Future<void> logout();
}
