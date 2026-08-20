import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_failure.freezed.dart';

@freezed
sealed class AppFailure with _$AppFailure {
  const AppFailure._();

  const factory AppFailure.network({
    String? message,
    int? statusCode,
    String? code,
  }) = NetworkFailure;

  const factory AppFailure.timeout({String? message}) = TimeoutFailure;

  const factory AppFailure.unauthorized({String? message}) =
      UnauthorizedFailure;

  const factory AppFailure.forbidden({String? message}) = ForbiddenFailure;

  const factory AppFailure.notFound({String? message}) = NotFoundFailure;

  const factory AppFailure.validation({
    String? message,
    Map<String, List<String>>? fieldErrors,
  }) = ValidationFailure;

  const factory AppFailure.conflict({String? message, String? code}) =
      ConflictFailure;

  const factory AppFailure.server({String? message, int? statusCode}) =
      ServerFailure;

  const factory AppFailure.unknown({
    String? message,
    Object? cause,
  }) = UnknownFailure;

  // ── Auth-specific failures ────────────────────────────────────────────────

  /// The phone number supplied is not a valid E.164 number.
  const factory AppFailure.invalidPhone({String? message}) = InvalidPhoneFailure;

  /// OTP code entered by user is wrong.
  const factory AppFailure.invalidOtp({String? message}) = InvalidOtpFailure;

  /// OTP code has expired on the server.
  const factory AppFailure.otpExpired({String? message}) = OtpExpiredFailure;

  /// Server rejected: too many incorrect attempts; session locked.
  const factory AppFailure.tooManyAttempts({String? message, Duration? lockDuration}) =
      TooManyAttemptsFailure;

  /// Resend blocked: cooldown window is still active.
  const factory AppFailure.otpCooldown({String? message, Duration? remaining}) =
      OtpCooldownFailure;

  /// Account has been disabled/suspended by admin.
  const factory AppFailure.accountDisabled({String? message}) = AccountDisabledFailure;

  /// Firebase ID-token refresh failed; session must be cleared.
  const factory AppFailure.sessionExpired({String? message}) = SessionExpiredFailure;

  /// Token refresh HTTP call failed (network/server); retryable.
  const factory AppFailure.refreshFailed({String? message}) = RefreshFailedFailure;

  String get userMessage => switch (this) {
        NetworkFailure(:final message) =>
          message ?? 'Network error. Check your connection.',
        TimeoutFailure(:final message) =>
          message ?? 'Request timed out. Please try again.',
        UnauthorizedFailure(:final message) =>
          message ?? 'Please sign in again.',
        ForbiddenFailure(:final message) =>
          message ?? 'You do not have permission for this action.',
        NotFoundFailure(:final message) => message ?? 'Resource not found.',
        ValidationFailure(:final message) =>
          message ?? 'Please check your input.',
        ConflictFailure(:final message) =>
          message ?? 'This action conflicts with the current state.',
        ServerFailure(:final message) =>
          message ?? 'Something went wrong. Please try again.',
        UnknownFailure(:final message) =>
          message ?? 'An unexpected error occurred.',
        InvalidPhoneFailure(:final message) =>
          message ?? 'Please enter a valid phone number.',
        InvalidOtpFailure(:final message) =>
          message ?? 'Incorrect code. Please try again.',
        OtpExpiredFailure(:final message) =>
          message ?? 'The code has expired. Please request a new one.',
        TooManyAttemptsFailure(:final message) =>
          message ?? 'Too many attempts. Please wait and try again.',
        OtpCooldownFailure(:final message, :final remaining) => message ??
            (remaining != null
                ? 'Please wait ${remaining.inSeconds}s before resending.'
                : 'Please wait before requesting another code.'),
        AccountDisabledFailure(:final message) =>
          message ?? 'Your account has been disabled. Contact support.',
        SessionExpiredFailure(:final message) =>
          message ?? 'Your session has expired. Please sign in again.',
        RefreshFailedFailure(:final message) =>
          message ?? 'Could not refresh your session. Please sign in again.',
      };
}
