import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import '../../../../core/errors/failure_mapper.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/entities/otp_session.dart';

/// Firebase Auth wrapper.
///
/// All Firebase calls are contained here.  Views, ViewModels, and use cases
/// must never import firebase_auth directly — that would violate the MVVM
/// layer boundary enforced by mvvm_layer_test.dart.
///
/// Phone OTP is Firebase-native (ADR-016). Firebase owns send/verify/quotas.
/// Ora client UX: ~30s resend cooldown. Custom otpSessions Path B is deferred.
class FirebaseAuthDataSource {
  FirebaseAuthDataSource({
    required FailureMapper failureMapper,
    required AppLogger logger,
    FirebaseAuth? firebaseAuth,
  })  : _auth = firebaseAuth ?? FirebaseAuth.instance,
        _failureMapper = failureMapper,
        _logger = logger;

  final FirebaseAuth _auth;
  final FailureMapper _failureMapper;
  final AppLogger _logger;

  // ── Auth state ────────────────────────────────────────────────────────────

  Stream<AuthUser?> get authStateChanges =>
      _auth.authStateChanges().map(_mapFirebaseUser);

  User? get currentFirebaseUser => _auth.currentUser;

  AuthUser? get currentUser => _mapFirebaseUser(_auth.currentUser);

  // ── Phone OTP ─────────────────────────────────────────────────────────────

  /// Starts the Firebase phone verification flow.
  ///
  /// Firebase SDK returns a [verificationId] used to confirm the code.
  /// The returned [OtpSession] wraps this along with the phone for transport
  /// to the verify step.
  Future<OtpSession> startPhoneVerification({required String phoneE164}) async {
    final completer = Completer<String>();

    _logger.info(
      'OTP request initiated',
      metadata: {'op': 'request_otp'},
    );

    await _auth.verifyPhoneNumber(
      phoneNumber: phoneE164,
      verificationCompleted: (PhoneAuthCredential credential) {
        // Auto-verification (Android SMS retrieval) — complete immediately.
        // The verificationId is not needed for auto-verified credentials, but
        // we still need to complete our completer; use empty string as sentinel.
        if (!completer.isCompleted) completer.complete('auto');
      },
      verificationFailed: (FirebaseAuthException error) {
        _logger.warning(
          'OTP verification failed',
          metadata: {'code': error.code, 'op': 'request_otp'},
        );
        if (!completer.isCompleted) {
          completer.completeError(
            _failureMapper.fromFirebaseAuthException(error),
          );
        }
      },
      codeSent: (String verificationId, int? resendToken) {
        if (!completer.isCompleted) completer.complete(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        if (!completer.isCompleted) completer.complete(verificationId);
      },
      timeout: const Duration(seconds: 60),
    );

    final verificationId = await completer.future;

    return OtpSession(
      sessionId: verificationId,
      phoneE164: phoneE164,
      otpState: OtpState.otpSent,
    );
  }

  /// Verifies the user-entered [otpCode] against the Firebase session.
  Future<UserCredential> verifyOtpCode({
    required String verificationId,
    required String otpCode,
  }) async {
    _logger.info('OTP verify attempt', metadata: {'op': 'verify_otp'});
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: otpCode,
      );
      return await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      _logger.warning(
        'OTP verify failed',
        metadata: {'code': e.code, 'op': 'verify_otp'},
      );
      throw _failureMapper.fromFirebaseAuthException(e);
    }
  }

  // ── Token management ──────────────────────────────────────────────────────

  /// Returns a Firebase ID token.  Throws [SessionExpiredFailure] when the
  /// token cannot be refreshed.
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    try {
      return await _auth.currentUser?.getIdToken(forceRefresh);
    } on FirebaseAuthException catch (e) {
      throw _failureMapper.fromFirebaseAuthException(e);
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    _logger.info('User signing out', metadata: {'op': 'logout'});
    await _auth.signOut();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  AuthUser? _mapFirebaseUser(User? user) {
    if (user == null) return null;
    return AuthUser(
      uid: user.uid,
      phoneNumber: user.phoneNumber ?? '',
      isEmailVerified: user.emailVerified,
      displayName: user.displayName,
    );
  }
}
