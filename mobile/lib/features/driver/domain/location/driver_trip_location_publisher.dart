import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/request_context.dart';
import '../../data/location/driver_location_remote_data_source.dart';
import 'driver_location_fix.dart';
import 'driver_location_lifecycle.dart';

/// Approved L2 Step 4 MVP publish cadence.
const Duration kTripLocationMinInterval = Duration(milliseconds: 4000);
const double kTripLocationMinMovementMeters = 15;
const Duration kTripLocationHeartbeat = Duration(milliseconds: 10000);
const Duration kTripLocationHeartbeatFreshness = Duration(seconds: 12);
const int kTripLocationMaxPublishesPerMinute = 15;
const Duration kTripLocationRateLimitBackoff = Duration(seconds: 3);
const Duration kTripLocationServerBackoff = Duration(seconds: 2);

/// Session-owned trip location publisher. No UI. No RTDB. No offline queue.
class DriverTripLocationPublisher {
  DriverTripLocationPublisher({
    required this.rideId,
    required DriverLocationRemoteDataSource remote,
    required AppLogger logger,
    DateTime Function()? now,
    String Function()? newStreamId,
    Duration minInterval = kTripLocationMinInterval,
    double minMovementMeters = kTripLocationMinMovementMeters,
    Duration heartbeat = kTripLocationHeartbeat,
    Duration heartbeatFreshness = kTripLocationHeartbeatFreshness,
    int maxPublishesPerMinute = kTripLocationMaxPublishesPerMinute,
  }) : _remote = remote,
       _logger = logger,
       _now = now ?? DateTime.now,
       _newStreamId = newStreamId ?? (() => const Uuid().v4()),
       _minInterval = minInterval,
       _minMovementMeters = minMovementMeters,
       _heartbeat = heartbeat,
       _heartbeatFreshness = heartbeatFreshness,
       _maxPublishesPerMinute = maxPublishesPerMinute;

  final String rideId;
  final DriverLocationRemoteDataSource _remote;
  final AppLogger _logger;
  final DateTime Function() _now;
  final String Function() _newStreamId;
  final Duration _minInterval;
  final double _minMovementMeters;
  final Duration _heartbeat;
  final Duration _heartbeatFreshness;
  final int _maxPublishesPerMinute;

  String? _rideState;
  String? _locationStreamId;
  int _nextSeq = 1;
  int _watchGeneration = 0;
  int _publishGeneration = 0;
  bool _watching = false;
  bool _stoppedPermanently = false;
  bool _disposed = false;
  bool _inFlight = false;
  DateTime? _backoffUntil;
  DateTime? _lastPublishAt;
  DriverLocationFix? _lastPublishedFix;
  DriverLocationFix? _latestAccepted;
  DriverLocationFix? _pendingWhileInFlight;
  final List<DateTime> _publishTimes = <DateTime>[];
  CancelToken? _cancelToken;
  Timer? _heartbeatTimer;

  /// Successful publishes in this publisher lifetime (tests/metrics).
  int successCount = 0;

  /// Outbound HTTP attempts that were actually sent.
  int attemptCount = 0;

  bool get isDisposed => _disposed;
  bool get isStoppedPermanently => _stoppedPermanently;
  bool get isWatching => _watching;
  bool get isInFlight => _inFlight;
  String? get activeLocationStreamId => _locationStreamId;
  int get nextLocationSeq => _nextSeq;
  int get watchGeneration => _watchGeneration;

  bool get wantsPublish {
    if (_disposed || _stoppedPermanently || !_watching) return false;
    return driverLocationShouldWatch(_rideState);
  }

  void onRideState(String? rideState) {
    if (_disposed) return;
    _rideState = rideState;
    if (!driverLocationShouldWatch(rideState)) {
      _cancelInFlight(reason: 'ride_state_inactive');
      _disarmHeartbeat();
    }
  }

