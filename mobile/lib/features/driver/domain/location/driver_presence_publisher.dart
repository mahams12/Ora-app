import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/logging/app_logger.dart';
import '../../data/location/driver_location_remote_data_source.dart';
import 'driver_location_fix.dart';
import 'driver_location_source.dart';

/// Idle presence publish cadence — must stay well under the server-side
/// 15s freshness window (N3_FRESHNESS_MAX_AGE_MS) so an online driver
/// remains continuously discoverable by nearby matching.
const Duration kPresencePublishInterval = Duration(seconds: 10);

/// A fix older than this is not republished by the heartbeat — matches the
/// server 15s staleness bound with margin.
const Duration kPresenceFixFreshness = Duration(seconds: 12);

/// Server-side accuracy bound (validation MAX_ACCURACY_M). Fixes worse than
/// this are rejected by the server anyway — skip them client-side to avoid
/// a guaranteed-failed write.
const double kPresenceMaxAccuracyMeters = 50;

/// Adaptive presence policy (cost-optimization Phase A). All values are
/// client-side only; the server independently derives marker freshness from
/// the declared [publishIntervalMs] when LOCATION_ADAPTIVE_FRESHNESS is on.
///
/// With [adaptive] = false every value collapses to the legacy fixed-10s
/// behavior — the flag is the only behavioral switch.
class PresencePublishPolicy {
  const PresencePublishPolicy({
    this.adaptive = false,
    this.movingInterval = kPresencePublishInterval,
    this.stationaryInterval = const Duration(seconds: 30),
    this.inviteBoostInterval = const Duration(seconds: 8),
    this.inviteBoostWindow = const Duration(seconds: 45),
    this.stationaryMovementMeters = 50,
    this.movingSpeedKmh = 8,
    this.keepaliveEnabled = false,
    this.keepaliveMaxFixAge = const Duration(seconds: 90),
    this.pauseDuringTrip = false,
    this.heartbeatTick = const Duration(seconds: 5),
  });

  /// Recommended production policy — mirrors ORA_COST_OPTIMIZATION_PLAN.md.
  const PresencePublishPolicy.adaptive()
      : adaptive = true,
        movingInterval = kPresencePublishInterval,
        stationaryInterval = const Duration(seconds: 30),
        inviteBoostInterval = const Duration(seconds: 8),
        inviteBoostWindow = const Duration(seconds: 45),
        stationaryMovementMeters = 50,
        movingSpeedKmh = 8,
        keepaliveEnabled = true,
        keepaliveMaxFixAge = const Duration(seconds: 90),
        pauseDuringTrip = true,
        heartbeatTick = const Duration(seconds: 5);

  final bool adaptive;
  final Duration movingInterval;
  final Duration stationaryInterval;
  final Duration inviteBoostInterval;

  /// How long a pending-invite signal keeps the boost cadence active.
  /// Covers the 20s server invite TTL with margin.
  final Duration inviteBoostWindow;
  final double stationaryMovementMeters;
  final double movingSpeedKmh;

  /// Republish the last accurate position with a fresh timestamp when the
  /// GPS watch stalls (keepalive). Only meaningful with adaptive cadences
  /// longer than the server 15s staleness bound.
  final bool keepaliveEnabled;
  final Duration keepaliveMaxFixAge;

  /// Suppress idle publishes while the trip publisher is streaming the same
  /// geo marker at trip cadence — the presence packet is redundant there.
  final bool pauseDuringTrip;

  /// Heartbeat tick granularity for adaptive mode (checks whether a publish
  /// is due; the effective interval is evaluated per tick).
  final Duration heartbeatTick;
}

