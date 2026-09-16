import 'package:firebase_auth/firebase_auth.dart' show User;

import '../../../../core/errors/app_failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../../../core/storage/storage_keys.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/entities/otp_session.dart';
import '../../domain/entities/phone_verification_result.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/auth_repository.dart';
import '../data_sources/auth_remote_data_source.dart';
import '../data_sources/firebase_auth_data_source.dart';

/// Concrete implementation of [AuthRepository].
class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl({
    required FirebaseAuthDataSource firebaseDataSource,
    required AuthRemoteDataSource remoteDataSource,
    required SecureStorage secureStorage,
    required ApiClient apiClient,
    required AppLogger logger,
  })  : _firebase = firebaseDataSource,
        _remote = remoteDataSource,
        _secureStorage = secureStorage,
        _apiClient = apiClient,
        _logger = logger;

  final FirebaseAuthDataSource _firebase;
  final AuthRemoteDataSource _remote;
  final SecureStorage _secureStorage;
  final ApiClient _apiClient;
  final AppLogger _logger;

  @override
  Stream<AuthUser?> get authStateChanges => _firebase.authStateChanges;

  @override
  Future<AuthUser?> getCurrentUser() async => _firebase.currentUser;

  @override
  Future<PhoneVerificationResult> requestOtp({
    required String phoneE164,
  }) async {
    final result = await _firebase.startPhoneVerification(
      phoneE164: phoneE164,
    );
    switch (result) {
      case PhoneCodeSent(:final session):
        await _secureStorage.write(
          key: StorageKeys.otpSessionId,
          value: session.sessionId,
        );
        await _secureStorage.write(
          key: StorageKeys.otpPhoneE164,
          value: phoneE164,
        );
        _logger.info('OTP session stored', metadata: {'op': 'request_otp'});
      case PhoneAutoSignedIn():
        await _secureStorage.delete(key: StorageKeys.otpSessionId);
        await _secureStorage.delete(key: StorageKeys.otpPhoneE164);
        _logger.info(
          'Phone auto-verification completed',
          metadata: {'op': 'auto_verify'},
        );
    }
    return result;
  }

  @override
  Future<AuthUser> verifyOtp({
    required OtpSession session,
    required String otpCode,
  }) async {
    final credential = await _firebase.verifyOtpCode(
      verificationId: session.sessionId,
      otpCode: otpCode,
    );

    final firebaseUser = credential.user;
    if (firebaseUser == null) {
      throw const AppFailure.sessionExpired(
        message: 'Firebase credential produced no user.',
      );
    }

    await _secureStorage.delete(key: StorageKeys.otpSessionId);
    await _secureStorage.delete(key: StorageKeys.otpPhoneE164);

    _logger.info('OTP verified; user signed in', metadata: {
      'op': 'verify_otp',
      'isNewUser': credential.additionalUserInfo?.isNewUser,
    });

    return _toAuthUser(firebaseUser);
  }

  @override
  Future<PhoneVerificationResult> resendOtp({required OtpSession session}) =>
      requestOtp(phoneE164: session.phoneE164);

  @override
  Future<AuthUser?> restoreSession() async {
    final user = _firebase.currentFirebaseUser;
    if (user == null) {
      _logger.info('No active session found',
          metadata: {'op': 'restore_session'});
      return null;
    }

    try {
      await user.getIdToken(true);
      _logger.info('Session restored', metadata: {'op': 'restore_session'});
      return _toAuthUser(user);
    } catch (e) {
      _logger.warning(
        'Session restore: token refresh failed; clearing session',
        metadata: {'op': 'restore_session', 'error': e.toString()},
      );
      await logout();
      return null;
    }
  }

  @override
  Future<String> refreshToken() async {
    final token = await _firebase.getIdToken(forceRefresh: true);
    if (token == null) {
      throw const AppFailure.sessionExpired();
    }
    return token;
  }

  @override
  Future<UserProfile> getUserProfile({required String uid}) async {
    final context = _apiClient.newContext(operationId: 'get_me');
    final model = await _remote.getMe(context: context);
    return model.toDomain();
  }

  @override
  Future<void> registerUser({required String uid}) => _registerUser(uid: uid);

  @override
  Future<UserProfile> updateDisplayName({required String displayName}) async {
    final context = _apiClient.newContext(operationId: 'update_profile');
    final model = await _remote.updateProfile(
      displayName: displayName,
      context: context,
    );
    return model.toDomain();
  }

  @override
  Future<void> logout() async {
    await _firebase.signOut();
    await _secureStorage.deleteAll();
    _logger.info('User logged out; secure storage cleared',
        metadata: {'op': 'logout'});
  }

  Future<void> _registerUser({required String uid}) async {
    final context = _apiClient.newContext(
      operationId: 'register_user',
      idempotencyKey: 'register_$uid',
    );
    await _remote.registerUser(uid: uid, context: context);
    _logger.info('User registered', metadata: {'op': 'register_user'});
  }

  AuthUser _toAuthUser(User user) => AuthUser(
        uid: user.uid,
        phoneNumber: user.phoneNumber ?? '',
        isEmailVerified: user.emailVerified,
        displayName: user.displayName,
      );
}
