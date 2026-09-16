import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/di/providers.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../../../core/storage/idempotency_nonce_store.dart';
import '../../domain/entities/ride.dart';
import '../../domain/use_cases/ride_use_cases.dart';
import '../active_ride/active_ride_display.dart';

/// Bounded HTTP polling for active ride (no FCM / map / GPS).
class ActiveRidePollingPolicy {
  const ActiveRidePollingPolicy({
    this.intervals = const [
      Duration(seconds: 3),
      Duration(seconds: 5),
      Duration(seconds: 8),
    ],
    this.maxLifetime = const Duration(hours: 4),
  });

  final List<Duration> intervals;
  final Duration maxLifetime;

  Duration delayForAttempt(int attemptIndex) {
    if (intervals.isEmpty) return const Duration(seconds: 5);
    if (attemptIndex < 0) return intervals.first;
    if (attemptIndex >= intervals.length) return intervals.last;
    return intervals[attemptIndex];
  }
}

enum ActiveRidePhase {
  initialLoading,
  active,
  mutating,
  ended,
  fatalError,
}

class ActiveRideUiState {
  const ActiveRideUiState({
    this.phase = ActiveRidePhase.initialLoading,
    this.ride,
    this.isRefreshing = false,
    this.isPolling = false,
    this.isCancelling = false,
    this.isClosing = false,
    this.errorMessage,
    this.infoMessage,
    this.connectivityDegraded = false,
  });

  final ActiveRidePhase phase;
  final Ride? ride;
  final bool isRefreshing;
  final bool isPolling;
  final bool isCancelling;
  final bool isClosing;
  final String? errorMessage;
  final String? infoMessage;
  final bool connectivityDegraded;

  String get rideState => ride?.state ?? '';

  bool get isMutating => isCancelling || isClosing;

  bool get canCancel =>
      ride != null &&
      passengerCanCancel(ride!.state) &&
      !isMutating &&
      phase != ActiveRidePhase.mutating;

  bool get canClose =>
      ride != null &&
      passengerCanClose(ride!.state) &&
      !isMutating &&
      phase != ActiveRidePhase.mutating;

  ActiveRideUiState copyWith({
    ActiveRidePhase? phase,
    Ride? ride,
    bool? isRefreshing,
    bool? isPolling,
    bool? isCancelling,
    bool? isClosing,
    String? errorMessage,
    String? infoMessage,
    bool? connectivityDegraded,
    bool clearError = false,
    bool clearInfo = false,
  }) {
    return ActiveRideUiState(
      phase: phase ?? this.phase,
      ride: ride ?? this.ride,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isPolling: isPolling ?? this.isPolling,
      isCancelling: isCancelling ?? this.isCancelling,
      isClosing: isClosing ?? this.isClosing,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      infoMessage: clearInfo ? null : (infoMessage ?? this.infoMessage),
      connectivityDegraded:
          connectivityDegraded ?? this.connectivityDegraded,
    );
  }
}