/// Session-owned idle presence publisher.
///
/// While the driver is online, signed in, and the app is foregrounded, this
/// publishes idle-mode location updates so the server geo index + online
/// marker stay fresh and the driver remains discoverable by N3 nearby
/// matching and N4 dispatch between trips.
///
/// Adaptive mode (PresencePublishPolicy.adaptive): the cadence follows the
/// driver state — stationary 30s, moving 10s, pending-invite boost 8s —
/// and every publish declares its interval to the server so the marker
/// freshness window tracks it. GPS stall falls back to a keepalive publish
/// (same last accurate coords, fresh timestamp) so an online driver with a
/// dead GPS stream does not silently drop out of matching.
///
/// Stationary drivers keep presence via the heartbeat (the server rejects
/// markers older than its freshness window). During an active trip the trip
/// publisher projects the same geo document; with pauseDuringTrip the
/// presence loop stops writing while trip publishes are active.
///
/// No UI. No RTDB. No offline queue.
class DriverPresencePublisher {
  DriverPresencePublisher({
    required DriverLocationRemoteDataSource remote,
    required DriverLocationSource source,
    required AppLogger logger,
    Duration interval = kPresencePublishInterval,
    Duration fixFreshness = kPresenceFixFreshness,
    double maxAccuracyMeters = kPresenceMaxAccuracyMeters,
    PresencePublishPolicy policy = const PresencePublishPolicy(),
    DateTime Function()? now,
    String Function()? newStreamId,
    this.onLatestFix,
  })  : _remote = remote,
        _source = source,
        _logger = logger,
        _interval = interval,
        _fixFreshness = fixFreshness,
        _maxAccuracyMeters = maxAccuracyMeters,
        _policy = policy,
        _now = now ?? DateTime.now,
        _newStreamId = newStreamId ?? (() => const Uuid().v4());

  final DriverLocationRemoteDataSource _remote;
  final DriverLocationSource _source;
  final AppLogger _logger;
  final Duration _interval;
  final Duration _fixFreshness;
  final double _maxAccuracyMeters;
  final PresencePublishPolicy _policy;
  final DateTime Function() _now;
  final String Function() _newStreamId;

  /// Latest accepted fix for local display (driver home map). Display-only;
  /// publish eligibility still runs through [_consider]/[_publishable].
  final void Function(DriverLocationFix fix)? onLatestFix;

  bool _online = false;
  bool _foreground = true;
  bool _signedIn = true;
  bool _disposed = false;

  StreamSubscription<DriverLocationReading>? _subscription;
  Timer? _heartbeatTimer;
  CancelToken? _cancelToken;

  DriverLocationFix? _latestFix;
  DriverLocationFix? _lastPublishedFix;
  DriverLocationFix? _lastAcceptedFix;
  DriverLocationFix? _pendingWhileInFlight;
  DateTime? _lastPublishAt;
  DateTime? _inviteBoostUntil;
  DateTime? _backoffUntil;
  Duration _backoffStep = const Duration(seconds: 2);
  bool _tripPublishing = false;
  bool _inFlight = false;
  String _locationStreamId = '';
  int _nextSeq = 1;

  bool get _wanted => _signedIn && _online && _foreground && !_disposed;

  /// Test-visible state.
  bool get isPublishing => _subscription != null;
  int get publishedCountForTest => _nextSeq - 1;

  /// Drive the gate: driver availability changed (durable server state).
  void onAvailability({required bool online}) {
    if (_disposed || _online == online) return;
    _online = online;
    _reconcile();
  }

  /// Pending-invite signal (FCM nudge OR invite-list refresh — whichever
  /// arrives). Extends the boost window; absence of signal never harms
  /// freshness — the marker window is self-declared.
  void onInviteActivity() {
    if (_disposed || !_policy.adaptive) return;
    _inviteBoostUntil = _now().add(_policy.inviteBoostWindow);
  }

  /// Trip publisher activity — when [PresencePublishPolicy.pauseDuringTrip]
  /// is on, idle publishes stop while trip packets keep the marker warm.
  void setTripPublishing(bool active) {
    if (_disposed) return;
    _tripPublishing = active;
  }

  void onForeground() {
    if (_disposed || _foreground) return;
    _foreground = true;
    _reconcile();
  }

  void onBackground() {
    if (_disposed || !_foreground) return;
    _foreground = false;
    _stop('background');
  }

