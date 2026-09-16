import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../auth/domain/entities/auth_user.dart';
import '../../../auth/domain/use_cases/get_current_user_use_case.dart';
import '../../../auth/domain/use_cases/logout_use_case.dart';

enum HomeLoadStatus { loading, ready, error }

/// Passenger home presentation state (no ride/pricing side effects).
class HomeUiState {
  const HomeUiState({
    this.loadStatus = HomeLoadStatus.loading,
    this.signingOut = false,
    this.displayName,
    this.phoneNumber,
    this.loadError,
  });

  final HomeLoadStatus loadStatus;
  final bool signingOut;
  final String? displayName;
  final String? phoneNumber;
  final String? loadError;

  String get greetingName {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'there';
  }

  String get avatarInitials {
    final name = displayName?.trim();
    if (name == null || name.isEmpty) return 'O';
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final letters = parts.take(2).map((p) => p[0].toUpperCase()).join();
    return letters.isEmpty ? 'O' : letters;
  }

  HomeUiState copyWith({
    HomeLoadStatus? loadStatus,
    bool? signingOut,
    String? displayName,
    String? phoneNumber,
    String? loadError,
    bool clearError = false,
  }) {
    return HomeUiState(
      loadStatus: loadStatus ?? this.loadStatus,
      signingOut: signingOut ?? this.signingOut,
      displayName: displayName ?? this.displayName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      loadError: clearError ? null : (loadError ?? this.loadError),
    );
  }
}

/// Passenger home ViewModel — greeting + logout. Does not create rides.
class HomeViewModel extends Notifier<HomeUiState> {
  late final LogoutUseCase _logout;
  late final GetCurrentUserUseCase _getCurrentUser;

  @override
  HomeUiState build() {
    _logout = ref.read(logoutUseCaseProvider);
    _getCurrentUser = ref.read(getCurrentUserUseCaseProvider);
    Future.microtask(loadProfile);
    return const HomeUiState();
  }

  Future<void> loadProfile() async {
    state = state.copyWith(
      loadStatus: HomeLoadStatus.loading,
      clearError: true,
    );
    try {
      final AuthUser? user = await _getCurrentUser();
      state = state.copyWith(
        loadStatus: HomeLoadStatus.ready,
        displayName: user?.displayName,
        phoneNumber: user?.phoneNumber,
        clearError: true,
      );
    } catch (_) {
      state = state.copyWith(
        loadStatus: HomeLoadStatus.error,
        loadError: 'Could not load your profile. Pull to try again.',
      );
    }
  }

  Future<void> logout() async {
    if (state.signingOut) return;
    state = state.copyWith(signingOut: true);
    try {
      await _logout();
    } finally {
      state = state.copyWith(signingOut: false);
    }
  }

  /// Honest gate: booking requires a server pricing snapshot that clients
  /// cannot invent. Slice C never submits [CreateRideUseCase].
  bool get canSubmitRideRequest => false;

  String get bookingUnavailableMessage =>
      'Ride pricing is currently unavailable. Booking will open once Ora '
      'pricing is ready on your account.';
}