/// Passenger active-ride ViewModel — observes server state; never invents it.
class ActiveRideViewModel
    extends AutoDisposeFamilyNotifier<ActiveRideUiState, String> {
  late final GetRideUseCase _getRide;
  late final CancelRideUseCase _cancelRide;
  late final CloseRideUseCase _closeRide;
  late final FailureMapper _failures;
  late final ActiveRidePollingPolicy _policy;
  late final IdempotencyNonceStore _nonceStore;

  Timer? _pollTimer;
  Timer? _clockTimer;
  DateTime? _startedAt;
  bool _disposed = false;
  bool _paused = false;
  bool _lifetimeExpired = false;
  bool _terminalStopped = false;
  int _attempt = 0;
  String? _cancelOpKey;
  String? _closeOpKey;
  int _fetchSeq = 0;
  int _mutationGen = 0;

  /// Display-only 1 Hz clock — does not notify [ActiveRideUiState] listeners.
  final ValueNotifier<DateTime> arrivedNow = ValueNotifier(DateTime.now());

  String get rideId => arg;

  bool get _alive => !_disposed;

  bool get _maySchedulePoll =>
      _alive && !_paused && !_lifetimeExpired && !_terminalStopped;

  @override
  ActiveRideUiState build(String arg) {
    _getRide = ref.read(getRideUseCaseProvider);
    _cancelRide = ref.read(cancelRideUseCaseProvider);
    _closeRide = ref.read(closeRideUseCaseProvider);
    _failures = ref.read(failureMapperProvider);
    _policy = ref.read(activeRidePollingPolicyProvider);
    _nonceStore = ref.read(idempotencyNonceStoreProvider);

    ref.onDispose(() {
      _disposed = true;
      _disposeTimers();
      arrivedNow.dispose();
    });

    Future.microtask(() {
      if (_alive) unawaited(start());
    });

    return const ActiveRideUiState();
  }

  Future<void> start() async {
    if (!_alive) return;
    _lifetimeExpired = false;
    _terminalStopped = false;
    _paused = false;
    _startedAt ??= DateTime.now();
    state = state.copyWith(isPolling: true, clearError: true);
    await refresh(isInitial: state.ride == null);
    _scheduleNext();
    _ensureClock();
  }

  void pausePolling() {
    _paused = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    // M5: freeze arrived clock while backgrounded.
    _clockTimer?.cancel();
    _clockTimer = null;
    if (_alive) {
      state = state.copyWith(isPolling: false);
    }
  }

  Future<void> resumePolling() async {
    if (!_alive) return;
    _paused = false;

    // M2: after max lifetime, one-shot refresh only.
    if (_lifetimeExpired) {
      await refresh(force: true);
      _ensureClock();
      return;
    }

    if (_terminalStopped) {
      _ensureClock();
      return;
    }

    state = state.copyWith(isPolling: true);
    await refresh();
    _scheduleNext();
    _ensureClock();
  }

  /// [force] used for post-mutation reconciliation (never dropped).
  Future<void> refresh({bool isInitial = false, bool force = false}) async {
    if (!_alive) return;
    // While mutating, skip soft polls unless forced reconcile.
    if (!force && state.isMutating) return;

    final seq = ++_fetchSeq;
    if (!isInitial && state.ride != null && _alive) {
      state = state.copyWith(isRefreshing: true);
    }

    try {
      final ride = await _getRide(rideId);
      if (!_alive || seq != _fetchSeq) return;
      if (!shouldAcceptRideSnapshot(ride, state.ride)) {
        if (_alive && seq == _fetchSeq) {
          state = state.copyWith(isRefreshing: false);
        }
        return;
      }
      _applyRide(ride, softError: false);
    } catch (error, stack) {
      if (!_alive || seq != _fetchSeq) return;
      final failure = _failures.fromException(error, stack);
      final isUnauthorized = failure.maybeWhen(
        unauthorized: (_) => true,
        orElse: () => false,
      );
      if (state.ride == null || isUnauthorized) {
        // M10: 401 must not leave a misleading active surface.
        state = state.copyWith(
          phase: ActiveRidePhase.fatalError,
          errorMessage: failure.userMessage,
          isRefreshing: false,
          isPolling: false,
          isCancelling: false,
          isClosing: false,
          connectivityDegraded: true,
        );
        _terminalStopped = true;
        _pollTimer?.cancel();
        _pollTimer = null;
      } else {
        state = state.copyWith(
          isRefreshing: false,
          connectivityDegraded: true,
          infoMessage:
              'Connection interrupted — updating when connection returns.',
        );
      }
    }
  }

  void _applyRide(Ride ride, {required bool softError}) {
    if (!_alive) return;

    final terminal = isActiveRideTerminalState(ride.state);
    final mutating = state.isMutating;
    final rideUnchanged = isRideUiEquivalent(state.ride, ride);

    // H1: while cancel/close in flight, do not clear mutation flags.
    if (mutating && !terminal) {
      if (rideUnchanged && !state.isRefreshing && softError == false) {
        _ensureClock();
        return;
      }
      state = state.copyWith(
        ride: rideUnchanged ? state.ride : ride,
        isRefreshing: false,
        connectivityDegraded: softError ? state.connectivityDegraded : false,
        clearError: true,
        clearInfo: softError ? false : true,
      );
      _ensureClock();
      return;
    }

    final nextPhase = terminal
        ? ActiveRidePhase.ended
        : (mutating ? ActiveRidePhase.mutating : ActiveRidePhase.active);

    final flagsUnchanged = !state.isRefreshing &&
        state.phase == nextPhase &&
        (mutating
            ? true
            : (!state.isCancelling && !state.isClosing)) &&
        (softError
            ? true
            : (!state.connectivityDegraded &&
                state.errorMessage == null &&
                state.infoMessage == null));

    if (rideUnchanged && flagsUnchanged && !terminal) {
      _ensureClock();
      return;
    }

    state = state.copyWith(
      phase: nextPhase,
      ride: rideUnchanged ? state.ride : ride,
      isRefreshing: false,
      isCancelling: mutating ? state.isCancelling : false,
      isClosing: mutating ? state.isClosing : false,
      connectivityDegraded: softError ? state.connectivityDegraded : false,
      clearError: true,
      clearInfo: softError ? false : true,
    );

    if (terminal) {
      state = state.copyWith(
        isPolling: false,
        isCancelling: false,
        isClosing: false,
        phase: ActiveRidePhase.ended,
      );
      _terminalStopped = true;
      _pollTimer?.cancel();
      _pollTimer = null;
    }

    _ensureClock();
  }

  void _scheduleNext() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (!_maySchedulePoll) return;
    final ride = state.ride;
    if (ride != null && isActiveRideTerminalState(ride.state)) return;
    if (state.isMutating) return;

    final started = _startedAt;
    if (started != null &&
        DateTime.now().difference(started) >= _policy.maxLifetime) {
      if (_alive) {
        state = state.copyWith(
          isPolling: false,
          infoMessage:
              'Stopped automatic updates. Pull to refresh for the latest status.',
        );
      }
      _lifetimeExpired = true;
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }

    final baseAttempt = ride?.state.toUpperCase() == 'RIDE_COMPLETED'
        ? _policy.intervals.length - 1
        : _attempt;
    final delay = _policy.delayForAttempt(baseAttempt);
    _pollTimer = Timer(delay, () async {
      if (!_maySchedulePoll) return;
      if (state.isMutating) {
        _scheduleNext();
        return;
      }
      _attempt += 1;
      await refresh();
      _scheduleNext();
    });
  }

  void _tickClock() {
    if (!_alive) return;
    arrivedNow.value = DateTime.now();
  }

  void _ensureClock() {
    if (_paused || !_alive) {
      _clockTimer?.cancel();
      _clockTimer = null;
      return;
    }
    final needsClock =
        state.ride?.state.toUpperCase() == 'DRIVER_ARRIVED' &&
            state.ride?.arrivedAt != null;
    if (!needsClock) {
      _clockTimer?.cancel();
      _clockTimer = null;
      return;
    }
    if (_clockTimer != null) return;
    _tickClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_alive || _paused) return;
      if (state.ride?.state.toUpperCase() != 'DRIVER_ARRIVED') {
        _clockTimer?.cancel();
        _clockTimer = null;
        return;
      }
      _tickClock();
    });
  }

  Future<void> cancel({String? reason}) async {
    if (!_alive) return;
    final ride = state.ride;
    if (ride == null || !passengerCanCancel(ride.state)) return;
    if (state.isMutating) return;

    final gen = ++_mutationGen;
    _cancelOpKey ??= 'ride:cancel:$rideId:${const Uuid().v4()}';
    state = state.copyWith(
      phase: ActiveRidePhase.mutating,
      isCancelling: true,
      clearError: true,
      clearInfo: true,
    );
    _pollTimer?.cancel();
    _pollTimer = null;

    try {
      final updated = await _cancelRide(
        rideId: rideId,
        reason: reason,
        operationKey: _cancelOpKey!,
      );
      if (!_alive || gen != _mutationGen) return;
      if (shouldAcceptRideSnapshot(updated, state.ride)) {
        state = state.copyWith(isCancelling: false, isClosing: false);
        _applyRide(updated, softError: false);
      } else {
        state = state.copyWith(isCancelling: false, isClosing: false);
        await refresh(force: true);
      }
    } catch (error, stack) {
      if (!_alive || gen != _mutationGen) return;
      await _handleMutationFailure(
        _failures.fromException(error, stack),
        wasCancel: true,
      );
    } finally {
      if (_alive && gen == _mutationGen && state.isCancelling) {
        state = state.copyWith(
          isCancelling: false,
          phase: state.ride != null &&
                  isActiveRideTerminalState(state.ride!.state)
              ? ActiveRidePhase.ended
              : ActiveRidePhase.active,
        );
        if (!_lifetimeExpired && !_terminalStopped) {
          _scheduleNext();
        }
      }
    }
  }

  Future<void> closeRide() async {
    if (!_alive) return;
    final ride = state.ride;
    if (ride == null || !passengerCanClose(ride.state)) return;
    if (state.isMutating) return;

    final gen = ++_mutationGen;
    _closeOpKey ??= 'ride:close:$rideId:${const Uuid().v4()}';
    state = state.copyWith(
      phase: ActiveRidePhase.mutating,
      isClosing: true,
      clearError: true,
      clearInfo: true,
    );
    _pollTimer?.cancel();
    _pollTimer = null;

    try {
      final updated = await _closeRide(
        rideId: rideId,
        expectedVersion: ride.version,
        operationKey: _closeOpKey!,
      );
      if (!_alive || gen != _mutationGen) return;
      if (shouldAcceptRideSnapshot(updated, state.ride)) {
        state = state.copyWith(isCancelling: false, isClosing: false);
        _applyRide(updated, softError: false);
      } else {
        state = state.copyWith(isCancelling: false, isClosing: false);
        await refresh(force: true);
      }
    } catch (error, stack) {
      if (!_alive || gen != _mutationGen) return;
      await _handleMutationFailure(
        _failures.fromException(error, stack),
        wasCancel: false,
      );
    } finally {
      if (_alive && gen == _mutationGen && state.isClosing) {
        state = state.copyWith(
          isClosing: false,
          phase: state.ride != null &&
                  isActiveRideTerminalState(state.ride!.state)
              ? ActiveRidePhase.ended
              : ActiveRidePhase.active,
        );
        if (!_lifetimeExpired && !_terminalStopped) {
          _scheduleNext();
        }
      }
    }
  }

  Future<void> _handleMutationFailure(
    AppFailure failure, {
    required bool wasCancel,
  }) async {
    final code = failure.maybeWhen(
      conflict: (message, code) => code,
      orElse: () => null,
    );

    final definitive = code == 'VERSION_CONFLICT' ||
        code == 'STATE_CONFLICT' ||
        code == 'ALREADY_ASSIGNED' ||
        code == 'IDEMPOTENCY_KEY_REUSED';

    if (definitive) {
      if (wasCancel) {
        final old = _cancelOpKey;
        _cancelOpKey = null;
        if (old != null) unawaited(_nonceStore.clear(old));
      } else {
        final old = _closeOpKey;
        _closeOpKey = null;
        if (old != null) unawaited(_nonceStore.clear(old));
      }
    }

    // Keep mutating until reconcile completes.
    if (_alive) {
      state = state.copyWith(
        errorMessage: definitive ? null : failure.userMessage,
        infoMessage: definitive ? failure.userMessage : null,
        clearError: definitive,
        clearInfo: !definitive,
      );
    }

    await refresh(force: true);

    if (!_alive) return;

    state = state.copyWith(
      isCancelling: false,
      isClosing: false,
      phase: state.ride != null && isActiveRideTerminalState(state.ride!.state)
          ? ActiveRidePhase.ended
          : ActiveRidePhase.active,
    );

    if (definitive && _alive) {
      state = state.copyWith(
        infoMessage: failure.userMessage,
        clearError: true,
      );
    }

    if (!_lifetimeExpired && !_terminalStopped) {
      _scheduleNext();
    }
  }

  void _disposeTimers() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _clockTimer?.cancel();
    _clockTimer = null;
    _paused = true;
  }
}

final activeRidePollingPolicyProvider = Provider<ActiveRidePollingPolicy>(
  (ref) => const ActiveRidePollingPolicy(),
);

final activeRideViewModelProvider = NotifierProvider.autoDispose
    .family<ActiveRideViewModel, ActiveRideUiState, String>(
  ActiveRideViewModel.new,
);
