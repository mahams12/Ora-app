import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/di/providers.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../../../core/notifications/ride_fcm_nudge.dart';
import '../../../../core/storage/idempotency_nonce_store.dart';
import '../../../ride/domain/entities/ride.dart';
import '../../../ride/domain/repositories/ride_repository.dart';
import '../../../ride/domain/use_cases/ride_use_cases.dart';
import '../../../ride/presentation/active_ride/active_ride_display.dart';
import '../../../ride/presentation/view_models/active_ride_view_model.dart';
import '../driver_display.dart';

enum DriverAssignedRidePhase {
  initialLoading,
  active,
  mutating,
  ended,
  fatalError,
}

enum DriverRideMutation {
  enRoute,
  arrive,
  start,
  complete,
  cancel,
  close,
  // Ora Courier — exception + return mutations.
  failDelivery,
  retryDelivery,
  startReturn,
  completeReturn,
  // Ora Courier v2 — code-free stop + settlement mutations.
  stopArrive,
  stopConfirm,
  stopFail,
  stopQuote,
  settle,
}

class DriverAssignedRideUiState {
  const DriverAssignedRideUiState({
    this.phase = DriverAssignedRidePhase.initialLoading,
    this.ride,
    this.isRefreshing = false,
    this.isPolling = false,
    this.activeMutation,
    this.errorMessage,
    this.infoMessage,
    this.connectivityDegraded = false,
  });

  final DriverAssignedRidePhase phase;
  final Ride? ride;
  final bool isRefreshing;
  final bool isPolling;
  final DriverRideMutation? activeMutation;
  final String? errorMessage;
  final String? infoMessage;
  final bool connectivityDegraded;

  String get rideState => ride?.state ?? '';

  bool get isMutating => activeMutation != null;

  bool get canEnRoute =>
      ride != null &&
      driverCanEnRoute(ride!.state) &&
      !isMutating &&
      phase != DriverAssignedRidePhase.mutating;

  bool get canArrive =>
      ride != null &&
      driverCanArrive(ride!.state) &&
      !isMutating &&
      phase != DriverAssignedRidePhase.mutating;

  bool get canStart =>
      ride != null &&
      driverCanStart(ride!.state) &&
      !isMutating &&
      phase != DriverAssignedRidePhase.mutating;

  bool get canComplete =>
      ride != null &&
      driverCanComplete(ride!.state) &&
      !isMutating &&
      phase != DriverAssignedRidePhase.mutating;

  bool get canCancel =>
      ride != null &&
      driverCanCancel(ride!.state, courier: ride!.isDelivery) &&
      !isMutating &&
      phase != DriverAssignedRidePhase.mutating;

  bool get canClose =>
      ride != null &&
      driverCanClose(ride!.state, courier: ride!.isDelivery) &&
      !isMutating &&
      phase != DriverAssignedRidePhase.mutating;

  // Ora Courier — exception actions.
  bool get canFailDelivery =>
      ride != null &&
      driverCanFailDelivery(ride!.state, courier: ride!.isDelivery) &&
      !isMutating &&
      phase != DriverAssignedRidePhase.mutating;

  bool get canRetryDelivery =>
      ride != null &&
      driverCanRetryDelivery(ride!.state, courier: ride!.isDelivery) &&
      !isMutating &&
      phase != DriverAssignedRidePhase.mutating;

  bool get canStartReturn =>
      ride != null &&
      driverCanStartReturn(ride!.state, courier: ride!.isDelivery) &&
      !isMutating &&
      phase != DriverAssignedRidePhase.mutating;

  bool get canConfirmReturn =>
      ride != null &&
      driverCanConfirmReturn(ride!.state, courier: ride!.isDelivery) &&
      !isMutating &&
      phase != DriverAssignedRidePhase.mutating;

  String? get primaryActionLabel {
    final ride = this.ride;
    if (ride == null) return null;
    if (ride.isCourierV2) {
      // v2 progression is per-stop — only the en-route leg uses the
      // primary button; the stop checklist carries the rest.
      return ride.state.toUpperCase() == 'DRIVER_ASSIGNED'
          ? 'Mark en route'
          : null;
    }
    return driverPrimaryActionLabel(
      ride.state,
      courier: ride.isDelivery,
    );
  }

