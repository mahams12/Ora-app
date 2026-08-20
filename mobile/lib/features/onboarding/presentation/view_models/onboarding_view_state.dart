/// State of the Phase 2 onboarding placeholder screen.
enum OnboardingViewState {
  /// Waiting for the user to acknowledge the placeholder screen.
  idle,

  /// The auth state has been promoted; the router guard owns navigation now.
  completed,
}
