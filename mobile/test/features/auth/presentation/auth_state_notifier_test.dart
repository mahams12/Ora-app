import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/core/errors/app_failure.dart';
import 'package:ora/core/logging/app_logger.dart';
import 'package:ora/core/logging/log_record.dart';
import 'package:ora/features/auth/domain/entities/auth_user.dart';
import 'package:ora/features/auth/domain/entities/otp_session.dart';
import 'package:ora/features/auth/domain/entities/phone_verification_result.dart';
import 'package:ora/features/auth/domain/entities/user_profile.dart';
import 'package:ora/features/auth/domain/repositories/auth_repository.dart';
import 'package:ora/features/auth/domain/use_cases/resolve_auth_profile_use_case.dart';
import 'package:ora/features/auth/domain/use_cases/restore_session_use_case.dart';
import 'package:ora/features/auth/presentation/view_models/auth_view_state.dart';

class _FakeAuthRepository implements AuthRepository {
  final StreamController<AuthUser?> controller =
      StreamController<AuthUser?>.broadcast();

  AuthUser? current;
  UserProfile? profile;
  Object? profileError;
  int registerCalls = 0;
  int logoutCalls = 0;

  @override
  Stream<AuthUser?> get authStateChanges => controller.stream;

  @override
  Future<AuthUser?> getCurrentUser() async => current;

  @override
  Future<PhoneVerificationResult> requestOtp({required String phoneE164}) =>
      throw UnimplementedError();

  @override
  Future<AuthUser> verifyOtp({
    required OtpSession session,
    required String otpCode,
  }) =>
      throw UnimplementedError();

  @override
  Future<PhoneVerificationResult> resendOtp({required OtpSession session}) =>
      throw UnimplementedError();

  @override
  Future<AuthUser?> restoreSession() => throw UnimplementedError();

  @override
  Future<String> refreshToken() => throw UnimplementedError();

  @override
  Future<UserProfile> getUserProfile({required String uid}) async {
    if (profileError != null) {
      throw profileError!;
    }
    return profile!;
  }

  @override
  Future<void> registerUser({required String uid}) async {
    registerCalls++;
  }

  @override
  Future<UserProfile> updateDisplayName({required String displayName}) async {
    return profile!;
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
    current = null;
  }
}

class MockRestoreSessionUseCase extends Mock implements RestoreSessionUseCase {}

class _SilentLogger extends AppLogger {
  @override
  void log(LogRecord record) {}
}

