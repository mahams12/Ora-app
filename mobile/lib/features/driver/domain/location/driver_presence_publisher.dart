import 'dart:async';

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

/// Session-owned idle presence publisher.
///
/// While the driver is online, signed in, and the app is foregrounded, this
/// publishes one idle-mode location update per [_interval] so the server geo
/// index + online marker stay fresh and the driver remains discoverable by
/// N3 nearby matching and N4 dispatch between trips.
///
/// Stationary drivers keep presence via the heartbeat (the server rejects
/// markers older than 15s). During an active trip the trip publisher also
/// projects the same geo document; the server-side marker resolves
/// newest-timestamp-wins across streams, so overlap is safe — presence is
/// NOT paused on trips because no always-on ride-state signal exists at
/// shell level.
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
    DateTime Function()? now,
    String Function()? newStreamId,
  })  : _remote = remote,
        _source = source,
        _logger = logger,
        _interval = interval,
        _fixFreshness = fixFreshness,
        _maxAccuracyMeters = maxAccuracyMeters,
        _now = now ?? DateTime.now,
        _newStreamId = newStreamId ?? (() => const Uuid().v4());

  final DriverLocationRemoteDataSource _remote;
  final DriverLocationSource _source;
  final AppLogger _logger;
  final Duration _interval;
  final Duration _fixFreshness;
  final double _maxAccuracyMeters;
  final DateTime Function() _now;
  final String Function() _newStreamId;

  bool _online = false;
  bool _foreground = true;
  bool _signedIn = true;
  bool _disposed = false;

  StreamSubscription<DriverLocationReading>? _subscription;
  Timer? _heartbeatTimer;
  CancelToken? _cancelToken;

  DriverLocationFix? _latestFix;
  DriverLocationFix? _pendingWhileInFlight;
  DateTime? _lastPublishAt;
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
    _lastPublishAt = null;
    _pendingWhileInFlight = null;
    _cancelToken = CancelToken();
    _log('presence_watch_started');
    _subscription = _source.watch().listen((reading) {
      if (_disposed || !_wanted) return;
      if (reading is DriverLocationFixReading) {
        _latestFix = reading.fix;
        _consider(reading.fix);
      }
      // Failure readings (permission/service loss): nothing to publish — the
      // server-side marker simply expires, which correctly removes the
      // driver from matching. Fail-closed is the desired behavior.
    });
    _heartbeatTimer = Timer.periodic(_interval, (_) => _heartbeat());
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
    if (reason != 'unwanted' || _online) {
      _log('presence_stopped', {'reason': reason});
    }
  }

  bool _publishable(DriverLocationFix fix) {
    final a = fix.accuracyMeters;
    if (!a.isFinite || a < 0 || a > _maxAccuracyMeters) return false;
    if (!fix.speedKmh.isFinite || fix.speedKmh < 0) return false;
    final age = _now().difference(fix.timestamp);
    if (age > _fixFreshness || age < -const Duration(seconds: 5)) return false;
    return true;
  }

  void _consider(DriverLocationFix fix) {
    if (!_wanted) return;
    if (_inFlight) {
      _pendingWhileInFlight = fix;
      return;
    }
    final last = _lastPublishAt;
    if (last != null && _now().difference(last) < _interval) return;
    if (!_publishable(fix)) return;
    unawaited(_publish(fix));
  }

  void _heartbeat() {
    final fix = _latestFix;
    if (fix == null || _inFlight || !_wanted) return;
    final last = _lastPublishAt;
    if (last != null && _now().difference(last) < _interval) return;
    if (!_publishable(fix)) return;
    unawaited(_publish(fix));
  }

  Future<void> _publish(DriverLocationFix fix) async {
    _inFlight = true;
    _lastPublishAt = _now();
    final seq = _nextSeq++;
    final token = _cancelToken ?? CancelToken();
    _cancelToken = token;
    try {
      final result = await _remote.publishIdleLocation(
        locationSeq: seq,
        locationStreamId: _locationStreamId,
        fix: fix,
        cancelToken: token,
      );
      _log('presence_publish_result', {
        'seq': seq,
        'accepted': result is LocationPublishAccepted,
      });
    } finally {
      _inFlight = false;
      final pending = _pendingWhileInFlight;
      _pendingWhileInFlight = null;
      if (pending != null && _wanted && !_disposed) {
        _consider(pending);
      }
    }
  }

  void _log(String event, [Map<String, Object?>? metadata]) {
    _logger.debug('driver_presence.$event', metadata: metadata);
  }
}
