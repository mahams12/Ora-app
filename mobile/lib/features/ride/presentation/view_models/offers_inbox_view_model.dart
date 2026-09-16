import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/di/providers.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../../../core/storage/idempotency_nonce_store.dart';
import '../../domain/entities/ride.dart';
import '../../domain/use_cases/ride_use_cases.dart';
import '../active_ride/active_ride_display.dart'
    show
        areOfferListsUiEquivalent,
        isRideUiEquivalent,
        shouldAcceptRideSnapshot;
import '../offers/offer_display.dart';

/// Bounded HTTP polling for the offers inbox (no FCM / Firestore listeners).
class OfferPollingPolicy {
  const OfferPollingPolicy({
    this.intervals = const [
      Duration(seconds: 2),
      Duration(seconds: 3),
      Duration(seconds: 5),
    ],
    this.maxLifetime = const Duration(minutes: 6),
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

enum OffersInboxPhase {
  initialLoading,
  ready,
  selecting,
  assigned,
  terminal,
  fatalError,
}

class OffersInboxUiState {
  const OffersInboxUiState({
    this.phase = OffersInboxPhase.initialLoading,
    this.ride,
    this.offers = const [],
    this.isRefreshing = false,
    this.isPolling = false,
    this.selectingOfferId,
    this.assignment,
    this.errorMessage,
    this.infoMessage,
  });

  final OffersInboxPhase phase;
  final Ride? ride;
  final List<RideOffer> offers;
  final bool isRefreshing;
  final bool isPolling;
  final String? selectingOfferId;
  final RideAssignment? assignment;
  final String? errorMessage;
  final String? infoMessage;

  String get rideId => ride?.rideId ?? '';

  String get rideState => ride?.state ?? '';

  bool get canRefresh =>
      phase != OffersInboxPhase.selecting &&
      phase != OffersInboxPhase.initialLoading;

  List<RideOffer> get pendingOffers =>
      offers.where(isOfferSelectable).toList(growable: false);

  OffersInboxUiState copyWith({
    OffersInboxPhase? phase,
    Ride? ride,
    List<RideOffer>? offers,
    bool? isRefreshing,
    bool? isPolling,
    String? selectingOfferId,
    RideAssignment? assignment,
    String? errorMessage,
    String? infoMessage,
    bool clearSelecting = false,
    bool clearError = false,
    bool clearInfo = false,
    bool clearAssignment = false,
  }) {
    return OffersInboxUiState(
      phase: phase ?? this.phase,
      ride: ride ?? this.ride,
      offers: offers ?? this.offers,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isPolling: isPolling ?? this.isPolling,
      selectingOfferId:
          clearSelecting ? null : (selectingOfferId ?? this.selectingOfferId),
      assignment: clearAssignment ? null : (assignment ?? this.assignment),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      infoMessage: clearInfo ? null : (infoMessage ?? this.infoMessage),
    );
  }
}

/// Passenger offers inbox — polls GET ride + GET offers; selects via use case.
class OffersInboxViewModel
    extends AutoDisposeFamilyNotifier<OffersInboxUiState, String> {
  late final GetRideUseCase _getRide;
  late final ListOffersUseCase _listOffers;
  late final SelectOfferUseCase _selectOffer;
  late final FailureMapper _failures;
  late final OfferPollingPolicy _policy;
  late final IdempotencyNonceStore _nonceStore;

  Timer? _timer;
  DateTime? _startedAt;
  bool _paused = false;
  bool _disposed = false;
  bool _lifetimeExpired = false;
  bool _terminalStopped = false;
  int _attempt = 0;
  int _fetchSeq = 0;
  final Map<String, String> _selectOperationKeys = {};

  String get rideId => arg;

  bool get _alive => !_disposed;

  bool get _maySchedulePoll =>
      _alive && !_paused && !_lifetimeExpired && !_terminalStopped;

  @override
  OffersInboxUiState build(String arg) {
    _getRide = ref.read(getRideUseCaseProvider);
    _listOffers = ref.read(listOffersUseCaseProvider);
    _selectOffer = ref.read(selectOfferUseCaseProvider);
    _failures = ref.read(failureMapperProvider);
    _policy = ref.read(offerPollingPolicyProvider);
    _nonceStore = ref.read(idempotencyNonceStoreProvider);

    ref.onDispose(() {
      _disposed = true;
      _disposePolling();
    });

    Future.microtask(() {
      if (_alive) unawaited(start());
    });

    return const OffersInboxUiState();
  }

  Future<void> start() async {
    if (!_alive) return;
    _lifetimeExpired = false;
    _terminalStopped = false;
    _paused = false;
    _startedAt ??= DateTime.now();
    state = state.copyWith(isPolling: true, clearError: true);
    await refresh(isInitial: state.ride == null && state.offers.isEmpty);
    _scheduleNext();
  }

  void pausePolling() {
    _paused = true;
    _timer?.cancel();
    _timer = null;
    if (_alive) {
      state = state.copyWith(isPolling: false);
    }
  }

  Future<void> resumePolling() async {
    if (!_alive) return;
    _paused = false;

    // M2: after max lifetime, one-shot refresh only — do not restart loop.
    if (_lifetimeExpired) {
      await refresh(force: true);
      return;
    }

    if (_terminalStopped) return;

    state = state.copyWith(isPolling: true);
    await refresh();
    _scheduleNext();
  }

  /// [force] bypasses the selecting-phase refresh block (post-mutation reconcile).
  Future<void> refresh({bool isInitial = false, bool force = false}) async {
    if (!_alive) return;
    if (!force && state.phase == OffersInboxPhase.selecting) return;

    final seq = ++_fetchSeq;
    if (!isInitial && state.ride != null && _alive) {
      state = state.copyWith(isRefreshing: true, clearError: true);
    }

    try {
      // K-P1-03: overlap ride + offers GETs; apply as one seq-gated pair.
      final results = await Future.wait<Object>([
        _getRide(rideId),
        _listOffers(rideId),
      ]);
      if (!_alive || seq != _fetchSeq) return;
      final ride = results[0] as Ride;
      final offers = mergeOffersById(results[1] as List<RideOffer>);
      if (!shouldAcceptRideSnapshot(ride, state.ride)) {
        if (_alive && seq == _fetchSeq) {
          state = state.copyWith(isRefreshing: false);
        }
        return;
      }
      _applyServerSnapshot(ride: ride, offers: offers);
    } catch (error, stack) {
      if (!_alive || seq != _fetchSeq) return;
      final failure = _failures.fromException(error, stack);
      final isUnauthorized = failure.maybeWhen(
        unauthorized: (_) => true,
        orElse: () => false,
      );
      // M10: 401 must not leave a misleading active offers surface.
      if (state.ride == null || isUnauthorized) {
        state = state.copyWith(
          phase: OffersInboxPhase.fatalError,
          errorMessage: failure.userMessage,
          isRefreshing: false,
          isPolling: false,
          clearSelecting: true,
        );
        _terminalStopped = true;
        _timer?.cancel();
        _timer = null;
      } else {
        state = state.copyWith(
          isRefreshing: false,
          infoMessage: failure.userMessage,
        );
      }
    }
  }

  void _applyServerSnapshot({
    required Ride ride,
    required List<RideOffer> offers,
  }) {
    if (!_alive) return;

    final rideSame = isRideUiEquivalent(state.ride, ride);
    final offersSame = areOfferListsUiEquivalent(state.offers, offers);

    // C2: while selecting, never drop back to ready — but honor terminal/assigned.
    if (state.phase == OffersInboxPhase.selecting) {
      if (isTerminalRideState(ride.state)) {
        state = state.copyWith(
          phase: OffersInboxPhase.terminal,
          ride: rideSame ? state.ride : ride,
          offers: offersSame ? state.offers : offers,
          isRefreshing: false,
          isPolling: false,
          clearSelecting: true,
          clearError: true,
          clearInfo: true,
        );
        _markTerminalStopped();
        return;
      }
      if (isAssignedOrBeyond(ride.state)) {
        _applyAssigned(ride, offers);
        return;
      }
      if (rideSame && offersSame && !state.isRefreshing) {
        return;
      }
      state = state.copyWith(
        ride: rideSame ? state.ride : ride,
        offers: offersSame ? state.offers : offers,
        isRefreshing: false,
        clearError: true,
        clearInfo: true,
      );
      return;
    }

    if (isTerminalRideState(ride.state)) {
      state = state.copyWith(
        phase: OffersInboxPhase.terminal,
        ride: rideSame ? state.ride : ride,
        offers: offersSame ? state.offers : offers,
        isRefreshing: false,
        isPolling: false,
        clearSelecting: true,
        clearError: true,
        clearInfo: true,
      );
      _markTerminalStopped();
      return;
    }

    if (isAssignedOrBeyond(ride.state)) {
      _applyAssigned(ride, offers);
      return;
    }

    if (state.assignment != null && state.phase == OffersInboxPhase.assigned) {
      if (rideSame && offersSame && !state.isRefreshing) {
        return;
      }
      state = state.copyWith(
        ride: rideSame ? state.ride : ride,
        offers: offersSame ? state.offers : offers,
        isRefreshing: false,
        isPolling: false,
        clearSelecting: true,
        clearInfo: true,
      );
      _markTerminalStopped();
      return;
    }

    // Ready marketplace — skip notify when nothing UI-relevant changed.
    if (state.phase == OffersInboxPhase.ready &&
        rideSame &&
        offersSame &&
        !state.isRefreshing &&
        state.errorMessage == null &&
        state.infoMessage == null &&
        state.selectingOfferId == null) {
      return;
    }

    state = state.copyWith(
      phase: OffersInboxPhase.ready,
      ride: rideSame ? state.ride : ride,
      offers: offersSame ? state.offers : offers,
      isRefreshing: false,
      clearError: true,
      clearInfo: true,
      clearSelecting: true,
    );
  }

  void _applyAssigned(Ride ride, List<RideOffer> offers) {
    state = state.copyWith(
      phase: OffersInboxPhase.assigned,
      ride: ride,
      offers: offers,
      isRefreshing: false,
      isPolling: false,
      clearSelecting: true,
      clearError: true,
      clearInfo: true,
      assignment: state.assignment ??
          RideAssignment(
            rideId: ride.rideId,
            state: ride.state,
            version: ride.version,
            assignedDriverId: ride.assignedDriverId ?? '',
            agreedFareMinor: ride.agreedFareMinor ?? ride.passengerOfferMinor,
            agreedOfferId: ride.agreedOfferId ?? '',
            currency: ride.agreedFareCurrency ?? 'PKR',
          ),
    );
    _markTerminalStopped();
  }

  void _markTerminalStopped() {
    _terminalStopped = true;
    _timer?.cancel();
    _timer = null;
  }

  void _scheduleNext() {
    _timer?.cancel();
    _timer = null;
    if (!_maySchedulePoll) return;
    if (state.phase == OffersInboxPhase.assigned ||
        state.phase == OffersInboxPhase.terminal ||
        state.phase == OffersInboxPhase.fatalError ||
        state.phase == OffersInboxPhase.selecting) {
      return;
    }

    final started = _startedAt;
    if (started != null &&
        DateTime.now().difference(started) >= _policy.maxLifetime) {
      if (_alive) {
        state = state.copyWith(
          isPolling: false,
          infoMessage:
              'Stopped checking for new offers. Pull to refresh if you are still waiting.',
        );
      }
      _lifetimeExpired = true;
      _timer?.cancel();
      _timer = null;
      return;
    }

    final delay = _policy.delayForAttempt(_attempt);
    _timer = Timer(delay, () async {
      if (!_maySchedulePoll) return;
      if (state.phase == OffersInboxPhase.selecting) {
        _scheduleNext();
        return;
      }
      _attempt += 1;
      await refresh();
      _scheduleNext();
    });
  }

  Future<void> selectOffer(String offerId) async {
    if (!_alive) return;
    if (state.phase == OffersInboxPhase.selecting) return;
    final ride = state.ride;
    if (ride == null) return;
    RideOffer? offer;
    for (final o in state.offers) {
      if (o.offerId == offerId) {
        offer = o;
        break;
      }
    }
    if (offer == null || !isOfferSelectable(offer)) return;

    final opKey = _selectOperationKeys.putIfAbsent(
      offerId,
      () => 'offer:select:$rideId:$offerId:${const Uuid().v4()}',
    );

    // Pause poll scheduling while selecting (C2).
    _timer?.cancel();
    _timer = null;

    state = state.copyWith(
      phase: OffersInboxPhase.selecting,
      selectingOfferId: offerId,
      isPolling: false,
      clearError: true,
      clearInfo: true,
    );

    try {
      final assignment = await _selectOffer(
        rideId: rideId,
        offerId: offerId,
        expectedVersion: ride.version,
        operationKey: opKey,
      );
      if (!_alive) return;
      // K-P2-03: POST assignment is authoritative for assigned UI — skip
      // immediate force GET. Conflicts still force-reconcile below.
      state = state.copyWith(
        phase: OffersInboxPhase.assigned,
        assignment: assignment,
        clearSelecting: true,
        isPolling: false,
        isRefreshing: false,
        clearInfo: true,
      );
      _markTerminalStopped();
    } catch (error, stack) {
      if (!_alive) return;
      final failure = _failures.fromException(error, stack);
      await _handleSelectFailure(failure, offerId: offerId);
    }
  }

  Future<void> _handleSelectFailure(
    AppFailure failure, {
    required String offerId,
  }) async {
    final code = failure.maybeWhen(
      conflict: (message, code) => code,
      orElse: () => null,
    );

    final definitive = code == 'VERSION_CONFLICT' ||
        code == 'ALREADY_ASSIGNED' ||
        code == 'STATE_CONFLICT' ||
        code == 'IDEMPOTENCY_KEY_REUSED';

    if (definitive) {
      // C1: rotate key so next attempt is a new Idempotency-Key + body.
      final oldKey = _selectOperationKeys.remove(offerId);
      if (oldKey != null) {
        unawaited(_nonceStore.clear(oldKey));
      }
    }

    // M4: stay in selecting until reconcile completes (C2-safe).
    if (_alive) {
      state = state.copyWith(
        infoMessage: definitive ? failure.userMessage : null,
        errorMessage: definitive ? null : failure.userMessage,
        clearError: definitive,
        clearInfo: !definitive,
      );
    }

    await refresh(force: true);

    if (!_alive) return;

    // If still selecting after reconcile (marketplace), release to ready.
    if (state.phase == OffersInboxPhase.selecting) {
      state = state.copyWith(
        phase: OffersInboxPhase.ready,
        clearSelecting: true,
        infoMessage: definitive ? failure.userMessage : state.infoMessage,
        errorMessage: definitive ? null : failure.userMessage,
      );
      if (!_lifetimeExpired && !_terminalStopped) {
        state = state.copyWith(isPolling: true);
        _scheduleNext();
      }
    }
  }

  void clearMessages() {
    if (!_alive) return;
    state = state.copyWith(clearError: true, clearInfo: true);
  }

  void _disposePolling() {
    _timer?.cancel();
    _timer = null;
    _paused = true;
  }
}

final offerPollingPolicyProvider = Provider<OfferPollingPolicy>(
  (ref) => const OfferPollingPolicy(),
);

final offersInboxViewModelProvider = NotifierProvider.autoDispose
    .family<OffersInboxViewModel, OffersInboxUiState, String>(
  OffersInboxViewModel.new,
);