void main() {
  const user = AuthUser(
    uid: 'uid-1',
    phoneNumber: '+923001234567',
    isEmailVerified: false,
  );

  const incompleteProfile = UserProfile(
    uid: 'uid-1',
    phoneNumber: '+923001234567',
    profileComplete: false,
  );

  const completeProfile = UserProfile(
    uid: 'uid-1',
    phoneNumber: '+923001234567',
    displayName: 'Ada',
    profileComplete: true,
  );

  late _FakeAuthRepository repository;
  late MockRestoreSessionUseCase restoreSession;

  setUp(() {
    repository = _FakeAuthRepository();
    restoreSession = MockRestoreSessionUseCase();
  });

  tearDown(() => repository.controller.close());

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        restoreSessionUseCaseProvider.overrideWithValue(restoreSession),
        resolveAuthProfileUseCaseProvider.overrideWithValue(
          ResolveAuthProfileUseCase(repository),
        ),
        appLoggerProvider.overrideWithValue(_SilentLogger()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  group('AuthStateNotifier startup', () {
    test('starts at unknown so the guard holds the user on splash', () {
      when(() => restoreSession()).thenAnswer((_) async => null);

      final container = makeContainer();

      expect(container.read(authStateNotifierProvider), AuthStatus.unknown);
    });

    test('unknown → unauthenticated when there is no session to restore',
        () async {
      when(() => restoreSession()).thenAnswer((_) async => null);

      final container = makeContainer();
      container.read(authStateNotifierProvider);
      await settle();

      expect(
        container.read(authStateNotifierProvider),
        AuthStatus.unauthenticated,
      );
    });

    test(
        'unknown → onboardingRequired when session restores with incomplete profile',
        () async {
      when(() => restoreSession()).thenAnswer((_) async => user);
      repository.profile = incompleteProfile;

      final container = makeContainer();
      container.read(authStateNotifierProvider);
      repository.controller.add(user);
      await settle();

      expect(
        container.read(authStateNotifierProvider),
        AuthStatus.onboardingRequired,
      );
      expect(repository.registerCalls, greaterThan(0));
    });

    test(
        'unknown → authenticatedReady when session restores with complete profile',
        () async {
      when(() => restoreSession()).thenAnswer((_) async => user);
      repository.profile = completeProfile;

      final container = makeContainer();
      container.read(authStateNotifierProvider);
      repository.controller.add(user);
      await settle();

      expect(
        container.read(authStateNotifierProvider),
        AuthStatus.authenticatedReady,
      );
    });

    test('backend failure leaves session at authenticated (fail closed)',
        () async {
      when(() => restoreSession()).thenAnswer((_) async => user);
      repository.profileError = const AppFailure.network(message: 'down');

      final container = makeContainer();
      container.read(authStateNotifierProvider);
      repository.controller.add(user);
      await settle();

      expect(
        container.read(authStateNotifierProvider),
        AuthStatus.authenticated,
      );
    });

    test('a restore failure does not leave the guard stuck on unknown',
        () async {
      when(() => restoreSession()).thenAnswer((_) async => null);

      final container = makeContainer();
      container.read(authStateNotifierProvider);
      await settle();

      expect(
        container.read(authStateNotifierProvider),
        isNot(AuthStatus.unknown),
      );
    });

    test('a stream error resolves to unauthenticated rather than unknown',
        () async {
      when(() => restoreSession()).thenAnswer((_) async => user);

      final container = makeContainer();
      container.read(authStateNotifierProvider);
      repository.controller.addError(Exception('firebase unavailable'));
      await settle();

      expect(
        container.read(authStateNotifierProvider),
        AuthStatus.unauthenticated,
      );
    });
  });

  group('AuthStateNotifier transitions', () {
    test('sign-out on the stream drops back to unauthenticated', () async {
      when(() => restoreSession()).thenAnswer((_) async => user);
      repository.profile = completeProfile;

      final container = makeContainer();
      container.read(authStateNotifierProvider);
      repository.controller.add(user);
      await settle();
      expect(
        container.read(authStateNotifierProvider),
        AuthStatus.authenticatedReady,
      );

      repository.controller.add(null);
      await settle();

      expect(
        container.read(authStateNotifierProvider),
        AuthStatus.unauthenticated,
      );
    });

    test('banned account clears the Firebase session', () async {
      when(() => restoreSession()).thenAnswer((_) async => user);
      repository.current = user;
      repository.profile = const UserProfile(
        uid: 'uid-1',
        phoneNumber: '+923001234567',
        banned: true,
        profileComplete: false,
      );

      final container = makeContainer();
      container.read(authStateNotifierProvider);
      repository.controller.add(user);
      await settle();

      expect(repository.logoutCalls, 1);
      expect(
        container.read(authStateNotifierProvider),
        AuthStatus.unauthenticated,
      );
    });

    test('setOnboardingRequired moves to onboardingRequired', () async {
      when(() => restoreSession()).thenAnswer((_) async => null);

      final container = makeContainer();
      container.read(authStateNotifierProvider);
      await settle();

      container
          .read(authStateNotifierProvider.notifier)
          .setOnboardingRequired();

      expect(
        container.read(authStateNotifierProvider),
        AuthStatus.onboardingRequired,
      );
    });

    test('setAuthenticatedReady moves to authenticatedReady', () async {
      when(() => restoreSession()).thenAnswer((_) async => null);

      final container = makeContainer();
      container.read(authStateNotifierProvider);
      await settle();

      container
          .read(authStateNotifierProvider.notifier)
          .setAuthenticatedReady();

      expect(
        container.read(authStateNotifierProvider),
        AuthStatus.authenticatedReady,
      );
    });

    test('clearSession moves to unauthenticated', () async {
      when(() => restoreSession()).thenAnswer((_) async => null);

      final container = makeContainer();
      container.read(authStateNotifierProvider);
      await settle();

      container.read(authStateNotifierProvider.notifier).clearSession();

      expect(
        container.read(authStateNotifierProvider),
        AuthStatus.unauthenticated,
      );
    });

    test('refreshCanonicalProfile uses /me without a second register',
        () async {
      when(() => restoreSession()).thenAnswer((_) async => user);
      repository.current = user;
      repository.profile = incompleteProfile;

      final container = makeContainer();
      container.read(authStateNotifierProvider);
      repository.controller.add(user);
      await settle();
      final registersAfterBootstrap = repository.registerCalls;

      repository.profile = completeProfile;
      await container
          .read(authStateNotifierProvider.notifier)
          .refreshCanonicalProfile();

      expect(
        container.read(authStateNotifierProvider),
        AuthStatus.authenticatedReady,
      );
      expect(repository.registerCalls, registersAfterBootstrap);
    });

    test('refreshCanonicalProfile failure stays on onboarding', () async {
      when(() => restoreSession()).thenAnswer((_) async => user);
      repository.current = user;
      repository.profile = incompleteProfile;

      final container = makeContainer();
      container.read(authStateNotifierProvider);
      repository.controller.add(user);
      await settle();

      repository.profileError = const AppFailure.timeout();
      await expectLater(
        container.read(authStateNotifierProvider.notifier).refreshCanonicalProfile(),
        throwsA(isA<TimeoutFailure>()),
      );
      await settle();
      expect(
        container.read(authStateNotifierProvider),
        AuthStatus.onboardingRequired,
      );
    });
  });
}
