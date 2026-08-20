/// Centralised key constants for secure and local storage.
/// Never store tokens, OTPs, or secrets outside of [SecureStorage].
class StorageKeys {
  StorageKeys._();

  // ── Idempotency (persisted for app-kill/restart recovery) ────────────────
  static const String idempotencyKeyPrefix = 'idempotency_';

  // ── Auth / session (SecureStorage only) ──────────────────────────────────
  //
  // No key exists for the session, uid, ID token, or refresh token: Firebase
  // Auth owns session persistence and token refresh entirely.  Adding one here
  // would duplicate that lifecycle and risk serving a stale identity.
  //
  // Only the in-flight OTP handshake is persisted, because Firebase does not
  // retain the verificationId across a process kill.

  /// Opaque OTP session ID returned by server after sending OTP.
  /// Stored to allow re-verification after app kill during OTP flow.
  static const String otpSessionId = 'otp_session_id';

  /// Phone number in E.164 format for the active OTP session.
  static const String otpPhoneE164 = 'otp_phone_e164';

  // ── Onboarding state (local, non-sensitive) ──────────────────────────────
  static const String onboardingCompleted = 'onboarding_completed';
}
