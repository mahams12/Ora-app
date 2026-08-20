/// Client-side view of an active OTP session.
///
/// The server is authoritative for all limits, cooldowns, and expiry.
/// The client holds only the opaque identifiers returned by the server so
/// it can associate subsequent verify/resend calls with the same session.
///
/// Frozen limits (from Phase 1.6 contract, section 4):
///   maxAttempts         = 5
///   maxResends          = 3
///   resendCooldown      = 30 s
///   otpExpiration       = 5 min
///   lockDuration        = 15 min
class OtpSession {
  const OtpSession({
    required this.sessionId,
    required this.phoneE164,
    required this.otpState,
    this.cooldownUntil,
    this.lockedUntil,
    this.attemptCount = 0,
    this.resendCount = 0,
  });

  /// Opaque server-assigned session identifier.
  final String sessionId;

  /// Phone number in E.164 format this session belongs to.
  final String phoneE164;

  /// Current OTP state as reported by server.
  final OtpState otpState;

  /// When the next resend is permitted (server-derived).  Null = no cooldown.
  final DateTime? cooldownUntil;

  /// When the session lock expires.  Null = not locked.
  final DateTime? lockedUntil;

  /// Client-side attempt counter (informational; server is authoritative).
  final int attemptCount;

  /// Client-side resend counter (informational; server is authoritative).
  final int resendCount;

  bool get isLocked =>
      lockedUntil != null && lockedUntil!.isAfter(DateTime.now());

  bool get isCoolingDown =>
      cooldownUntil != null && cooldownUntil!.isAfter(DateTime.now());

  Duration get cooldownRemaining {
    if (cooldownUntil == null) return Duration.zero;
    final remaining = cooldownUntil!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  OtpSession copyWith({
    OtpState? otpState,
    DateTime? cooldownUntil,
    DateTime? lockedUntil,
    int? attemptCount,
    int? resendCount,
  }) =>
      OtpSession(
        sessionId: sessionId,
        phoneE164: phoneE164,
        otpState: otpState ?? this.otpState,
        cooldownUntil: cooldownUntil ?? this.cooldownUntil,
        lockedUntil: lockedUntil ?? this.lockedUntil,
        attemptCount: attemptCount ?? this.attemptCount,
        resendCount: resendCount ?? this.resendCount,
      );
}

/// Mirrors the server OTP session state machine (Phase 1.6 contract, section 4).
enum OtpState {
  /// OTP request accepted; SMS being dispatched.
  otpRequested,

  /// SMS delivered to device; waiting for user input.
  otpSent,

  /// User code verified; Firebase custom token issued.
  otpVerified,

  /// OTP window elapsed; user must resend.
  otpExpired,

  /// Code was wrong; retry permitted if attempts remain.
  otpInvalid,

  /// Too many invalid attempts; session locked for 15 min.
  otpLocked,

  /// Resend requested before cooldown elapsed.
  otpCooldown,
}
