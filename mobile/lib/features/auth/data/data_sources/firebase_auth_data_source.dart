
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/entities/phone_verification_result.dart';
import '../../domain/phone_verification_coordinator.dart';

/// Firebase Auth wrapper.
///
/// All Firebase calls are contained here. Views, ViewModels, and use cases
/// must never import firebase_auth directly.
///
/// Phone OTP is Firebase-native (ADR-016).
///
/// LOCAL DEBUG TESTING:
/// When using the Firebase Auth emulator, entering 000000 retrieves the
/// actual OTP generated for the current verification session.
///
/// This does not bypass production Firebase authentication.
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

  static const String _emulatorHost =
      String.fromEnvironment('ORA_FIREBASE_EMULATOR_HOST');

  Stream<AuthUser?> get authStateChanges =>
      _auth.authStateChanges().map(_mapFirebaseUser);

  User? get currentFirebaseUser => _auth.currentUser;

  AuthUser? get currentUser => _mapFirebaseUser(_auth.currentUser);

  /// Starts Firebase phone verification.
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
          metadata: {
            'code': error.code,
            'op': 'request_otp',
          },
        );

        coordinator.onFailed(
          _failureMapper.fromFirebaseAuthException(error),
        );
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

  /// Verifies an OTP.
  ///
  /// For local debug builds using the Firebase Auth emulator, 000000
  /// is replaced with the actual emulator-generated verification code.
  ///
  /// For all other builds, normal Firebase verification is preserved.
  Future<UserCredential> verifyOtpCode({
    required String verificationId,
    required String otpCode,
  }) async {
    _logger.info(
      'OTP verify attempt',
      metadata: {'op': 'verify_otp'},
    );

    try {
      String smsCode = otpCode;

      if (kDebugMode &&
          _emulatorHost.isNotEmpty &&
          otpCode == '000000') {
        smsCode = await _getLocalEmulatorOtp(verificationId);
      }

      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );

      return await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      _logger.warning(
        'OTP verify failed',
        metadata: {
          'code': e.code,
          'op': 'verify_otp',
        },
      );

      throw _failureMapper.fromFirebaseAuthException(e);
    }
  }

  /// Fetches the real OTP for a verification session from the local
  /// Firebase Auth emulator.
  ///
  /// This endpoint is only intended for local development.
  Future<String> _getLocalEmulatorOtp(
    String verificationId,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);

    try {
      final projectId = _auth.app.options.projectId;

      final uri = Uri(
        scheme: 'http',
        host: _emulatorHost,
        port: 9099,
        path:
            '/emulator/v1/projects/$projectId/verificationCodes',
      );

      final request = await client.getUrl(uri);

      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );

      if (response.statusCode != HttpStatus.ok) {
        throw StateError(
          'Firebase Auth emulator returned HTTP '
          '${response.statusCode}.',
        );
      }

      final responseText = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 5));

      final decoded = jsonDecode(responseText);

      if (decoded is! Map<String, dynamic>) {
        throw StateError(
          'Invalid Firebase Auth emulator response.',
        );
      }

      final verificationCodes =
          decoded['verificationCodes'];

      if (verificationCodes is! List) {
        throw StateError(
          'No verification codes found in emulator.',
        );
      }

      for (final entry in verificationCodes.reversed) {
        if (entry is! Map) {
          continue;
        }

        final sessionInfo = entry['sessionInfo'];
        final code = entry['code'];

        if (sessionInfo == verificationId &&
            code is String &&
            code.isNotEmpty) {
          _logger.info(
            'Local emulator OTP resolved',
            metadata: {'op': 'local_emulator_verify'},
          );

          return code;
        }
      }

      throw StateError(
        'No matching OTP found for this verification session. '
        'Request a new OTP and try again.',
      );
    } on SocketException {
      throw StateError(
        'Cannot connect to Firebase Auth emulator at '
        '$_emulatorHost:9099. '
        'Check Wi-Fi, emulator binding, and firewall.',
      );
    } on TimeoutException {
      throw StateError(
        'Firebase Auth emulator connection timed out.',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<String?> getIdToken({
    bool forceRefresh = false,
  }) async {
    try {
      return await _auth.currentUser?.getIdToken(
        forceRefresh,
      );
    } on FirebaseAuthException catch (e) {
      throw _failureMapper.fromFirebaseAuthException(e);
    }
  }

  Future<void> signOut() async {
    _logger.info(
      'User signing out',
      metadata: {'op': 'logout'},
    );

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
