import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/app/theme/theme.dart';
import 'package:ora/features/auth/domain/entities/app_bootstrap.dart';
import 'package:ora/features/auth/domain/entities/otp_session.dart';
import 'package:ora/features/auth/domain/repositories/app_config_repository.dart';
import 'package:ora/features/auth/domain/use_cases/get_app_bootstrap_use_case.dart';
import 'package:ora/features/auth/presentation/view_models/auth_state_notifier.dart';
import 'package:ora/features/auth/presentation/view_models/auth_view_model.dart';
import 'package:ora/features/auth/presentation/view_models/auth_view_state.dart';
import 'package:ora/features/auth/presentation/views/otp_entry_view.dart';
import 'package:ora/features/auth/presentation/views/phone_entry_view.dart';
import 'package:ora/features/auth/presentation/views/splash_view.dart';
import 'package:ora/features/onboarding/presentation/view_models/onboarding_view_model.dart';
import 'package:ora/features/onboarding/presentation/view_models/onboarding_view_state.dart';
import 'package:ora/features/onboarding/presentation/views/onboarding_view.dart';

class _FixedAuthState extends AuthStateNotifier {
  _FixedAuthState(this._status);
  final AuthStatus _status;
  @override
  AuthStatus build() => _status;
}

class _ControllableAuthVm extends AuthViewModel {
  _ControllableAuthVm({AuthFlowState initial = const AuthFlowIdle()})
    : _initial = initial;

  final AuthFlowState _initial;
  String? lastRequestedPhone;
  String? lastVerifiedCode;
  int resendCalls = 0;
  Completer<void>? requestGate;
  Object? requestError;

  @override
  AuthFlowState build() => _initial;

  @override
  Future<void> requestOtp({required String phoneE164}) async {
    lastRequestedPhone = phoneE164;
    state = const AuthFlowRequestingOtp();
    if (requestGate != null) await requestGate!.future;
    if (requestError != null) {
      state = AuthFlowError(
        message: requestError.toString(),
        previousState: const AuthFlowPhoneEntry(),
      );
      return;
    }
    state = const AuthFlowOtpSent(
      session: OtpSession(
        sessionId: 'vid-test',
        phoneE164: '+923001234567',
        otpState: OtpState.otpSent,
      ),
    );
  }

  @override
  Future<void> verifyOtp({required String code}) async {
    lastVerifiedCode = code;
    const session = OtpSession(
      sessionId: 'vid-test',
      phoneE164: '+923001234567',
      otpState: OtpState.otpSent,
    );
    state = const AuthFlowVerifyingOtp(session: session);
    state = const AuthFlowOtpSent(session: session);
  }

  @override
  Future<void> resendOtp() async {
    resendCalls++;
  }

  @override
  void showPhoneEntry() {
    state = const AuthFlowPhoneEntry();
  }
}

class _FakeBootstrapRepo implements AppConfigRepository {
  _FakeBootstrapRepo(this.bootstrap);
  final AppBootstrap bootstrap;
  @override
  Future<AppBootstrap> loadBootstrap() async => bootstrap;
}

class _ControllableOnboardingVm extends OnboardingViewModel {
  _ControllableOnboardingVm({OnboardingViewState? initial})
    : _initial = initial ?? const OnboardingViewState();

  final OnboardingViewState _initial;
  String? lastSubmitted;

  @override
  OnboardingViewState build() => _initial;

  @override
  void onNameChanged(String value) {
    state = state.copyWith(fieldError: null, serverError: null);
  }

  @override
  Future<void> submit({required String rawName}) async {
    lastSubmitted = rawName;
    if (rawName.trim().isEmpty) {
      state = state.copyWith(fieldError: 'Please enter your name.');
      return;
    }
    state = state.copyWith(status: OnboardingStatus.submitting);
  }
}

Widget _wrap(
  Widget child, {
  List<Override> overrides = const [],
  Size size = const Size(390, 844),
  double textScale = 1,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: MaterialApp(theme: OraTheme.dark(), home: child),
    ),
  );
}

