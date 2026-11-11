import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ora/core/errors/app_failure.dart';
import 'package:ora/features/auth/domain/entities/auth_user.dart';
import 'package:ora/features/auth/domain/entities/otp_session.dart';
import 'package:ora/features/auth/domain/entities/phone_verification_result.dart';
import 'package:ora/features/auth/domain/use_cases/logout_use_case.dart';
import 'package:ora/features/auth/domain/use_cases/request_otp_use_case.dart';
import 'package:ora/features/auth/domain/use_cases/resend_otp_use_case.dart';
import 'package:ora/features/auth/domain/use_cases/restore_session_use_case.dart';
import 'package:ora/features/auth/domain/use_cases/verify_otp_use_case.dart';
import 'package:ora/features/auth/presentation/view_models/auth_view_state.dart';
import 'package:ora/app/di/providers.dart';

// Mock use cases
class MockRequestOtpUseCase extends Mock implements RequestOtpUseCase {}

class MockVerifyOtpUseCase extends Mock implements VerifyOtpUseCase {}

class MockResendOtpUseCase extends Mock implements ResendOtpUseCase {}

class MockRestoreSessionUseCase extends Mock implements RestoreSessionUseCase {}

class MockLogoutUseCase extends Mock implements LogoutUseCase {}

// Fake types for mocktail registerFallbackValue
class FakeOtpSession extends Fake implements OtpSession {}

