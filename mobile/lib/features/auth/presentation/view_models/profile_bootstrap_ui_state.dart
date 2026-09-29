/// Splash UX while `GET /v1/auth/me` bootstrap runs (orthogonal to [AuthStatus]).
class ProfileBootstrapUiState {
  const ProfileBootstrapUiState({
    this.inProgress = false,
    this.autoRetrying = false,
    this.failureMessage,
  });

  final bool inProgress;
  final bool autoRetrying;
  final String? failureMessage;

  ProfileBootstrapUiState copyWith({
    bool? inProgress,
    bool? autoRetrying,
    String? failureMessage,
    bool clearFailure = false,
  }) {
    return ProfileBootstrapUiState(
      inProgress: inProgress ?? this.inProgress,
      autoRetrying: autoRetrying ?? this.autoRetrying,
      failureMessage:
          clearFailure ? null : (failureMessage ?? this.failureMessage),
    );
  }
}