  void onSignedOut() {
    if (_disposed) return;
    _signedIn = false;
    _stop('sign_out');
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stop('dispose');
  }

  void _reconcile() {
    if (_wanted) {
      _start();
    } else {
      _stop('unwanted');
    }
  }

  void _start() {
    if (_subscription != null) return;
    _locationStreamId = _newStreamId();
    _nextSeq = 1;
    _latestFix = null;
    _lastPublishedFix = null;
    _lastAcceptedFix = null;
    _lastPublishAt = null;
    _backoffUntil = null;
    _backoffStep = const Duration(seconds: 2);
    _pendingWhileInFlight = null;
    _cancelToken = CancelToken();
    _log('presence_watch_started');
    _subscription = _source.watch().listen((reading) {
      if (_disposed || !_wanted) return;
      if (reading is DriverLocationFixReading) {
        _latestFix = reading.fix;
        onLatestFix?.call(reading.fix);
        _consider(reading.fix);
      }
      // Failure readings (permission/service loss): nothing to publish — the
      // server-side marker simply expires, which correctly removes the
      // driver from matching. Fail-closed is the desired behavior.
    });
    // Adaptive mode ticks faster than the slowest interval and evaluates the
    // effective interval per tick; legacy mode keeps its fixed period.
    _heartbeatTimer = Timer.periodic(
      _policy.adaptive ? _policy.heartbeatTick : _interval,
      (_) => _heartbeat(),
    );
  }

  void _stop(String reason) {
    _subscription?.cancel();
    _subscription = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _cancelToken?.cancel();
    _cancelToken = null;
    _inFlight = false;
    _pendingWhileInFlight = null;
    _latestFix = null;
    _lastPublishedFix = null;
    _lastAcceptedFix = null;
    _backoffUntil = null;
    if (reason != 'unwanted' || _online) {
      _log('presence_stopped', {'reason': reason});
    }
  }

  bool _accuracyOk(DriverLocationFix fix) {
    final a = fix.accuracyMeters;
    return a.isFinite && a >= 0 && a <= _maxAccuracyMeters;
  }

  bool _publishable(DriverLocationFix fix) {
    if (!_accuracyOk(fix)) return false;
    if (!fix.speedKmh.isFinite || fix.speedKmh < 0) return false;
    final age = _now().difference(fix.timestamp);
    if (age > _fixFreshness || age < -const Duration(seconds: 5)) return false;
    return true;
  }

  /// Whether the driver currently counts as moving — displacement vs the
  /// last published fix above the jitter floor, or a moving speed reading.
  bool _isMoving(DriverLocationFix fix) {
    if (fix.speedKmh.isFinite && fix.speedKmh > _policy.movingSpeedKmh) {
      return true;
    }
    final last = _lastPublishedFix;
    if (last == null) return true;
    return _distanceMeters(last, fix) >= _policy.stationaryMovementMeters;
  }

  /// Effective publish interval for the current driver state.
  Duration _effectiveInterval(DriverLocationFix fix) {
    if (!_policy.adaptive) return _interval;
    final boostUntil = _inviteBoostUntil;
    if (boostUntil != null && _now().isBefore(boostUntil)) {
      return _policy.inviteBoostInterval;
    }
    return _isMoving(fix)
        ? _policy.movingInterval
        : _policy.stationaryInterval;
  }

  bool _suppressedByTrip() {
    return _policy.adaptive && _policy.pauseDuringTrip && _tripPublishing;
  }

  bool _backingOff() {
    final until = _backoffUntil;
    return until != null && _now().isBefore(until);
  }

  void _consider(DriverLocationFix fix) {
    if (!_wanted || _suppressedByTrip() || _backingOff()) return;
    if (_inFlight) {
      _pendingWhileInFlight = fix;
      return;
    }
    final last = _lastPublishAt;
    if (last != null &&
        _now().difference(last) < _effectiveInterval(fix)) {
      return;
    }
    if (!_publishable(fix)) return;
    unawaited(_publish(fix));
  }

