import '../entities/auth_user.dart';
import '../entities/otp_session.dart';
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
  /// Server initiates an SMS dispatch.  Returns an [OtpSession] containing
  /// the opaque session ID needed to verify or resend.
  ///
  /// Throws [InvalidPhoneFailure] for malformed numbers.
  /// Throws [TooManyAttemptsFailure] / [OtpCooldownFailure] when rate-limited.
  Future<OtpSession> requestOtp({required String phoneE164});

  /// Verifies [otpCode] against the active [session].
  ///
  /// On success, Firebase Auth signs in and the updated [AuthUser] is returned.
  /// A `POST /v1/auth/register` call is made if this is the first sign-in.
  ///
  /// Throws [InvalidOtpFailure], [OtpExpiredFailure], [TooManyAttemptsFailure],
  /// [AccountDisabledFailure].
  Future<AuthUser> verifyOtp({
    required OtpSession session,
    required String otpCode,
  });

  /// Requests a new OTP for the same phone in [session].
  ///
  /// Server enforces the 30 s cooldown and maxResends = 3.
  ///
  /// Throws [OtpCooldownFailure] when cooldown is active.
  Future<OtpSession> resendOtp({required OtpSession session});

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

  /// Loads the minimal [UserProfile] from Firestore after sign-in.
  Future<UserProfile> getUserProfile({required String uid});

  /// Registers a new user document on the backend after first sign-in.
  Future<void> registerUser({required String uid});

  /// Clears all auth state: Firebase sign-out, secure storage wipe.
  Future<void> logout();
}
