import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/features/auth/presentation/view_models/auth_state_notifier.dart';
import 'package:ora/features/auth/presentation/view_models/auth_view_state.dart';
import 'package:ora/features/onboarding/presentation/view_models/onboarding_view_state.dart';

class _RecordingAuthStateNotifier extends AuthStateNotifier {
  int retryCalls = 0;

  @override
  AuthStatus build() => AuthStatus.onboardingRequired;

  @override
  Future<void> retryProfileBootstrap() async {
    retryCalls++;
    // Simulate server eventually marking the profile complete.
    state = AuthStatus.authenticatedReady;
  }
}

void main() {
  test('starts idle', () {
    final container = ProviderContainer(
      overrides: [
        authStateNotifierProvider.overrideWith(_RecordingAuthStateNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(onboardingViewModelProvider),
      OnboardingViewState.idle,
    );
  });

  test('completePlaceholder re-resolves profile instead of forging ready',
      () async {
    final notifier = _RecordingAuthStateNotifier();
    final container = ProviderContainer(
      overrides: [
        authStateNotifierProvider.overrideWith(() => notifier),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(onboardingViewModelProvider.notifier)
        .completePlaceholder();

    expect(notifier.retryCalls, 1);
    expect(
      container.read(authStateNotifierProvider),
      AuthStatus.authenticatedReady,
    );
    expect(
      container.read(onboardingViewModelProvider),
      OnboardingViewState.completed,
    );
  });
}