  void _heartbeat() {
    if (_inFlight || !_wanted || _suppressedByTrip() || _backingOff()) {
      return;
    }
    final fix = _latestFix;
    if (fix == null) return;
    final last = _lastPublishAt;
    final interval = _effectiveInterval(fix);
    if (last != null && _now().difference(last) < interval) return;
    if (_publishable(fix)) {
      unawaited(_publish(fix));
      return;
    }
    // Adaptive keepalive: the GPS watch stalled but the driver is still
    // online. Re-assert the last ACCURATE position with its ORIGINAL
    // timestamp — the server records the honest fix age in lastLocationTs
    // and derives presence freshness from acceptedAt, so a stale position
    // can never masquerade as a fresh fix at invite time.
    // Fail-closed for legacy mode and for keepalive age overflow.
    if (!_policy.keepaliveEnabled) return;
    final keepaliveSource = _accuracyOk(fix)
        ? fix
        : _lastAcceptedFix;
    if (keepaliveSource == null) return;
    final fixAge = _now().difference(keepaliveSource.timestamp);
    if (fixAge > _policy.keepaliveMaxFixAge) return;
    unawaited(_publish(keepaliveSource, keepalive: true));
  }

  Future<void> _publish(DriverLocationFix fix, {bool keepalive = false}) async {
    // Compute the advertised interval BEFORE marking this fix as last-
    // published — _isMoving measures displacement from the previous publish.
    final intervalMs = _policy.adaptive
        ? _effectiveInterval(fix).inMilliseconds
        : null;
    _inFlight = true;
    _lastPublishAt = _now();
    _lastPublishedFix = fix;
    final seq = _nextSeq++;
    final token = _cancelToken ?? CancelToken();
    _cancelToken = token;
    try {
      final result = await _remote.publishIdleLocation(
        locationSeq: seq,
        locationStreamId: _locationStreamId,
        fix: fix,
        cancelToken: token,
        publishIntervalMs: intervalMs,
        presenceKeepalive: keepalive,
      );
      final accepted = result is LocationPublishAccepted;
      _log('presence_publish_result', {
        'seq': seq,
        'accepted': accepted,
        'keepalive': keepalive,
      });
      if (accepted) {
        _lastAcceptedFix = fix;
        _backoffUntil = null;
        _backoffStep = const Duration(seconds: 2);
      } else if (result is LocationPublishFailed) {
        _handleFailure(result);
      }
    } finally {
      _inFlight = false;
      final pending = _pendingWhileInFlight;
      _pendingWhileInFlight = null;
      if (pending != null && _wanted && !_disposed) {
        _consider(pending);
      }
    }
  }

  void _handleFailure(LocationPublishFailed result) {
    switch (result.kind) {
      case LocationPublishFailureKind.sequenceViolation:
        // The idle stream is replaceable — reset it so the driver recovers
        // instead of failing every subsequent publish on a stale cursor.
        _locationStreamId = _newStreamId();
        _nextSeq = 1;
        _log('presence_stream_reset', {'reason': 'sequence_violation'});
      case LocationPublishFailureKind.rateLimited:
      case LocationPublishFailureKind.server:
      case LocationPublishFailureKind.network:
      case LocationPublishFailureKind.timeout:
      case LocationPublishFailureKind.unknown:
        _backoffUntil = _now().add(_backoffStep);
        _backoffStep = _backoffStep * 2 > const Duration(seconds: 30)
            ? const Duration(seconds: 30)
            : _backoffStep * 2;
      case LocationPublishFailureKind.unauthorized:
      case LocationPublishFailureKind.forbidden:
      case LocationPublishFailureKind.invalidOrStale:
      case LocationPublishFailureKind.cancelled:
        break;
    }
  }

  void _log(String event, [Map<String, Object?>? metadata]) {
    _logger.debug('driver_presence.$event', metadata: metadata);
  }

  /// Haversine distance in meters.
  static double _distanceMeters(DriverLocationFix a, DriverLocationFix b) {
    const earthRadiusM = 6371000.0;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * earthRadiusM * math.asin(math.sqrt(h));
  }
}
