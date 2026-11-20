import 'dart:async';

import '../core/errors/app_failure.dart';
import '../features/auth/domain/entities/auth_user.dart';
import '../features/auth/domain/entities/otp_session.dart';
import '../features/auth/domain/entities/phone_verification_result.dart';
import '../features/auth/domain/entities/user_profile.dart';
import '../features/auth/domain/repositories/auth_repository.dart';
import 'demo_session_store.dart';

/// DEMO/REVIEW BUILD ONLY — never referenced by `lib/main.dart`.
///
/// Fully local [AuthRepository]: any phone number signs in with OTP `000000`,
/// sessions persist in secure storage, and partner applications resolve as
/// APPROVED instantly so every dashboard is explorable without a backend.
/// The production `AuthRepositoryImpl` (Firebase OTP + `/v1/auth/*`) is
/// untouched and remains the only implementation the real entrypoint sees.
class DemoAuthRepository implements AuthRepository {
  DemoAuthRepository(this._store);

  /// The only code the demo build accepts — review builds only.
  static const demoOtp = '000000';

  final DemoSessionStore _store;
  final _authChanges = StreamController<AuthUser?>.broadcast();
  int _otpAttempts = 0;

  @override
  Stream<AuthUser?> get authStateChanges => _authChanges.stream;

  @override
  Future<AuthUser?> getCurrentUser() async => _store.authUser;

  @override
  Future<PhoneVerificationResult> requestOtp({
    required String phoneE164,
  }) async {
    _otpAttempts = 0;
    return PhoneCodeSent(
      OtpSession(
        sessionId: 'demo-otp-${DateTime.now().millisecondsSinceEpoch}',
        phoneE164: phoneE164,
        otpState: OtpState.otpSent,
      ),
    );
  }

  @override
  Future<AuthUser> verifyOtp({
    required OtpSession session,
    required String otpCode,
  }) async {
    if (otpCode != demoOtp) {
      _otpAttempts += 1;
      if (_otpAttempts >= 5) {
        throw const AppFailure.tooManyAttempts(
          message: 'Too many wrong codes. Request a new OTP.',
        );
      }
      throw const AppFailure.invalidOtp(
        message: 'Wrong code — the demo OTP is 000000.',
      );
    }

    // Returning user on this install keeps their demo roles/listings; a new
    // phone starts as a fresh passenger (onboarding → home).
    final existing = await _store.load();
    final uid = DemoSessionStore.uidForPhone(session.phoneE164);
    if (existing == null || existing.uid != uid) {
      await _store.createForPhone(session.phoneE164);
    }
    final user = _store.authUser!;
    _authChanges.add(user);
    return user;
  }

  @override
  Future<PhoneVerificationResult> resendOtp({
    required OtpSession session,
  }) async {
    _otpAttempts = 0;
    return PhoneCodeSent(
      session.copyWith(
        otpState: OtpState.otpSent,
        resendCount: session.resendCount + 1,
      ),
    );
  }

  @override
  Future<AuthUser?> restoreSession() async {
    final profile = await _store.load();
    if (profile == null) return null;
    final user = _store.authUser!;
    _authChanges.add(user);
    return user;
  }

  @override
  Future<String> refreshToken() async => 'demo-token';

  @override
  Future<UserProfile> getUserProfile({required String uid}) async {
    final profile = await _store.load();
    if (profile == null) throw const AppFailure.unauthorized();
    return profile;
  }

  @override
  Future<void> registerUser({required String uid}) async {
    // Idempotent no-op — the demo store is the user document.
    await _store.load();
  }

  @override
  Future<UserProfile> updateDisplayName({
    required String displayName,
  }) => _store.update(displayName: displayName, markComplete: true);

  @override
  Future<UserProfile> updateProfile({
    required String displayName,
    String? avatarData,
    bool clearAvatar = false,
  }) => _store.update(
    displayName: displayName,
    avatarData: avatarData,
    clearAvatar: clearAvatar,
    markComplete: true,
  );

  @override
  Future<UserProfile> switchMode({required String mode}) async {
    final profile = await _store.load();
    if (profile == null) throw const AppFailure.unauthorized();
    if (mode == 'driver' && !profile.isApprovedDriver) {
      // Mirrors the production gate so the UI still routes to registration.
      throw const AppFailure.conflict(code: 'DRIVER_ONBOARDING_REQUIRED');
    }
    return _store.setMode(mode);
  }

  @override
  Future<UserProfile> submitVendorApplication({
    required String type,
    Map<String, dynamic>? details,
  }) {
    // DEMO-ONLY auto-approval. Production keeps 'pending' until admin review.
    return _store.approveVendor(type);
  }

  @override
  Future<Map<String, dynamic>> submitDriverOnboarding({
    required String vehicleType,
    String? vehicleModel,
    String? plateNumber,
    String? homeCity,
  }) async {
    await _store.approveDriver();
    return {'driverStatus': 'approved'};
  }

  @override
  Future<void> logout() async {
    await _store.clear();
    _authChanges.add(null);
  }
}
