import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora/app/config/app_config.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/core/errors/app_failure.dart';
import 'package:ora/features/auth/presentation/view_models/splash_view_state.dart';

void main() {
  group('SplashViewModel', () {
    test('transitions loading -> loaded on success', () async {
      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.development()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(splashViewModelProvider.notifier);
      expect(container.read(splashViewModelProvider), const SplashViewState.initial());

      final future = notifier.initialize();
      expect(container.read(splashViewModelProvider), const SplashViewState.loading());

      await future;
      final state = container.read(splashViewModelProvider);
      expect(state, isA<SplashLoaded>());
    });

    test('retry moves to loading and completes', () async {
      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.development()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(splashViewModelProvider.notifier);
      await notifier.initialize();
      notifier.retry();
      expect(container.read(splashViewModelProvider), const SplashViewState.loading());
      await Future<void>.delayed(Duration.zero);
      expect(container.read(splashViewModelProvider), isA<SplashLoaded>());
    });
  });

  test('AppFailure userMessage is safe for UI', () {
    const failure = AppFailure.network(message: 'Offline');
    expect(failure.userMessage, 'Offline');
  });
}
