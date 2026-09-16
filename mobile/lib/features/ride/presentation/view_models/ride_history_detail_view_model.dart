import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../domain/entities/ride.dart';
import '../../domain/use_cases/ride_use_cases.dart';
import '../history/ride_history_display.dart';

enum RideHistoryDetailPhase {
  loading,
  ready,
  redirectOffers,
  redirectActive,
  fatalError,
}

class RideHistoryDetailUiState {
  const RideHistoryDetailUiState({
    this.phase = RideHistoryDetailPhase.loading,
    this.ride,
    this.errorMessage,
  });

  final RideHistoryDetailPhase phase;
  final Ride? ride;
  final String? errorMessage;

  RideHistoryDetailUiState copyWith({
    RideHistoryDetailPhase? phase,
    Ride? ride,
    String? errorMessage,
    bool clearError = false,
  }) {
    return RideHistoryDetailUiState(
      phase: phase ?? this.phase,
      ride: ride ?? this.ride,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Terminal ride detail — single GET, no polling. Request-sequenced (H6).
class RideHistoryDetailViewModel
    extends AutoDisposeFamilyNotifier<RideHistoryDetailUiState, String> {
  late final GetRideUseCase _getRide;
  late final FailureMapper _failures;

  int _loadSeq = 0;
  bool _disposed = false;

  String get rideId => arg;

  bool get _alive => !_disposed;

  @override
  RideHistoryDetailUiState build(String arg) {
    _getRide = ref.read(getRideUseCaseProvider);
    _failures = ref.read(failureMapperProvider);
    ref.onDispose(() => _disposed = true);
    return const RideHistoryDetailUiState();
  }

  Future<void> load() async {
    if (!_alive) return;
    final seq = ++_loadSeq;
    state = state.copyWith(
      phase: RideHistoryDetailPhase.loading,
      clearError: true,
    );
    try {
      final ride = await _getRide(rideId);
      if (!_alive || seq != _loadSeq) return;
      final dest = rideHistoryDestinationFor(ride.state);
      state = state.copyWith(
        ride: ride,
        phase: switch (dest) {
          RideHistoryDestination.offers =>
            RideHistoryDetailPhase.redirectOffers,
          RideHistoryDestination.active =>
            RideHistoryDetailPhase.redirectActive,
          RideHistoryDestination.detail => RideHistoryDetailPhase.ready,
        },
        clearError: true,
      );
    } catch (error, stack) {
      if (!_alive || seq != _loadSeq) return;
      final failure = _failures.fromException(error, stack);
      state = state.copyWith(
        phase: RideHistoryDetailPhase.fatalError,
        errorMessage: failure.userMessage,
      );
    }
  }

  Future<void> retry() => load();
}

final rideHistoryDetailViewModelProvider = NotifierProvider.autoDispose
    .family<RideHistoryDetailViewModel, RideHistoryDetailUiState, String>(
  RideHistoryDetailViewModel.new,
);
