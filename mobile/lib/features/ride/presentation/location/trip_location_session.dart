import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../domain/location/trip_location_freshness.dart';
import '../../domain/location/trip_location_listen_gate.dart';
import '../../domain/models/trip_location_latest.dart';
import '../../domain/ports/trip_location_port.dart';
import '../view_models/active_ride_view_model.dart';

/// UI-facing trip location session state (display-only).
class TripLocationSessionState {
  const TripLocationSessionState({
    this.latest,
    this.freshness = TripLocationFreshness.missing,
    this.isListening = false,
    this.isUnavailable = false,
    this.statusMessage,
    this.appliedSeq = 0,
    this.watchGeneration = 0,
  });

  final TripLocationLatest? latest;
  final TripLocationFreshness freshness;
  final bool isListening;
  final bool isUnavailable;
  final String? statusMessage;

  /// Highest applied locationSeq (0 = none).
  final int appliedSeq;

  /// Increments each time a new RTDB watch is started (test: no duplicates).
  final int watchGeneration;

  static const initial = TripLocationSessionState();

  TripLocationSessionState copyWith({
    TripLocationLatest? latest,
    bool clearLatest = false,
    TripLocationFreshness? freshness,
    bool? isListening,
    bool? isUnavailable,
    String? statusMessage,
    bool clearStatusMessage = false,
    int? appliedSeq,
    int? watchGeneration,
  }) {
    return TripLocationSessionState(
      latest: clearLatest ? null : (latest ?? this.latest),
      freshness: freshness ?? this.freshness,
      isListening: isListening ?? this.isListening,
      isUnavailable: isUnavailable ?? this.isUnavailable,
      statusMessage: clearStatusMessage
          ? null
          : (statusMessage ?? this.statusMessage),
      appliedSeq: appliedSeq ?? this.appliedSeq,
      watchGeneration: watchGeneration ?? this.watchGeneration,
    );
  }
}