void main() {
  late MockRequestOtpUseCase requestOtp;
  late MockVerifyOtpUseCase verifyOtp;
  late MockResendOtpUseCase resendOtp;
  late MockRestoreSessionUseCase restoreSession;
  late MockLogoutUseCase logout;

  setUpAll(() {
    registerFallbackValue(FakeOtpSession());
  });

  setUp(() {
    requestOtp = MockRequestOtpUseCase();
    verifyOtp = MockVerifyOtpUseCase();
    resendOtp = MockResendOtpUseCase();
    restoreSession = MockRestoreSessionUseCase();
    logout = MockLogoutUseCase();
  });

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [
        requestOtpUseCaseProvider.overrideWithValue(requestOtp),
        verifyOtpUseCaseProvider.overrideWithValue(verifyOtp),
        resendOtpUseCaseProvider.overrideWithValue(resendOtp),
        restoreSessionUseCaseProvider.overrideWithValue(restoreSession),
        logoutUseCaseProvider.overrideWithValue(logout),
      ],
    );
  }

  group('AuthViewModel.requestOtp', () {
    test('transitions to AuthFlowOtpSent on success', () async {
      const session = OtpSession(
        sessionId: 'vid-1',
        phoneE164: '+923001234567',
        otpState: OtpState.otpSent,
      );
      when(() => requestOtp(phoneE164: any(named: 'phoneE164')))
          .thenAnswer((_) async => const PhoneCodeSent(session));

      final container = makeContainer();
      addTearDown(container.dispose);
      final vm = container.read(authViewModelProvider.notifier);

      await vm.requestOtp(phoneE164: '+923001234567');

      final state = container.read(authViewModelProvider);
      expect(state, isA<AuthFlowOtpSent>());
      expect((state as AuthFlowOtpSent).session.sessionId, 'vid-1');
    });

    test('transitions to AuthFlowAuthenticated on Android auto-sign-in',
        () async {
      const user = AuthUser(
        uid: 'uid-1',
        phoneNumber: '+923001234567',
        isEmailVerified: false,
      );
      when(() => requestOtp(phoneE164: any(named: 'phoneE164')))
          .thenAnswer((_) async => const PhoneAutoSignedIn(user));

      final container = makeContainer();
      addTearDown(container.dispose);
      final vm = container.read(authViewModelProvider.notifier);

      await vm.requestOtp(phoneE164: '+923001234567');

      final state = container.read(authViewModelProvider);
      expect(state, isA<AuthFlowAuthenticated>());
      expect((state as AuthFlowAuthenticated).user.uid, 'uid-1');
    });

    test('transitions to AuthFlowError on InvalidPhoneFailure', () async {
      when(() => requestOtp(phoneE164: any(named: 'phoneE164')))
          .thenThrow(const AppFailure.invalidPhone());

      final container = makeContainer();
      addTearDown(container.dispose);
      final vm = container.read(authViewModelProvider.notifier);

      await vm.requestOtp(phoneE164: '+invalid');

      final state = container.read(authViewModelProvider);
      expect(state, isA<AuthFlowError>());
      expect((state as AuthFlowError).message, contains('phone'));
    });
  });

  group('AuthViewModel.verifyOtp', () {
    test('transitions to AuthFlowAuthenticated on success', () async {
      const user = AuthUser(
        uid: 'uid-1',
        phoneNumber: '+923001234567',
        isEmailVerified: false,
      );
      const session = OtpSession(
        sessionId: 'vid-1',
        phoneE164: '+923001234567',
        otpState: OtpState.otpSent,
      );

      when(() => verifyOtp(session: any(named: 'session'), otpCode: any(named: 'otpCode')))
          .thenAnswer((_) async => user);

      final container = makeContainer();
      addTearDown(container.dispose);

      // Manually put into OtpSent state so verifyOtp is allowed.
      final vm = container.read(authViewModelProvider.notifier);
      // ignore: invalid_use_of_protected_member
      vm.state = const AuthFlowOtpSent(session: session);

      await vm.verifyOtp(code: '123456');

      final state = container.read(authViewModelProvider);
      expect(state, isA<AuthFlowAuthenticated>());
      expect((state as AuthFlowAuthenticated).user.uid, 'uid-1');
    });

    test('transitions to AuthFlowError on TooManyAttemptsFailure', () async {
      const session = OtpSession(
        sessionId: 'vid-1',
        phoneE164: '+923001234567',
        otpState: OtpState.otpSent,
      );

      when(() => verifyOtp(session: any(named: 'session'), otpCode: any(named: 'otpCode')))
          .thenThrow(const AppFailure.tooManyAttempts());

      final container = makeContainer();
      addTearDown(container.dispose);
      final vm = container.read(authViewModelProvider.notifier);
      // ignore: invalid_use_of_protected_member
      vm.state = const AuthFlowOtpSent(session: session);

      await vm.verifyOtp(code: '000000');

      final state = container.read(authViewModelProvider);
      expect(state, isA<AuthFlowError>());
      expect((state as AuthFlowError).message, contains('Too many'));
    });

    test('retry after wrong code still verifies (session from error state)', () async {
      const user = AuthUser(
        uid: 'uid-1',
        phoneNumber: '+923001234567',
        isEmailVerified: false,
      );
      const session = OtpSession(
        sessionId: 'vid-1',
        phoneE164: '+923001234567',
        otpState: OtpState.otpSent,
      );

      var attempt = 0;
      when(() => verifyOtp(session: any(named: 'session'), otpCode: any(named: 'otpCode')))
          .thenAnswer((_) async {
        attempt++;
        if (attempt == 1) throw const AppFailure.invalidOtp();
        return user;
      });

      final container = makeContainer();
      addTearDown(container.dispose);
      final vm = container.read(authViewModelProvider.notifier);
      // ignore: invalid_use_of_protected_member
      vm.state = const AuthFlowOtpSent(session: session);

      await vm.verifyOtp(code: '000000');
      expect(container.read(authViewModelProvider), isA<AuthFlowError>());

      // Second attempt must not be dead — the verify button stays live.
      await vm.verifyOtp(code: '123456');
      verify(() => verifyOtp(
          session: any(named: 'session'), otpCode: any(named: 'otpCode'))).called(2);
      expect(container.read(authViewModelProvider), isA<AuthFlowAuthenticated>());
    });

    test('resend still works from error state', () async {
      const session = OtpSession(
        sessionId: 'vid-1',
        phoneE164: '+923001234567',
        otpState: OtpState.otpSent,
      );
      when(() => resendOtp(session: any(named: 'session'))).thenAnswer(
        (_) async => const PhoneCodeSent(
          OtpSession(
            sessionId: 'vid-2',
            phoneE164: '+923001234567',
            otpState: OtpState.otpSent,
          ),
        ),
      );

      final container = makeContainer();
      addTearDown(container.dispose);
      final vm = container.read(authViewModelProvider.notifier);
      // ignore: invalid_use_of_protected_member
      vm.state = const AuthFlowError(
        message: 'Incorrect code.',
        previousState: AuthFlowOtpSent(session: session),
      );

      await vm.resendOtp();
      verify(() => resendOtp(session: any(named: 'session'))).called(1);
      expect(container.read(authViewModelProvider), isA<AuthFlowOtpSent>());
    });
  });

  group('AuthViewModel.resendOtp', () {
    test('does nothing if state is not AuthFlowOtpSent', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final vm = container.read(authViewModelProvider.notifier);
      // State is idle
      await vm.resendOtp();
      verifyNever(() => resendOtp(session: any(named: 'session')));
    });

    test('returns cooldown state if session is cooling down', () async {
      final cooldownUntil = DateTime.now().add(const Duration(seconds: 20));
      final session = OtpSession(
        sessionId: 'vid-1',
        phoneE164: '+923001234567',
        otpState: OtpState.otpSent,
        cooldownUntil: cooldownUntil,
      );

      final container = makeContainer();
      addTearDown(container.dispose);
      final vm = container.read(authViewModelProvider.notifier);
      // ignore: invalid_use_of_protected_member
      vm.state = AuthFlowOtpSent(session: session);

      await vm.resendOtp();

      expect(container.read(authViewModelProvider), isA<AuthFlowResendCooldown>());
      verifyNever(() => resendOtp(session: any(named: 'session')));
    });
  });

  group('AuthViewModel.logout', () {
    test('calls logout use case and resets state', () async {
      when(() => logout()).thenAnswer((_) async {});

      final container = makeContainer();
      addTearDown(container.dispose);
      final vm = container.read(authViewModelProvider.notifier);

      await vm.logout();

      verify(() => logout()).called(1);
      expect(container.read(authViewModelProvider), isA<AuthFlowPhoneEntry>());
    });
  });
}
