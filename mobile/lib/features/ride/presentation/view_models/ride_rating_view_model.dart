import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/di/providers.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../../../core/storage/idempotency_nonce_store.dart';
import '../../domain/entities/ride.dart';
import '../../domain/use_cases/ride_use_cases.dart';
import '../ratings/rating_display.dart';

enum RideRatingPhase {
  loading,
  readyToRate,
  submitting,
  success,
  alreadyRated,
  ineligible,
  fatalError,
}

class RideRatingUiState {
  const RideRatingUiState({
    this.phase = RideRatingPhase.loading,
    this.rideState,
    this.selectedStars = 0,
    this.submittedRating,
    this.errorMessage,
  });

  final RideRatingPhase phase;
  final String? rideState;
  final int selectedStars;
  final RideRating? submittedRating;
  final String? errorMessage;

  bool get canSubmit =>
      phase == RideRatingPhase.readyToRate &&
      selectedStars >= 1 &&
      selectedStars <= 5;

  bool get isReadOnly =>
      phase == RideRatingPhase.alreadyRated ||
      phase == RideRatingPhase.success;

  int get displayStars {
    if (submittedRating != null) return submittedRating!.stars;
    return selectedStars;
  }

  RideRatingUiState copyWith({
    RideRatingPhase? phase,
    String? rideState,
    int? selectedStars,
    RideRating? submittedRating,
    String? errorMessage,
    bool clearError = false,
    bool clearSubmitted = false,
  }) {
    return RideRatingUiState(
      phase: phase ?? this.phase,
      rideState: rideState ?? this.rideState,
      selectedStars: selectedStars ?? this.selectedStars,
      submittedRating:
          clearSubmitted ? null : (submittedRating ?? this.submittedRating),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Passenger stars-only rating — server derives participants; no comments.
class RideRatingViewModel
    extends AutoDisposeFamilyNotifier<RideRatingUiState, String> {
  late final GetRideUseCase _getRide;
  late final GetMyRatingUseCase _getMyRating;
  late final SubmitRatingUseCase _submitRating;
  late final FailureMapper _failures;
  late final IdempotencyNonceStore _nonceStore;

  String? _submitOpKey;
  int? _opKeyStars;
  int _submitGen = 0;
  int _loadSeq = 0;
  bool _disposed = false;

  String get rideId => arg;

  bool get _alive => !_disposed;

  @override
  RideRatingUiState build(String arg) {
    _getRide = ref.read(getRideUseCaseProvider);
    _getMyRating = ref.read(getMyRatingUseCaseProvider);
    _submitRating = ref.read(submitRatingUseCaseProvider);
    _failures = ref.read(failureMapperProvider);
    _nonceStore = ref.read(idempotencyNonceStoreProvider);
    ref.onDispose(() => _disposed = true);
    return const RideRatingUiState();
  }

  Future<void> load() async {
    if (!_alive) return;
    final seq = ++_loadSeq;
    state = state.copyWith(
      phase: RideRatingPhase.loading,
      clearError: true,
      clearSubmitted: true,
      selectedStars: 0,
    );

    // K-P2-04: overlap ride + own-rating GETs.
    Object? rideResult;
    Object? ratingResult;
    await Future.wait<void>([
      () async {
        try {
          rideResult = await _getRide(rideId);
        } catch (error) {
          rideResult = error;
        }
      }(),
      () async {
        try {
          ratingResult = await _getMyRating(rideId);
        } catch (error) {
          ratingResult = error;
        }
      }(),
    ]);

    if (!_alive || seq != _loadSeq) return;

    String? rideState;
    if (rideResult is Ride) {
      rideState = (rideResult as Ride).state;
    }

    if (ratingResult is RideRating) {
      final existing = ratingResult as RideRating;
      state = state.copyWith(
        phase: RideRatingPhase.alreadyRated,
        rideState: rideState,
        submittedRating: existing,
        selectedStars: existing.stars,
        clearError: true,
      );
      return;
    }

    if (ratingResult != null) {
      final failure = _failures.fromException(
        ratingResult!,
        StackTrace.current,
      );
      final isMissing = failure.maybeWhen(
        notFound: (_) => true,
        orElse: () => false,
      );
      if (!isMissing) {
        state = state.copyWith(
          phase: RideRatingPhase.fatalError,
          rideState: rideState,
          errorMessage: failure.userMessage,
        );
        return;
      }
    }

    if (rideState != null && !isPassengerRatingSoftEligible(rideState)) {
      state = state.copyWith(
        phase: RideRatingPhase.ineligible,
        rideState: rideState,
        errorMessage: ratingIneligibleMessage(rideState),
        clearError: false,
      );
      return;
    }

    state = state.copyWith(
      phase: RideRatingPhase.readyToRate,
      rideState: rideState,
      clearError: true,
    );
  }

  void selectStars(int stars) {
    if (!_alive) return;
    if (state.isReadOnly || state.phase == RideRatingPhase.submitting) return;
    if (state.phase != RideRatingPhase.readyToRate) return;
    if (stars < 1 || stars > 5) return;

    // H5/H7: star change after a prior submit attempt requires a new key.
    if (_submitOpKey != null && _opKeyStars != null && _opKeyStars != stars) {
      final old = _submitOpKey;
      _submitOpKey = null;
      _opKeyStars = null;
      if (old != null) unawaited(_nonceStore.clear(old));
    }

    state = state.copyWith(selectedStars: stars, clearError: true);
  }

  Future<void> submit() async {
    if (!_alive) return;
    if (!state.canSubmit) return;
    if (state.phase == RideRatingPhase.submitting) return;

    final stars = state.selectedStars;
    if (_submitOpKey != null && _opKeyStars != null && _opKeyStars != stars) {
      final old = _submitOpKey;
      _submitOpKey = null;
      _opKeyStars = null;
      if (old != null) unawaited(_nonceStore.clear(old));
    }

    _submitOpKey ??= 'ride:rating:$rideId:${const Uuid().v4()}';
    _opKeyStars = stars;
    final gen = ++_submitGen;
    final opKey = _submitOpKey!;

    state = state.copyWith(
      phase: RideRatingPhase.submitting,
      clearError: true,
    );

    try {
      final rating = await _submitRating(
        rideId: rideId,
        stars: stars,
        operationKey: opKey,
      );
      if (!_alive || gen != _submitGen) return;
      // Ignore success if user changed stars mid-flight (shouldn't happen —
      // selectStars blocks during submitting — but guard anyway).
      if (state.selectedStars != stars &&
          state.phase != RideRatingPhase.submitting) {
        return;
      }
      state = state.copyWith(
        phase: RideRatingPhase.success,
        submittedRating: rating,
        selectedStars: rating.stars,
        clearError: true,
      );
    } catch (error, stack) {
      if (!_alive || gen != _submitGen) return;
      final failure = _failures.fromException(error, stack);
      await _handleSubmitFailure(failure, stars: stars);
    }
  }

  Future<void> _handleSubmitFailure(
    AppFailure failure, {
    required int stars,
  }) async {
    final code = failure.maybeWhen(
      conflict: (_, code) => code,
      orElse: () => null,
    );

    if (code == 'ALREADY_RATED') {
      try {
        final existing = await _getMyRating(rideId);
        if (!_alive) return;
        state = state.copyWith(
          phase: RideRatingPhase.alreadyRated,
          submittedRating: existing,
          selectedStars: existing.stars,
          clearError: true,
        );
      } catch (_) {
        if (!_alive) return;
        state = state.copyWith(
          phase: RideRatingPhase.alreadyRated,
          errorMessage: failure.userMessage,
        );
      }
      return;
    }

    if (code == 'STATE_CONFLICT' ||
        code == 'VERSION_CONFLICT' ||
        code == 'IDEMPOTENCY_KEY_REUSED') {
      final old = _submitOpKey;
      _submitOpKey = null;
      _opKeyStars = null;
      if (old != null) unawaited(_nonceStore.clear(old));
    }

    if (code == 'STATE_CONFLICT') {
      if (!_alive) return;
      state = state.copyWith(
        phase: RideRatingPhase.ineligible,
        errorMessage: failure.userMessage,
      );
      return;
    }

    if (!_alive) return;
    state = state.copyWith(
      phase: RideRatingPhase.readyToRate,
      errorMessage: failure.userMessage,
    );
  }

  Future<void> retry() => load();
}

final rideRatingViewModelProvider = NotifierProvider.autoDispose
    .family<RideRatingViewModel, RideRatingUiState, String>(
  RideRatingViewModel.new,
);