/// AutoDispose family: one RTDB listener per rideId while state allows.
///
/// HTTP ride state remains authoritative. RTDB is display-only.
class TripLocationSession
    extends AutoDisposeFamilyNotifier<TripLocationSessionState, String> {
  // ignore: cancel_subscriptions — cancelled in _cancelWatch / onDispose
  StreamSubscription<TripLocationLatest?>? _sub;
  var _alive = true;
  var _appInForeground = true;
  var _watchHeld = false;
  String? _rideState;
  late TripLocationPort _port;
  late TripLocationFreshnessPolicy _freshnessPolicy;
  DateTime Function() _now = DateTime.now;
  Timer? _freshnessTimer;

  /// Test hook.
  int get activeSubscriptionCount => _sub == null ? 0 : 1;

  @override
  TripLocationSessionState build(String rideId) {
    _alive = true;
    _appInForeground = true;
    _watchHeld = false;
    _port = ref.read(tripLocationPortProvider);
    _freshnessPolicy = ref.read(tripLocationFreshnessPolicyProvider);
    _now = ref.read(tripLocationClockProvider);

    ref.onDispose(() {
      _alive = false;
      _cancelWatch();
      _freshnessTimer?.cancel();
      _freshnessTimer = null;
    });

    ref.listen<String?>(
      activeRideViewModelProvider(rideId).select((s) => s.ride?.state),
      (previous, next) {
        _rideState = next;
        _reconcile(rideId);
      },
    );

    Future<void>.microtask(() {
      if (!_alive) return;
      _rideState = ref.read(
        activeRideViewModelProvider(rideId).select((s) => s.ride?.state),
      );
      _reconcile(rideId);
    });

    _freshnessTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_alive) return;
      _refreshFreshnessOnly();
    });

    return TripLocationSessionState.initial;
  }

  void onAppLifecycle(AppLifecycleState lifecycle) {
    if (!_alive) return;
    switch (lifecycle) {
      case AppLifecycleState.resumed:
        _appInForeground = true;
        _reconcile(arg);
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _appInForeground = false;
        _stopForBackgroundOrTerminal(clearFix: false);
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _reconcile(String rideId) {
    if (!_alive) return;
    final should = tripLocationShouldListen(_rideState) && _appInForeground;
    if (!should) {
      final clearFix = tripLocationMustStop(_rideState);
      _stopForBackgroundOrTerminal(clearFix: clearFix);
      return;
    }
    if (_watchHeld) return;
    _startWatch(rideId);
  }

  void _startWatch(String rideId) {
    if (_watchHeld) return;
    _watchHeld = true;
    final generation = state.watchGeneration + 1;
    state = state.copyWith(
      isListening: true,
      isUnavailable: false,
      watchGeneration: generation,
      statusMessage:
          state.latest == null ? 'Waiting for driver location…' : state.statusMessage,
      clearStatusMessage: state.latest != null && state.statusMessage == null,
    );

    try {
      _sub = _port.watchLatest(rideId).listen(
        _onLatest,
        onError: (_) {
          if (!_alive) return;
          _watchHeld = false;
          _sub = null;
          state = state.copyWith(
            isListening: false,
            isUnavailable: true,
            statusMessage: 'Live location unavailable',
          );
        },
        onDone: () {
          if (!_alive) return;
          _watchHeld = false;
          _sub = null;
          state = state.copyWith(
            isListening: false,
            isUnavailable: true,
            statusMessage: state.latest == null
                ? 'Live location unavailable'
                : 'Location updating…',
          );
        },
        cancelOnError: false,
      );
    } catch (_) {
      _watchHeld = false;
      _sub = null;
      state = state.copyWith(
        isListening: false,
        isUnavailable: true,
        statusMessage: 'Live location unavailable',
      );
    }
  }

  void _onLatest(TripLocationLatest? latest) {
    if (!_alive) return;
    if (latest == null) {
      if (state.latest == null) {
        state = state.copyWith(
          clearLatest: true,
          freshness: TripLocationFreshness.missing,
          statusMessage: tripLocationShouldListen(_rideState)
              ? 'Waiting for driver location…'
              : null,
          isUnavailable: false,
        );
      } else {
        _refreshFreshnessOnly();
      }
      return;
    }

    // Seq monotonicity: ignore older sequences.
    if (state.appliedSeq > 0 && latest.locationSeq < state.appliedSeq) {
      return;
    }

    final band = _freshnessPolicy.classify(latest, now: _now());
    final message = _messageFor(band);
    state = state.copyWith(
      latest: latest,
      freshness: band,
      appliedSeq: latest.locationSeq,
      isListening: true,
      isUnavailable: false,
      statusMessage: message,
      clearStatusMessage: message == null,
    );
  }

  void _refreshFreshnessOnly() {
    final latest = state.latest;
    if (latest == null) return;
    final band = _freshnessPolicy.classify(latest, now: _now());
    final message = _messageFor(band);
    if (band == state.freshness && state.statusMessage == message) return;
    state = state.copyWith(
      freshness: band,
      statusMessage: message,
      clearStatusMessage: message == null,
    );
  }

  String? _messageFor(TripLocationFreshness band) {
    switch (band) {
      case TripLocationFreshness.fresh:
        return null;
      case TripLocationFreshness.stale:
      case TripLocationFreshness.degraded:
        return 'Location updating…';
      case TripLocationFreshness.expired:
        return 'Waiting for driver location…';
      case TripLocationFreshness.missing:
        return 'Waiting for driver location…';
    }
  }

  void _stopForBackgroundOrTerminal({required bool clearFix}) {
    _cancelWatch();
    if (clearFix) {
      state = state.copyWith(
        clearLatest: true,
        freshness: TripLocationFreshness.missing,
        isListening: false,
        isUnavailable: false,
        clearStatusMessage: true,
        appliedSeq: 0,
      );
    } else {
      state = state.copyWith(isListening: false);
    }
  }

  void _cancelWatch() {
    _watchHeld = false;
    final sub = _sub;
    _sub = null;
    if (sub != null) {
      unawaited(sub.cancel());
    }
  }
}

final tripLocationSessionProvider = NotifierProvider.autoDispose
    .family<TripLocationSession, TripLocationSessionState, String>(
      TripLocationSession.new,
    );