void main() {
  const session = OtpSession(
    sessionId: 'vid-1',
    phoneE164: '+923001234567',
    otpState: OtpState.otpSent,
  );

  const bootstrap = AppBootstrap(
    appName: 'Ora',
    environmentName: 'Development',
    apiBaseUrl: 'https://example.invalid',
    clientVersion: '1.0.0',
  );

  group('PhoneEntryView', () {
    testWidgets('renders Ora branding and CTA', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PhoneEntryView(),
          overrides: [
            authViewModelProvider.overrideWith(() => _ControllableAuthVm()),
          ],
        ),
      );
      expect(find.textContaining('Welcome to Ora'), findsOneWidget);
      expect(find.text('Send code'), findsOneWidget);
      expect(find.text('Phone number'), findsOneWidget);
    });

    testWidgets('shows inline validation for invalid phone', (tester) async {
      final vm = _ControllableAuthVm();
      await tester.pumpWidget(
        _wrap(
          const PhoneEntryView(),
          overrides: [authViewModelProvider.overrideWith(() => vm)],
        ),
      );
      await tester.enterText(find.byType(TextField), '123');
      await tester.tap(find.text('Send code'));
      await tester.pump();
      expect(vm.lastRequestedPhone, isNull);
      expect(
        find.text('Use a Pakistan mobile number (+92… or 03…)'),
        findsOneWidget,
      );
    });

    testWidgets('shows loading while requesting OTP', (tester) async {
      final gate = Completer<void>();
      final vm = _ControllableAuthVm()..requestGate = gate;
      await tester.pumpWidget(
        _wrap(
          const PhoneEntryView(),
          overrides: [authViewModelProvider.overrideWith(() => vm)],
        ),
      );
      await tester.enterText(find.byType(TextField), '+923001234567');
      await tester.tap(find.text('Send code'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(vm.lastRequestedPhone, '+923001234567');
      // Leave gate incomplete so we do not navigate to OTP without a router.
    });

    testWidgets('surfaces recoverable auth error', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PhoneEntryView(),
          overrides: [
            authViewModelProvider.overrideWith(
              () => _ControllableAuthVm(
                initial: const AuthFlowError(
                  message: 'Too many attempts. Try again later.',
                  previousState: AuthFlowPhoneEntry(),
                ),
              ),
            ),
          ],
        ),
      );
      expect(find.text('Too many attempts. Try again later.'), findsOneWidget);
    });

    testWidgets('layout has no overflow on compact phone', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PhoneEntryView(),
          size: const Size(320, 568),
          textScale: 1.3,
          overrides: [
            authViewModelProvider.overrideWith(() => _ControllableAuthVm()),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('OtpEntryView', () {
    testWidgets('renders verification hierarchy and pin boxes', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const OtpEntryView(),
          overrides: [
            authViewModelProvider.overrideWith(
              () => _ControllableAuthVm(
                initial: const AuthFlowOtpSent(session: session),
              ),
            ),
          ],
        ),
      );
      expect(find.text('Verify your number'), findsOneWidget);
      expect(find.text('Verify & continue'), findsOneWidget);
      expect(find.byType(OraPinBox), findsNWidgets(6));
    });

    testWidgets('submits 6-digit code', (tester) async {
      final vm = _ControllableAuthVm(
        initial: const AuthFlowOtpSent(session: session),
      );
      await tester.pumpWidget(
        _wrap(
          const OtpEntryView(),
          overrides: [authViewModelProvider.overrideWith(() => vm)],
        ),
      );
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      expect(vm.lastVerifiedCode, '123456');
    });

    testWidgets('shows verifying progress', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const OtpEntryView(),
          overrides: [
            authViewModelProvider.overrideWith(
              () => _ControllableAuthVm(
                initial: const AuthFlowVerifyingOtp(session: session),
              ),
            ),
          ],
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error and allows resend when idle', (tester) async {
      final vm = _ControllableAuthVm(
        initial: const AuthFlowError(
          message: 'Invalid code. Please try again.',
          previousState: AuthFlowOtpSent(session: session),
        ),
      );
      await tester.pumpWidget(
        _wrap(
          const OtpEntryView(),
          overrides: [authViewModelProvider.overrideWith(() => vm)],
        ),
      );
      expect(find.text('Invalid code. Please try again.'), findsOneWidget);
      await tester.tap(find.text('Resend code'));
      await tester.pump();
      expect(vm.resendCalls, 1);
    });

    testWidgets('shows cooldown banner', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const OtpEntryView(),
          overrides: [
            authViewModelProvider.overrideWith(
              () => _ControllableAuthVm(
                initial: const AuthFlowResendCooldown(
                  session: session,
                  remaining: Duration(seconds: 28),
                ),
              ),
            ),
          ],
        ),
      );
      expect(find.textContaining('Resend available in'), findsOneWidget);
    });
  });

  group('OnboardingView', () {
    testWidgets('renders name field and continue CTA', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const OnboardingView(),
          overrides: [
            onboardingViewModelProvider.overrideWith(
              () => _ControllableOnboardingVm(),
            ),
            authViewModelProvider.overrideWith(() => _ControllableAuthVm()),
          ],
        ),
      );
      expect(find.text('What should we call you?'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('shows validation when name empty', (tester) async {
      final vm = _ControllableOnboardingVm();
      await tester.pumpWidget(
        _wrap(
          const OnboardingView(),
          overrides: [
            onboardingViewModelProvider.overrideWith(() => vm),
            authViewModelProvider.overrideWith(() => _ControllableAuthVm()),
          ],
        ),
      );
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(find.text('Please enter your name.'), findsOneWidget);
    });

    testWidgets('shows submitting state', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const OnboardingView(),
          overrides: [
            onboardingViewModelProvider.overrideWith(
              () => _ControllableOnboardingVm(
                initial: const OnboardingViewState(
                  status: OnboardingStatus.submitting,
                ),
              ),
            ),
            authViewModelProvider.overrideWith(() => _ControllableAuthVm()),
          ],
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows server error banner', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const OnboardingView(),
          overrides: [
            onboardingViewModelProvider.overrideWith(
              () => _ControllableOnboardingVm(
                initial: const OnboardingViewState(
                  serverError: 'Could not save your name.',
                ),
              ),
            ),
            authViewModelProvider.overrideWith(() => _ControllableAuthVm()),
          ],
        ),
      );
      expect(find.text('Could not save your name.'), findsOneWidget);
    });
  });

  group('SplashView', () {
    testWidgets('shows Ora brand while waiting on session', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SplashView(),
          overrides: [
            authStateNotifierProvider.overrideWith(
              () => _FixedAuthState(AuthStatus.unknown),
            ),
            getAppBootstrapUseCaseProvider.overrideWithValue(
              GetAppBootstrapUseCase(_FakeBootstrapRepo(bootstrap)),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Ora'), findsWidgets);
      expect(find.textContaining('Signing you in'), findsOneWidget);
    });
  });
}
