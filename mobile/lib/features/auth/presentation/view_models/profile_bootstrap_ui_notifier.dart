import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'profile_bootstrap_ui_state.dart';

class ProfileBootstrapUiNotifier extends Notifier<ProfileBootstrapUiState> {
  @override
  ProfileBootstrapUiState build() => const ProfileBootstrapUiState();

  void resetForBootstrap() {
    state = const ProfileBootstrapUiState(inProgress: true);
  }

  void setAutoRetrying() {
    state = state.copyWith(inProgress: true, autoRetrying: true, clearFailure: true);
  }

  void setFailure(String message) {
    state = ProfileBootstrapUiState(
      inProgress: false,
      failureMessage: message,
    );
  }

  void clear() {
    state = const ProfileBootstrapUiState();
  }
}

final profileBootstrapUiProvider =
    NotifierProvider<ProfileBootstrapUiNotifier, ProfileBootstrapUiState>(
  ProfileBootstrapUiNotifier.new,
);
