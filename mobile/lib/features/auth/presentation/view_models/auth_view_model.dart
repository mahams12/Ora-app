import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/entities/otp_session.dart';
import '../../domain/entities/phone_verification_result.dart';
import '../../domain/use_cases/logout_use_case.dart';
import '../../domain/use_cases/request_otp_use_case.dart';
import '../../domain/use_cases/resend_otp_use_case.dart';
import '../../domain/use_cases/restore_session_use_case.dart';
import '../../domain/use_cases/verify_otp_use_case.dart';
import 'auth_view_state.dart';

/// ViewModel for the OTP sign-in flow.
///
/// Enforces the ADR-016 OTP client-side cooldown display:
///   cooldown  = 30 s countdown (UX only; Firebase owns OTP quotas)
///   lock / expiry = server-authoritative; we surface the error message.
///
/// All OTP validity decisions are server-authoritative; this ViewModel
/// only manages UI states and cooldown display timers.
class AuthViewModel extends Notifier<AuthFlowState> {
  late final RequestOtpUseCase _requestOtp;
  late final VerifyOtpUseCase _verifyOtp;
  late final ResendOtpUseCase _resendOtp;
  late final RestoreSessionUseCase _restoreSession;
  late final LogoutUseCase _logout;
  late final AppLogger _logger;

  // Countdown timer for resend cooldown display.
  Timer? _cooldownTimer;

  @override
  AuthFlowState build() {
    _requestOtp = ref.read(requestOtpUseCaseProvider);
    _verifyOtp = ref.read(verifyOtpUseCaseProvider);
    _resendOtp = ref.read(resendOtpUseCaseProvider);
    _restoreSession = ref.read(restoreSessionUseCaseProvider);
    _logout = ref.read(logoutUseCaseProvider);
    _logger = ref.read(appLoggerProvider);

    ref.onDispose(() => _cooldownTimer?.cancel());

    return const AuthFlowIdle();
  }

  // ── Phone entry ───────────────────────────────────────────────────────────

  void showPhoneEntry() {
    state = const AuthFlowPhoneEntry();
  }

  // ── OTP request ───────────────────────────────────────────────────────────

  Future<void> requestOtp({required String phoneE164}) async {
    state = const AuthFlowRequestingOtp();
    _logger.info('Requesting OTP', metadata: {'op': 'request_otp'});
    try {
      final result = await _requestOtp(phoneE164: phoneE164);
      _applyVerificationResult(result);
    } catch (e) {
      _handleError(e, fallback: const AuthFlowPhoneEntry());
    }
  }

  // ── OTP verify ────────────────────────────────────────────────────────────

  Future<void> verifyOtp({required String code}) async {
    final current = state;
    if (current is! AuthFlowOtpSent) return;

    final session = current.session;
    state = AuthFlowVerifyingOtp(session: session);
    _logger.info('Verifying OTP', metadata: {'op': 'verify_otp'});

    try {
      final user = await _verifyOtp(session: session, otpCode: code);
      state = AuthFlowAuthenticated(user: user);
    } catch (e) {
      _handleError(e, fallback: AuthFlowOtpSent(session: session));
    }
  }

  // ── OTP resend ────────────────────────────────────────────────────────────

  Future<void> resendOtp() async {
    final current = state;
    if (current is! AuthFlowOtpSent) return;

    final session = current.session;
    if (session.isCoolingDown) {
      state = AuthFlowResendCooldown(
        session: session,
        remaining: session.cooldownRemaining,
      );
      return;
    }

    state = AuthFlowResendingOtp(session: session);
    _logger.info('Resending OTP', metadata: {'op': 'resend_otp'});

    try {
      final result = await _resendOtp(session: session);
      switch (result) {
        case PhoneCodeSent(:final session):
          _startCooldownTimer(session);
        case PhoneAutoSignedIn(:final user):
          state = AuthFlowAuthenticated(user: user);
      }
    } catch (e) {
      _handleError(e, fallback: AuthFlowOtpSent(session: session));
    }
  }

  // ── Session management ────────────────────────────────────────────────────

  Future<AuthUser?> restoreSession() async {
    _logger.info('Restoring session', metadata: {'op': 'restore_session'});
    try {
      return await _restoreSession();
    } catch (_) {
      return null;
    }
  }

  Future<void> logout() async {
    _logger.info('Logging out', metadata: {'op': 'logout'});
    _cooldownTimer?.cancel();
    await _logout();
    state = const AuthFlowPhoneEntry();
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  void _applyVerificationResult(PhoneVerificationResult result) {
    switch (result) {
      case PhoneCodeSent(:final session):
        state = AuthFlowOtpSent(session: session);
      case PhoneAutoSignedIn(:final user):
        state = AuthFlowAuthenticated(user: user);
    }
  }

  /// Starts the 30-second countdown for the resend button UX.
  void _startCooldownTimer(OtpSession session) {
    _cooldownTimer?.cancel();
    // ADR-016: client resend UX cooldown = 30 s
    final cooldownEnd = DateTime.now().add(const Duration(seconds: 30));
    final updatedSession = session.copyWith(cooldownUntil: cooldownEnd);
    state = AuthFlowOtpSent(session: updatedSession);

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = cooldownEnd.difference(DateTime.now());
      if (remaining.isNegative || remaining.inSeconds <= 0) {
        timer.cancel();
        final current = state;
        if (current is AuthFlowOtpSent) {
          state = AuthFlowOtpSent(
            session: current.session.copyWith(cooldownUntil: null),
          );
        }
        return;
      }
      final current = state;
      if (current is AuthFlowOtpSent || current is AuthFlowResendCooldown) {
        final s = current is AuthFlowOtpSent
            ? current.session
            : (current as AuthFlowResendCooldown).session;
        state = AuthFlowResendCooldown(session: s, remaining: remaining);
      }
    });
  }

  void _handleError(Object error, {required AuthFlowState fallback}) {
    final message = error is AppFailure
        ? error.userMessage
        : 'An unexpected error occurred. Please try again.';

    _logger.warning(
      'Auth flow error',
      metadata: {'type': error.runtimeType.toString()},
    );
    state = AuthFlowError(message: message, previousState: fallback);
  }
}
