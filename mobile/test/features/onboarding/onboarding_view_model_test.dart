import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/core/errors/app_failure.dart';
import 'package:ora/features/auth/domain/entities/user_profile.dart';
import 'package:ora/features/auth/domain/use_cases/update_display_name_use_case.dart';
import 'package:ora/features/auth/presentation/view_models/auth_state_notifier.dart';
import 'package:ora/features/auth/presentation/view_models/auth_view_state.dart';
import 'package:ora/features/onboarding/presentation/view_models/onboarding_view_state.dart';

class MockUpdateDisplayNameUseCase extends Mock
    implements UpdateDisplayNameUseCase {}

class _RecordingAuthStateNotifier extends AuthStateNotifier {
  int applyCalls = 0;
  int refreshCalls = 0;
  int readyForgeCalls = 0;
  UserProfile? lastApplied;

  @override
  AuthStatus build() => AuthStatus.onboardingRequired;

  @override
  Future<void> applyCanonicalProfile(UserProfile profile) async {
    applyCalls++;
    lastApplied = profile;
    state = profile.profileComplete
        ? AuthStatus.authenticatedReady
        : AuthStatus.onboardingRequired;
  }

  @override
  Future<void> refreshCanonicalProfile() async {
    refreshCalls++;
    state = AuthStatus.authenticatedReady;
  }

  @override
  void setAuthenticatedReady() {
    readyForgeCalls++;
    super.setAuthenticatedReady();
  }
}

void main() {
  late MockUpdateDisplayNameUseCase updateDisplayName;
  late _RecordingAuthStateNotifier notifier;

  const completeProfile = UserProfile(
    uid: 'uid-1',
    phoneNumber: '+923001234567',
    displayName: 'Ada Khan',
    profileComplete: true,
  );

  setUp(() {
    updateDisplayName = MockUpdateDisplayNameUseCase();
    notifier = _RecordingAuthStateNotifier();
  });

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [
        updateDisplayNameUseCaseProvider.overrideWithValue(updateDisplayName),
        authStateNotifierProvider.overrideWith(() => notifier),
      ],
    );
  }

  test('starts idle', () {
    final container = makeContainer();
    addTearDown(container.dispose);

    expect(
      container.read(onboardingViewModelProvider).status,
      OnboardingStatus.idle,
    );
  });

  test('rejects an invalid name without calling the API', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    await container
        .read(onboardingViewModelProvider.notifier)
        .submit(rawName: '   ');

    expect(
      container.read(onboardingViewModelProvider).fieldError,
      isNotNull,
    );
    verifyNever(
      () => updateDisplayName(displayName: any(named: 'displayName')),
    );
    expect(notifier.applyCalls, 0);
    expect(notifier.refreshCalls, 0);
    expect(notifier.readyForgeCalls, 0);
  });

  test('saves a valid name then applies PATCH profile (not a second /me)',
      () async {
    when(() => updateDisplayName(displayName: any(named: 'displayName')))
        .thenAnswer((_) async => completeProfile);

    final container = makeContainer();
    addTearDown(container.dispose);

    await container
        .read(onboardingViewModelProvider.notifier)
        .submit(rawName: '  Ada   Khan  ');

    verify(() => updateDisplayName(displayName: 'Ada Khan')).called(1);
    expect(notifier.applyCalls, 1);
    expect(notifier.refreshCalls, 0);
    expect(notifier.readyForgeCalls, 0);
    expect(notifier.lastApplied?.profileComplete, isTrue);
    expect(
      container.read(onboardingViewModelProvider).status,
      OnboardingStatus.submitted,
    );
    expect(
      container.read(authStateNotifierProvider),
      AuthStatus.authenticatedReady,
    );
  });

  test('double-tap Continue is ignored while submitting', () async {
    final gate = Completer<UserProfile>();
    when(() => updateDisplayName(displayName: any(named: 'displayName')))
        .thenAnswer((_) => gate.future);

    final container = makeContainer();
    addTearDown(container.dispose);
    final vm = container.read(onboardingViewModelProvider.notifier);

    final first = vm.submit(rawName: 'Ada Khan');
    final second = vm.submit(rawName: 'Ada Khan');
    gate.complete(completeProfile);
    await Future.wait([first, second]);

    verify(() => updateDisplayName(displayName: 'Ada Khan')).called(1);
    expect(notifier.applyCalls, 1);
    expect(notifier.refreshCalls, 0);
  });

  test('reaches home from PATCH profile without calling /me', () async {
    when(() => updateDisplayName(displayName: any(named: 'displayName')))
        .thenAnswer((_) async => completeProfile);

    final container = makeContainer();
    addTearDown(container.dispose);

    await container
        .read(onboardingViewModelProvider.notifier)
        .submit(rawName: 'Ada Khan');

    expect(
      container.read(onboardingViewModelProvider).status,
      OnboardingStatus.submitted,
    );
    expect(
      container.read(authStateNotifierProvider),
      AuthStatus.authenticatedReady,
    );
    expect(notifier.refreshCalls, 0);
    expect(notifier.readyForgeCalls, 0);
  });

  test('surfaces a server error and allows retry', () async {
    when(() => updateDisplayName(displayName: any(named: 'displayName')))
        .thenThrow(const AppFailure.network(message: 'offline'));

    final container = makeContainer();
    addTearDown(container.dispose);

    await container
        .read(onboardingViewModelProvider.notifier)
        .submit(rawName: 'Ada Khan');

    expect(
      container.read(onboardingViewModelProvider).serverError,
      isNotNull,
    );
    expect(notifier.applyCalls, 0);
    expect(notifier.refreshCalls, 0);

    when(() => updateDisplayName(displayName: any(named: 'displayName')))
        .thenAnswer((_) async => completeProfile);
    await container
        .read(onboardingViewModelProvider.notifier)
        .submit(rawName: 'Ada Khan');

    expect(
      container.read(onboardingViewModelProvider).status,
      OnboardingStatus.submitted,
    );
    expect(notifier.applyCalls, 1);
  });
}