  void onWatchStarted() {
    if (_disposed || _stoppedPermanently) return;
    _watchGeneration++;
    _publishGeneration = _watchGeneration;
    _watching = true;
    _locationStreamId = _newStreamId();
    _nextSeq = 1;
    _lastPublishedFix = null;
    _lastPublishAt = null;
    _latestAccepted = null;
    _pendingWhileInFlight = null;
    _cancelInFlight(reason: 'watch_restart');
    _log('location_publish_stream_started', {
      'rideId': rideId,
      'watchGeneration': _watchGeneration,
      // stream id is not secret but omit full uuid from sparse logs if needed —
      // keep a short fingerprint only.
      'streamIdSuffix': _streamSuffix(_locationStreamId),
    });
  }

  void onWatchStopped(String reason) {
    if (_disposed) return;
    _watching = false;
    _cancelInFlight(reason: reason);
    _disarmHeartbeat();
    _pendingWhileInFlight = null;
    _latestAccepted = null;
  }

  void onAcceptedFix(DriverLocationFix fix) {
    if (_disposed || _stoppedPermanently || !wantsPublish) return;
    _latestAccepted = fix;
    _consider(fix, reason: 'accepted_fix');
    _armHeartbeat();
  }

  /// Terminal stop for this ride session (cancel / 403 / dispose).
  void stop({required String reason}) {
    if (_disposed) return;
    _stoppedPermanently = true;
    _watching = false;
    _publishGeneration++;
    _cancelInFlight(reason: reason);
    _disarmHeartbeat();
    _pendingWhileInFlight = null;
    _latestAccepted = null;
    _log('location_publish_stopped', {
      'rideId': rideId,
      'reason': reason,
    });
  }

  void dispose() {
    if (_disposed) return;
    stop(reason: 'dispose');
    _disposed = true;
  }

  void _consider(DriverLocationFix fix, {required String reason}) {
    if (!wantsPublish) return;
    if (_inFlight) {
      _pendingWhileInFlight = fix;
      return;
    }
    if (!_eligible(fix, reason: reason)) return;
    unawaited(_publish(fix, reason: reason));
  }

  bool _eligible(DriverLocationFix fix, {required String reason}) {
    final now = _now();
    if (_backoffUntil != null && now.isBefore(_backoffUntil!)) {
      return false;
    }
    if (_rateLimited(now)) return false;

    final lastAt = _lastPublishAt;
    final lastFix = _lastPublishedFix;
    if (lastAt == null || lastFix == null) {
      return true;
    }
    // Exact duplicate coords+timestamp: suppress for movement publishes only.
    // Heartbeat may republish the same fresh fix.
    if (reason != 'heartbeat' && fix.isDuplicateOf(lastFix)) {
      return false;
    }

    final intervalOk =
        now.difference(lastAt) >= _minInterval;
    final moved = _distanceMeters(lastFix, fix) >= _minMovementMeters;
    if (intervalOk && moved) return true;

    if (reason == 'heartbeat') {
      final age = now.difference(fix.timestamp);
      if (age <= _heartbeatFreshness &&
          now.difference(lastAt) >= _heartbeat) {
        return true;
      }
    }
    return false;
  }

  bool _rateLimited(DateTime now) {
    _publishTimes.removeWhere(
      (t) => now.difference(t) > const Duration(minutes: 1),
    );
    return _publishTimes.length >= _maxPublishesPerMinute;
  }

