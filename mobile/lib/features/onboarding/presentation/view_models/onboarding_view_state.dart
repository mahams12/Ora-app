enum OnboardingStatus {
  idle,
  submitting,
  submitted,
}

/// Presentation state for display-name onboarding.
class OnboardingViewState {
  const OnboardingViewState({
    this.status = OnboardingStatus.idle,
    this.fieldError,
    this.serverError,
  });

  final OnboardingStatus status;
  final String? fieldError;
  final String? serverError;

  bool get isSubmitting => status == OnboardingStatus.submitting;

  OnboardingViewState copyWith({
    OnboardingStatus? status,
    String? fieldError,
    String? serverError,
  }) =>
      OnboardingViewState(
        status: status ?? this.status,
        fieldError: fieldError,
        serverError: serverError,
      );
}
