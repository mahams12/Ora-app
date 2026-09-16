import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/utils/display_name.dart';
import '../../../auth/domain/use_cases/update_display_name_use_case.dart';
import 'onboarding_view_state.dart';

/// Onboarding ViewModel — collects displayName and persists via the API.
///
/// Completeness is server-derived. This ViewModel never calls
/// [AuthStateNotifier.setAuthenticatedReady].
class OnboardingViewModel extends Notifier<OnboardingViewState> {
  late final UpdateDisplayNameUseCase _updateDisplayName;

  @override
  OnboardingViewState build() {
    _updateDisplayName = ref.read(updateDisplayNameUseCaseProvider);
    return const OnboardingViewState();
  }

  void onNameChanged(String value) {
    if (state.fieldError != null || state.serverError != null) {
      state = state.copyWith(fieldError: null, serverError: null);
    }
  }

  Future<void> submit({required String rawName}) async {
    if (state.isSubmitting) {
      return;
    }

    final error = DisplayName.validationError(rawName);
    if (error != null) {
      state = state.copyWith(fieldError: error, serverError: null);
      return;
    }

    final name = DisplayName.normalize(rawName);
    state = state.copyWith(
      status: OnboardingStatus.submitting,
      fieldError: null,
      serverError: null,
    );

    try {
      await _updateDisplayName(displayName: name);
      await ref
          .read(authStateNotifierProvider.notifier)
          .refreshCanonicalProfile();
      state = state.copyWith(status: OnboardingStatus.submitted);
    } on AppFailure catch (failure) {
      state = state.copyWith(
        status: OnboardingStatus.idle,
        serverError: failure.userMessage,
      );
    } catch (_) {
      state = state.copyWith(
        status: OnboardingStatus.idle,
        serverError: 'Could not save your name. Please try again.',
      );
    }
  }
}
