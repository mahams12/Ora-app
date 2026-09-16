import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/entities/phone_verification_result.dart';
import '../../domain/phone_verification_coordinator.dart';

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

  Stream<AuthUser?> get authStateChanges =>
      _auth.authStateChanges().map(_mapFirebaseUser);

  User? get currentFirebaseUser => _auth.currentUser;

  AuthUser? get currentUser => _mapFirebaseUser(_auth.currentUser);

  /// Starts Firebase phone verification.
  ///
  /// Android instant/auto-retrieval signs in with the real
  /// [PhoneAuthCredential] — it never invents a verification ID.
  Future<PhoneVerificationResult> startPhoneVerification({
    required String phoneE164,
  }) async {
    _logger.info(
      'OTP request initiated',
      metadata: {'op': 'request_otp'},
    );

    final coordinator = PhoneVerificationCoordinator(
      phoneE164: phoneE164,
      signInWithCredential: (credential) async {
        final result = await _auth.signInWithCredential(
          credential as PhoneAuthCredential,
        );
        final user = _mapFirebaseUser(result.user);
        if (user == null) {
          throw const AppFailure.sessionExpired(
            message: 'Firebase credential produced no user.',
          );
        }
        _logger.info(
          'Phone auto-verification signed in',
          metadata: {'op': 'auto_verify'},
        );
        return user;
      },
    );

    await _auth.verifyPhoneNumber(
      phoneNumber: phoneE164,
      verificationCompleted: (PhoneAuthCredential credential) {
        unawaited(coordinator.onAutoVerified(credential));
      },
      verificationFailed: (FirebaseAuthException error) {
        _logger.warning(
          'OTP verification failed',
          metadata: {'code': error.code, 'op': 'request_otp'},
        );
        coordinator.onFailed(_failureMapper.fromFirebaseAuthException(error));
      },
      codeSent: (String verificationId, int? resendToken) {
        coordinator.onCodeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        coordinator.onAutoRetrievalTimeout(verificationId);
      },
      timeout: const Duration(seconds: 60),
    );

    return coordinator.future;
  }

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

  Future<String?> getIdToken({bool forceRefresh = false}) async {
    try {
      return await _auth.currentUser?.getIdToken(forceRefresh);
    } on FirebaseAuthException catch (e) {
      throw _failureMapper.fromFirebaseAuthException(e);
    }
  }

  Future<void> signOut() async {
    _logger.info('User signing out', metadata: {'op': 'logout'});
    await _auth.signOut();
  }

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
