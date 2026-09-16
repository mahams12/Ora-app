import 'dart:async';

import 'entities/auth_user.dart';
import 'entities/otp_session.dart';
import 'entities/phone_verification_result.dart';

/// Coordinates Firebase `verifyPhoneNumber` callbacks without inventing IDs.
///
/// - [onCodeSent] / timeout complete with [PhoneCodeSent].
/// - [onAutoVerified] signs in with the real credential, then completes with
///   [PhoneAutoSignedIn] if the request is still pending.
/// - A late auto-retrieval after [onCodeSent] still signs in (does not
///   complete the future a second time).
class PhoneVerificationCoordinator {
  PhoneVerificationCoordinator({
    required this.phoneE164,
    required this.signInWithCredential,
  });

  final String phoneE164;
  final Future<AuthUser> Function(Object credential) signInWithCredential;

  final Completer<PhoneVerificationResult> _completer =
      Completer<PhoneVerificationResult>();

  Future<PhoneVerificationResult> get future => _completer.future;

  bool get isCompleted => _completer.isCompleted;

  Future<void> onAutoVerified(Object credential) async {
    try {
      final user = await signInWithCredential(credential);
      if (!_completer.isCompleted) {
        _completer.complete(PhoneAutoSignedIn(user));
      }
    } catch (error, stackTrace) {
      if (!_completer.isCompleted) {
        _completer.completeError(error, stackTrace);
      } else {
        // Late auto-verify after the user already has a session id: the sign-in
        // failed; AuthStateNotifier / OTP screen remain responsible.
      }
    }
  }

  void onCodeSent(String verificationId) {
    if (_completer.isCompleted) {
      return;
    }
    _completer.complete(
      PhoneCodeSent(
        OtpSession(
          sessionId: verificationId,
          phoneE164: phoneE164,
          otpState: OtpState.otpSent,
        ),
      ),
    );
  }

  void onFailed(Object error) {
    if (!_completer.isCompleted) {
      _completer.completeError(error);
    }
  }

  void onAutoRetrievalTimeout(String verificationId) {
    onCodeSent(verificationId);
  }
}