  DriverAssignedRideUiState copyWith({
    DriverAssignedRidePhase? phase,
    Ride? ride,
    bool? isRefreshing,
    bool? isPolling,
    DriverRideMutation? activeMutation,
    String? errorMessage,
    String? infoMessage,
    bool? connectivityDegraded,
    bool clearMutation = false,
    bool clearError = false,
    bool clearInfo = false,
  }) {
    return DriverAssignedRideUiState(
      phase: phase ?? this.phase,
      ride: ride ?? this.ride,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isPolling: isPolling ?? this.isPolling,
      activeMutation:
          clearMutation ? null : (activeMutation ?? this.activeMutation),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      infoMessage: clearInfo ? null : (infoMessage ?? this.infoMessage),
      connectivityDegraded:
          connectivityDegraded ?? this.connectivityDegraded,
    );
  }
}

/// Driver assigned-job ViewModel — observes server state; never invents it.
class DriverAssignedRideViewModel
    extends AutoDisposeFamilyNotifier<DriverAssignedRideUiState, String> {
  late final GetRideUseCase _getRide;
  late final MarkEnRouteUseCase _markEnRoute;
  late final MarkArrivedUseCase _markArrived;
  late final StartRideUseCase _startRide;
  late final CompleteRideUseCase _completeRide;
  late final CancelRideUseCase _cancelRide;
  late final CloseRideUseCase _closeRide;
  late final FailDeliveryUseCase _failDelivery;
  late final RetryDeliveryUseCase _retryDelivery;
  late final StartReturnUseCase _startReturn;
  late final CompleteReturnUseCase _completeReturn;
  late final FailureMapper _failures;
  late final ActiveRidePollingPolicy _policy;
  late final IdempotencyNonceStore _nonceStore;
  late final RideRepository _repo;

  Timer? _pollTimer;
  Timer? _nudgeDebounce;
  bool _nudgePending = false;
  DateTime? _startedAt;
  bool _disposed = false;
  bool _paused = false;
  bool _lifetimeExpired = false;
  bool _terminalStopped = false;
  int _attempt = 0;
  String? _enRouteOpKey;
  String? _arriveOpKey;
  String? _startOpKey;
  String? _completeOpKey;
  String? _cancelOpKey;
  String? _closeOpKey;
  String? _failDeliveryOpKey;
  String? _retryDeliveryOpKey;
  String? _startReturnOpKey;
  String? _completeReturnOpKey;
  final Map<String, String> _v2OpKeys = {};
  int _fetchSeq = 0;
  int _mutationGen = 0;

  String get rideId => arg;

  bool get _alive => !_disposed;

  bool get _maySchedulePoll =>
      _alive && !_paused && !_lifetimeExpired && !_terminalStopped;

  @override
  DriverAssignedRideUiState build(String arg) {
    _getRide = ref.read(getRideUseCaseProvider);
    _markEnRoute = ref.read(markEnRouteUseCaseProvider);
    _markArrived = ref.read(markArrivedUseCaseProvider);
    _startRide = ref.read(startRideUseCaseProvider);
    _completeRide = ref.read(completeRideUseCaseProvider);
    _cancelRide = ref.read(cancelRideUseCaseProvider);
    _closeRide = ref.read(closeRideUseCaseProvider);
    _failDelivery = ref.read(failDeliveryUseCaseProvider);
    _retryDelivery = ref.read(retryDeliveryUseCaseProvider);
    _startReturn = ref.read(startReturnUseCaseProvider);
    _completeReturn = ref.read(completeReturnUseCaseProvider);
    _failures = ref.read(failureMapperProvider);
    _policy = ref.read(activeRidePollingPolicyProvider);
    _nonceStore = ref.read(idempotencyNonceStoreProvider);
    _repo = ref.read(rideRepositoryProvider);

    // NOTIF-RIDE-NUDGE: push ⇒ "poll now" hint for this ride only; HTTP
    // polling stays the authoritative fallback and is untouched.
    ref.listen<AsyncValue<RideFcmNudge>>(fcmRideNudgeProvider, (_, next) {
      final nudge = next.value;
      if (nudge == null || nudge.rideId != rideId) return;
      _onRideNudge();
    });

    ref.onDispose(() {
      _disposed = true;
      _disposeTimers();
    });

    Future.microtask(() {
      if (_alive) unawaited(start());
    });

    return const DriverAssignedRideUiState();
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
  }

  void pausePolling() {
    _paused = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_alive) {
      state = state.copyWith(isPolling: false);
    }
  }

  Future<void> resumePolling() async {
    if (!_alive) return;
    _paused = false;

    if (_lifetimeExpired) {
      await refresh(force: true);
      return;
    }

    if (_terminalStopped) {
      return;
    }

    state = state.copyWith(isPolling: true);
    await refresh();
    _scheduleNext();
  }

  /// Push nudge ⇒ one immediate refresh, then a short debounce window that
  /// collapses FCM bursts into at most one extra fetch. [refresh]'s own
  /// guards keep mutation/disposal safety; works while paused (push is the
  /// wake signal) and never schedules or mutates polling.
  static const Duration nudgeDebounceWindow = Duration(milliseconds: 500);

  void _onRideNudge() {
    if (!_alive) return;
    if (_nudgeDebounce != null) {
      _nudgePending = true;
      return;
    }
    _nudgeDebounce = Timer(nudgeDebounceWindow, () {
      _nudgeDebounce = null;
      if (!_nudgePending) return;
      _nudgePending = false;
      if (_alive) unawaited(refresh());
    });
    unawaited(refresh());
  }

  /// [force] used for post-mutation reconciliation (never dropped).
  Future<void> refresh({bool isInitial = false, bool force = false}) async {
    if (!_alive) return;
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
        state = state.copyWith(
          phase: DriverAssignedRidePhase.fatalError,
          errorMessage: failure.userMessage,
          isRefreshing: false,
          isPolling: false,
          clearMutation: true,
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

    final terminal = isDriverJobTerminalState(ride.state);
    final mutating = state.isMutating;
    final rideUnchanged = isRideUiEquivalent(state.ride, ride);

    if (mutating && !terminal) {
      if (rideUnchanged && !state.isRefreshing && softError == false) {
        return;
      }
      state = state.copyWith(
        ride: rideUnchanged ? state.ride : ride,
        isRefreshing: false,
        connectivityDegraded: softError ? state.connectivityDegraded : false,
        clearError: true,
        clearInfo: softError ? false : true,
      );
      return;
    }

    final nextPhase = terminal
        ? DriverAssignedRidePhase.ended
        : (mutating
            ? DriverAssignedRidePhase.mutating
            : DriverAssignedRidePhase.active);

    final flagsUnchanged = !state.isRefreshing &&
        state.phase == nextPhase &&
        (mutating ? true : state.activeMutation == null) &&
        (softError
            ? true
            : (!state.connectivityDegraded &&
                state.errorMessage == null &&
                state.infoMessage == null));

    if (rideUnchanged && flagsUnchanged && !terminal) {
      return;
    }

    state = state.copyWith(
      phase: nextPhase,
      ride: rideUnchanged ? state.ride : ride,
      isRefreshing: false,
      clearMutation: !mutating,
      connectivityDegraded: softError ? state.connectivityDegraded : false,
      clearError: true,
      clearInfo: softError ? false : true,
    );

    if (terminal) {
      state = state.copyWith(
        isPolling: false,
        clearMutation: true,
        phase: DriverAssignedRidePhase.ended,
      );
      _terminalStopped = true;
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  void _scheduleNext() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (!_maySchedulePoll) return;
    final ride = state.ride;
    if (ride != null && isDriverJobTerminalState(ride.state)) return;
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

  /// Runs the primary lifecycle action for the current state. For courier
  /// OTP-gated transitions (pickup/delivery/return) the view must call the
  /// OTP methods directly after collecting the code — the primary button
  /// opens the code sheet instead.
  Future<void> runPrimaryAction() async {
    final ride = state.ride;
    if (ride == null || state.isMutating) return;
    final s = ride.state.toUpperCase();
    if (ride.isCourierV2) {
      // v2 progression is per-stop — the stop checklist carries the
      // arrive/confirm/fail buttons; here we only handle the en-route leg.
      if (s == 'DRIVER_ASSIGNED') await markEnRoute();
      return;
    }
    if (s == 'DRIVER_ASSIGNED') {
      await markEnRoute();
    } else if (s == 'DRIVER_EN_ROUTE') {
      await markArrived();
    } else if (!ride.isCourier && s == 'DRIVER_ARRIVED') {
      await startRide();
    } else if (!ride.isCourier && s == 'RIDE_STARTED') {
      await completeRide();
    }
  }

  Future<void> markEnRoute() => _runMutation(
        kind: DriverRideMutation.enRoute,
        allowed: (ride) => driverCanEnRoute(ride.state),
        opKey: () {
          _enRouteOpKey ??= 'ride:en_route:$rideId:${const Uuid().v4()}';
          return _enRouteOpKey!;
        },
        clearOpKey: () {
          final old = _enRouteOpKey;
          _enRouteOpKey = null;
          return old;
        },
        call: (ride, key) => _markEnRoute(
          rideId: rideId,
          expectedVersion: ride.version,
          operationKey: key,
        ),
      );

  Future<void> markArrived() => _runMutation(
        kind: DriverRideMutation.arrive,
        allowed: (ride) => driverCanArrive(ride.state),
        opKey: () {
          _arriveOpKey ??= 'ride:arrived:$rideId:${const Uuid().v4()}';
          return _arriveOpKey!;
        },
        clearOpKey: () {
          final old = _arriveOpKey;
          _arriveOpKey = null;
          return old;
        },
        call: (ride, key) => _markArrived(
          rideId: rideId,
          expectedVersion: ride.version,
          operationKey: key,
        ),
      );

  Future<void> startRide({String? otp, String? pickupPhotoUrl}) =>
      _runMutation(
        kind: DriverRideMutation.start,
        allowed: (ride) => driverCanStart(ride.state),
        opKey: () {
          _startOpKey ??= 'ride:start:$rideId:${const Uuid().v4()}';
          return _startOpKey!;
        },
        clearOpKey: () {
          final old = _startOpKey;
          _startOpKey = null;
          return old;
        },
        call: (ride, key) => _startRide(
          rideId: rideId,
          expectedVersion: ride.version,
          otp: otp,
          pickupPhotoUrl: pickupPhotoUrl,
          operationKey: key,
        ),
      );

  Future<void> completeRide({String? otp}) => _runMutation(
        kind: DriverRideMutation.complete,
        allowed: (ride) => driverCanComplete(ride.state),
        opKey: () {
          _completeOpKey ??= 'ride:complete:$rideId:${const Uuid().v4()}';
          return _completeOpKey!;
        },
        clearOpKey: () {
          final old = _completeOpKey;
          _completeOpKey = null;
          return old;
        },
        call: (ride, key) => _completeRide(
          rideId: rideId,
          expectedVersion: ride.version,
          otp: otp,
          operationKey: key,
        ),
      );

  Future<void> cancel({String? reason}) => _runMutation(
        kind: DriverRideMutation.cancel,
        allowed: (ride) =>
            driverCanCancel(ride.state, courier: ride.isDelivery),
        opKey: () {
          _cancelOpKey ??= 'ride:cancel:$rideId:${const Uuid().v4()}';
          return _cancelOpKey!;
        },
        clearOpKey: () {
          final old = _cancelOpKey;
          _cancelOpKey = null;
          return old;
        },
        call: (ride, key) => _cancelRide(
          rideId: rideId,
          reason: reason,
          operationKey: key,
        ),
      );

  Future<void> closeRide() => _runMutation(
        kind: DriverRideMutation.close,
        allowed: (ride) =>
            driverCanClose(ride.state, courier: ride.isDelivery),
        opKey: () {
          _closeOpKey ??= 'ride:close:$rideId:${const Uuid().v4()}';
          return _closeOpKey!;
        },
        clearOpKey: () {
          final old = _closeOpKey;
          _closeOpKey = null;
          return old;
        },
        call: (ride, key) => _closeRide(
          rideId: rideId,
          expectedVersion: ride.version,
          operationKey: key,
        ),
      );

  // ── Ora Courier — exception + return mutations ──────────────────────────

  Future<void> failDelivery({required String reason}) => _runMutation(
        kind: DriverRideMutation.failDelivery,
        allowed: (ride) =>
            driverCanFailDelivery(ride.state, courier: ride.isDelivery),
        opKey: () {
          _failDeliveryOpKey ??=
              'ride:delivery_fail:$rideId:${const Uuid().v4()}';
          return _failDeliveryOpKey!;
        },
        clearOpKey: () {
          final old = _failDeliveryOpKey;
          _failDeliveryOpKey = null;
          return old;
        },
        call: (ride, key) => _failDelivery(
          rideId: rideId,
          expectedVersion: ride.version,
          reason: reason,
          operationKey: key,
        ),
      );

  Future<void> retryDelivery() => _runMutation(
        kind: DriverRideMutation.retryDelivery,
        allowed: (ride) =>
            driverCanRetryDelivery(ride.state, courier: ride.isDelivery),
        opKey: () {
          _retryDeliveryOpKey ??=
              'ride:delivery_retry:$rideId:${const Uuid().v4()}';
          return _retryDeliveryOpKey!;
        },
        clearOpKey: () {
          final old = _retryDeliveryOpKey;
          _retryDeliveryOpKey = null;
          return old;
        },
        call: (ride, key) => _retryDelivery(
          rideId: rideId,
          expectedVersion: ride.version,
          operationKey: key,
        ),
      );

  Future<void> startReturn() => _runMutation(
        kind: DriverRideMutation.startReturn,
        allowed: (ride) =>
            driverCanStartReturn(ride.state, courier: ride.isDelivery),
        opKey: () {
          _startReturnOpKey ??=
              'ride:return_start:$rideId:${const Uuid().v4()}';
          return _startReturnOpKey!;
        },
        clearOpKey: () {
          final old = _startReturnOpKey;
          _startReturnOpKey = null;
          return old;
        },
        call: (ride, key) => _startReturn(
          rideId: rideId,
          expectedVersion: ride.version,
          operationKey: key,
        ),
      );

  Future<void> completeReturn({String? otp}) => _runMutation(
        kind: DriverRideMutation.completeReturn,
        allowed: (ride) =>
            driverCanConfirmReturn(ride.state, courier: ride.isDelivery),
        opKey: () {
          _completeReturnOpKey ??=
              'ride:return_complete:$rideId:${const Uuid().v4()}';
          return _completeReturnOpKey!;
        },
        clearOpKey: () {
          final old = _completeReturnOpKey;
          _completeReturnOpKey = null;
          return old;
        },
        call: (ride, key) => _completeReturn(
          rideId: rideId,
          expectedVersion: ride.version,
          otp: otp,
          operationKey: key,
        ),
      );

  // ── Ora Courier v2 — code-free stop progression ───────────────────────

  bool _isV2Actionable(Ride ride) =>
      ride.isCourierV2 && !isDriverJobTerminalState(ride.state);

  String _v2OpKey(String purpose) => _v2OpKeys.putIfAbsent(
        purpose,
        () => 'ride:$purpose:$rideId:${const Uuid().v4()}',
      );

  /// Ora Courier v2 — next per-stop driver action for the current stop.
  /// Returns null when no stop action applies right now.
  String? v2PrimaryAction(Ride ride) {
    final stop = ride.currentStop;
    if (!_isV2Actionable(ride) || stop == null) return null;
    return switch (stop.status) {
      'PENDING' => 'arrive',
      'ARRIVED' =>
        stop.type == 'SHOP' && (stop.quote?.isEmpty ?? true) ? 'quote' : 'confirm',
      _ => null,
    };
  }

  /// Driver arrives at the current itinerary stop (any PICKUP/SHOP/DROPOFF).
  Future<void> arriveStop(int seq) => _runMutation(
        kind: DriverRideMutation.stopArrive,
        allowed: (ride) =>
            _isV2Actionable(ride) && ride.currentStop?.seq == seq,
        opKey: () => _v2OpKey('stop_arrive:$seq'),
        clearOpKey: () {
          final old = _v2OpKeys['stop_arrive:$seq'];
          _v2OpKeys.remove('stop_arrive:$seq');
          return old;
        },
        call: (ride, key) => _repo.arriveStop(
          rideId: rideId,
          seq: seq,
          expectedVersion: ride.version,
          operationKey: key,
        ),
      );

  /// Driver completes the current stop — PICKUP "collected", SHOP "purchased"
  /// (requires `purchaseTotalMinor` ≤ approved quote), DROPOFF "delivered".
  Future<void> confirmStop(int seq, {int? purchaseTotalMinor}) =>
      _runMutation(
        kind: DriverRideMutation.stopConfirm,
        allowed: (ride) => _isV2Actionable(ride),
        opKey: () => _v2OpKey('stop_confirm:$seq'),
        clearOpKey: () {
          final old = _v2OpKeys['stop_confirm:$seq'];
          _v2OpKeys.remove('stop_confirm:$seq');
          return old;
        },
        call: (ride, key) => _repo.confirmStop(
          rideId: rideId,
          seq: seq,
          expectedVersion: ride.version,
          purchaseTotalMinor: purchaseTotalMinor,
          operationKey: key,
        ),
      );

  /// Driver reports a failed stop — server enum reason; the itinerary may
  /// continue to remaining stops (partial fulfillment) or close out.
  Future<void> failStop(int seq, {required String reason}) => _runMutation(
        kind: DriverRideMutation.stopFail,
        allowed: (ride) => _isV2Actionable(ride),
        opKey: () => _v2OpKey('stop_fail:$seq'),
        clearOpKey: () {
          final old = _v2OpKeys['stop_fail:$seq'];
          _v2OpKeys.remove('stop_fail:$seq');
          return old;
        },
        call: (ride, key) => _repo.failStop(
          rideId: rideId,
          seq: seq,
          expectedVersion: ride.version,
          reason: reason,
          operationKey: key,
        ),
      );

  /// buy_deliver — driver submits an itemized quote on an arrived SHOP stop;
  /// the customer must approve before the purchase can be confirmed.
  Future<void> submitStopQuote(
    int seq,
    List<Map<String, Object?>> items,
  ) =>
      _runMutation(
        kind: DriverRideMutation.stopQuote,
        allowed: (ride) => _isV2Actionable(ride),
        opKey: () => _v2OpKey('stop_quote:$seq'),
        clearOpKey: () {
          final old = _v2OpKeys['stop_quote:$seq'];
          _v2OpKeys.remove('stop_quote:$seq');
          return old;
        },
        call: (ride, key) => _repo.submitStopQuote(
          rideId: rideId,
          seq: seq,
          expectedVersion: ride.version,
          items: items,
          operationKey: key,
        ),
      );

  /// Ora Courier v2 — driver-reported cash collection (PAID/UNPAID/PARTIAL);
  /// never presented as platform-verified payment.
  Future<void> reportSettlement(String status) => _runMutation(
        kind: DriverRideMutation.settle,
        allowed: _isV2Actionable,
        opKey: () => _v2OpKey('settlement'),
        clearOpKey: () {
          final old = _v2OpKeys['settlement'];
          _v2OpKeys.remove('settlement');
          return old;
        },
        call: (ride, key) => _repo.reportSettlement(
          rideId: rideId,
          expectedVersion: ride.version,
          status: status,
          operationKey: key,
        ),
      );

  Future<void> _runMutation({
    required DriverRideMutation kind,
    required bool Function(Ride ride) allowed,
    required String Function() opKey,
    required String? Function() clearOpKey,
    required Future<Ride> Function(Ride ride, String key) call,
  }) async {
    if (!_alive) return;
    final ride = state.ride;
    if (ride == null || !allowed(ride)) return;
    if (state.isMutating) return;

    final gen = ++_mutationGen;
    final key = opKey();
    state = state.copyWith(
      phase: DriverAssignedRidePhase.mutating,
      activeMutation: kind,
      clearError: true,
      clearInfo: true,
    );
    _pollTimer?.cancel();
    _pollTimer = null;

    try {
      final updated = await call(ride, key);
      if (!_alive || gen != _mutationGen) return;
      if (shouldAcceptRideSnapshot(updated, state.ride)) {
        state = state.copyWith(clearMutation: true);
        _applyRide(updated, softError: false);
      } else {
        state = state.copyWith(clearMutation: true);
        await refresh(force: true);
      }
    } catch (error, stack) {
      if (!_alive || gen != _mutationGen) return;
      await _handleMutationFailure(
        _failures.fromException(error, stack),
        clearOpKey: clearOpKey,
      );
    } finally {
      if (_alive && gen == _mutationGen && state.activeMutation == kind) {
        state = state.copyWith(
          clearMutation: true,
          phase: state.ride != null &&
                  isDriverJobTerminalState(state.ride!.state)
              ? DriverAssignedRidePhase.ended
              : DriverAssignedRidePhase.active,
        );
        if (!_lifetimeExpired && !_terminalStopped) {
          _scheduleNext();
        }
      }
    }
  }

  Future<void> _handleMutationFailure(
    AppFailure failure, {
    required String? Function() clearOpKey,
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
      final old = clearOpKey();
      if (old != null) unawaited(_nonceStore.clear(old));
    }

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
      clearMutation: true,
      phase: state.ride != null && isDriverJobTerminalState(state.ride!.state)
          ? DriverAssignedRidePhase.ended
          : DriverAssignedRidePhase.active,
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
    _nudgeDebounce?.cancel();
    _nudgeDebounce = null;
    _nudgePending = false;
    _paused = true;
  }
}

final driverAssignedRideViewModelProvider = NotifierProvider.autoDispose
    .family<DriverAssignedRideViewModel, DriverAssignedRideUiState, String>(
  DriverAssignedRideViewModel.new,
);
