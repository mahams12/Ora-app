import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../domain/use_cases/get_app_bootstrap_use_case.dart';
import 'splash_view_state.dart';

class SplashViewModel extends Notifier<SplashViewState> {
  late final GetAppBootstrapUseCase _getAppBootstrap;
  late final FailureMapper _failureMapper;

  @override
  SplashViewState build() {
    _getAppBootstrap = ref.read(getAppBootstrapUseCaseProvider);
    _failureMapper = ref.read(failureMapperProvider);
    // Start bootstrap from the notifier lifecycle so SplashView does not race
    // auth redirects that dispose the widget before a post-frame callback runs.
    Future.microtask(initialize);
    return const SplashViewState.initial();
  }

  Future<void> initialize() async {
    if (state is SplashLoading || state is SplashLoaded) {
      return;
    }

    state = const SplashViewState.loading();
    try {
      final bootstrap = await _getAppBootstrap();
      try {
        state = SplashViewState.loaded(bootstrap);
      } on StateError {
        // Notifier disposed after auth redirected off splash.
      }
    } catch (error, stackTrace) {
      // Provider may have been disposed after auth redirected off splash.
      try {
        ref.read(appLoggerProvider).error(
              'Splash bootstrap failed',
              error: error,
              stackTrace: stackTrace,
            );
        state = SplashViewState.error(_failureMapper.fromException(error));
      } on StateError {
        // Notifier disposed — safe to ignore.
      }
    }
  }

  void retry() {
    state = const SplashViewState.initial();
    initialize();
  }
}