  Future<void> _publish(DriverLocationFix fix, {required String reason}) async {
    if (!wantsPublish || _inFlight) return;
    final streamId = _locationStreamId;
    if (streamId == null || streamId.isEmpty) return;

    final generation = _publishGeneration;
    final seq = _nextSeq;
    _nextSeq = seq + 1;
    _inFlight = true;
    attemptCount++;
    final now = _now();
    _publishTimes.add(now);
    _publishTimes.removeWhere(
      (t) => now.difference(t) > const Duration(minutes: 1),
    );
    final token = CancelToken();
    _cancelToken = token;

    _log('location_publish_attempt', {
      'rideId': rideId,
      'locationSeq': seq,
      'streamIdSuffix': _streamSuffix(streamId),
      'reason': reason,
      'watchGeneration': generation,
    });

    LocationPublishResult result;
    try {
      result = await _remote.publishTripLocation(
        rideId: rideId,
        locationSeq: seq,
        locationStreamId: streamId,
        fix: fix,
        cancelToken: token,
        context: RequestContext(
          requestId: const Uuid().v4(),
          operationId: 'location:update:$rideId',
        ),
      );
    } catch (_) {
      result = const LocationPublishFailed(
        kind: LocationPublishFailureKind.unknown,
      );
    }

    if (_disposed || generation != _publishGeneration) {
      _inFlight = false;
      _cancelToken = null;
      return;
    }
    if (token.isCancelled) {
      _inFlight = false;
      _cancelToken = null;
      return;
    }

    _inFlight = false;
    _cancelToken = null;
    _handleResult(result, fix: fix, seq: seq, generation: generation);

    final pending = _pendingWhileInFlight;
    _pendingWhileInFlight = null;
    if (pending != null && wantsPublish && generation == _publishGeneration) {
      _consider(pending, reason: 'coalesced');
    }
  }

  void _handleResult(
    LocationPublishResult result, {
    required DriverLocationFix fix,
    required int seq,
    required int generation,
  }) {
    if (generation != _publishGeneration) return;

    switch (result) {
      case LocationPublishAccepted():
        successCount++;
        final now = _now();
        _lastPublishAt = now;
        _lastPublishedFix = fix;
        _armHeartbeat();
        _log('location_publish_accepted', {
          'rideId': rideId,
          'locationSeq': seq,
          'streamIdSuffix': _streamSuffix(_locationStreamId),
        });
      case LocationPublishFailed(:final kind, :final statusCode, :final code):
        _log('location_publish_failed', {
          'rideId': rideId,
          'locationSeq': seq,
          'kind': kind.name,
          'statusCode': statusCode,
          'code': code,
        });
        switch (kind) {
          case LocationPublishFailureKind.unauthorized:
          case LocationPublishFailureKind.forbidden:
            stop(reason: kind.name);
          case LocationPublishFailureKind.sequenceViolation:
            // Seq already advanced on send; wait for next fresh fix.
            break;
          case LocationPublishFailureKind.invalidOrStale:
          case LocationPublishFailureKind.cancelled:
          case LocationPublishFailureKind.network:
          case LocationPublishFailureKind.timeout:
          case LocationPublishFailureKind.unknown:
            break;
          case LocationPublishFailureKind.rateLimited:
            _backoffUntil = _now().add(kTripLocationRateLimitBackoff);
          case LocationPublishFailureKind.server:
            _backoffUntil = _now().add(kTripLocationServerBackoff);
        }
    }
  }

  void _armHeartbeat() {
    _heartbeatTimer?.cancel();
    if (_disposed || _stoppedPermanently || !wantsPublish) return;
    if (_heartbeat <= Duration.zero) return;
    final generation = _publishGeneration;
    _heartbeatTimer = Timer(_heartbeat, () {
      if (_disposed ||
          _stoppedPermanently ||
          generation != _publishGeneration ||
          !wantsPublish) {
        return;
      }
      final latest = _latestAccepted;
      if (latest == null) return;
      _consider(latest, reason: 'heartbeat');
      _armHeartbeat();
    });
  }

  void _disarmHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _cancelInFlight({required String reason}) {
    final token = _cancelToken;
    _cancelToken = null;
    if (token != null && !token.isCancelled) {
      token.cancel(reason);
    }
    _inFlight = false;
  }

  void _log(String message, Map<String, Object?> metadata) {
    _logger.info(message, metadata: metadata);
  }

  static String? _streamSuffix(String? streamId) {
    if (streamId == null || streamId.length < 8) return streamId;
    return streamId.substring(streamId.length - 8);
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
