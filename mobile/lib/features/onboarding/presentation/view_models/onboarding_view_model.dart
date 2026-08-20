import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import 'onboarding_view_state.dart';

/// ViewModel for the Phase 2 onboarding placeholder.
///
/// Completeness is server-derived (`GET /v1/auth/me` → `profileComplete`).
/// The placeholder does not forge readiness: it asks [AuthStateNotifier] to
/// re-resolve the profile. Home is granted only when the server says so.
class OnboardingViewModel extends Notifier<OnboardingViewState> {
  @override
  OnboardingViewState build() => OnboardingViewState.idle;

  /// Re-fetches authoritative profile state from the backend.
  Future<void> completePlaceholder() async {
    state = OnboardingViewState.completed;
    await ref.read(authStateNotifierProvider.notifier).retryProfileBootstrap();
  }
}
