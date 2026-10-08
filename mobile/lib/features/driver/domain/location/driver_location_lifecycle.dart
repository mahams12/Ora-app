import 'dart:async';

import '../../../../core/logging/app_logger.dart';
import 'driver_location_classifier.dart';
import 'driver_location_fix.dart';
import 'driver_location_source.dart';
import 'driver_location_status.dart';

/// Where the location controller is hosted.
enum DriverLocationSurface {
  /// Driver home does not acquire GPS.
  home,

  /// Assigned-job screen. GPS still depends on ride state.
  assignedRide,
}

/// Ride states that require a foreground GPS watch.
///
/// Terminal and pre-assignment states do not.
bool driverLocationShouldWatch(String? rideState) {
  switch (rideState?.toUpperCase()) {
    case 'DRIVER_ASSIGNED':
    case 'DRIVER_EN_ROUTE':
    case 'DRIVER_ARRIVED':
    case 'RIDE_STARTED':
      return true;
    default:
      return false;
  }
}

const _bannedLogKeys = <String>{
  'lat',
  'lng',
  'latitude',
  'longitude',
  'token',
  'authorization',
  'appcheck',
  'apikey',
  'secret',
};

Map<String, Object?> _safeLocationMetadata(Map<String, Object?> metadata) {
  final safe = <String, Object?>{};
  for (final entry in metadata.entries) {
    if (_bannedLogKeys.contains(entry.key.toLowerCase())) continue;
    final value = entry.value;
    if (value is double && !value.isFinite) {
      safe[entry.key] = 'non_finite';
      continue;
    }
    safe[entry.key] = value;
  }
  return safe;
}

/// Starts and stops one foreground GPS watch from ride and app lifecycle.
///
/// Local only. This class does not write to the network, Redis, or RTDB.
/// Optional [onAcceptedFix] / watch callbacks let L2 publish without owning GPS.
class DriverLocationLifecycleController {
  DriverLocationLifecycleController({
    required DriverLocationSource source,
    required AppLogger logger,
    required void Function(DriverLocationStatusKind kind) onStatus,
    void Function(DriverLocationFix fix)? onAcceptedFix,
    void Function()? onWatchStarted,
    void Function(String reason)? onWatchStopped,
    DriverLocationClassifier classifier = const DriverLocationClassifier(),
    DateTime Function()? now,
    Duration acquisitionTimeout = const Duration(seconds: 20),
  }) : _source = source,
       _logger = logger,
       _onStatus = onStatus,
       _onAcceptedFix = onAcceptedFix,
       _onWatchStarted = onWatchStarted,
       _onWatchStopped = onWatchStopped,
       _classifier = classifier,
       _now = now ?? DateTime.now,
       _acquisitionTimeout = acquisitionTimeout;

  final DriverLocationSource _source;
  final AppLogger _logger;
  final void Function(DriverLocationStatusKind kind) _onStatus;
  final void Function(DriverLocationFix fix)? _onAcceptedFix;
  final void Function()? _onWatchStarted;
  final void Function(String reason)? _onWatchStopped;
  final DriverLocationClassifier _classifier;
  final DateTime Function() _now;
  final Duration _acquisitionTimeout;

  DriverLocationSurface _surface = DriverLocationSurface.assignedRide;
  bool _offline = false;
  bool _signedIn = true;
  bool _foreground = true;
  bool _disposed = false;
  /// When true, do not auto-restart after a terminal acquisition failure
  /// (permission denied / services off). User action clears this.
  bool _holdRestart = false;
  String? _rideId;
  String? _rideState;
  DriverLocationFix? _lastAccepted;
  DriverLocationStatusKind _status = DriverLocationStatusKind.hidden;
  StreamSubscription<DriverLocationReading>? _subscription;
  Timer? _acquisitionWatchdog;
  int _generation = 0;
  DateTime? _watchStartedAt;
  bool _loggedFirstCallback = false;
  bool _loggedFirstAccepted = false;

  /// How many times the visible status actually changed.
  int statusChangeCount = 0;

  DriverLocationStatusKind get status => _status;

  bool get isWatching => _subscription != null;

  void onSurface(DriverLocationSurface surface) {
    _surface = surface;
    _reconcile();
  }

  void onDriverOffline(bool offline) {
    _offline = offline;
    if (offline) _holdRestart = false;
    _reconcile();
  }

  void onRide({required String? rideId, required String? rideState}) {
    final rideChanged = _rideId != rideId;
    _rideId = rideId;
    _rideState = rideState;
    // Only a different ride clears the hold. Ride-state flicker during poll
    // must not restart after a permanent permission denial.
    if (rideChanged) _holdRestart = false;
    _reconcile();
  }

  void onBackground() {
    _foreground = false;
    // Do not clear [_holdRestart]: system permission sheets flip lifecycle and
    // must not restart acquisition after a deny.
    _stop('background');
  }

  void onForeground() {
    _foreground = true;
    if (_holdRestart) {
      // Soft deny / unavailable: wait for the in-app recovery CTA.
      // Permanent deny / services-off: allow one retry after Settings return.
      if (_status == DriverLocationStatusKind.permissionBlocked ||
          _status == DriverLocationStatusKind.servicesDisabled) {
        _holdRestart = false;
        _reconcile();
      }
      return;
    }
    _reconcile();
  }

  void onSignedOut() {
    _signedIn = false;
    _holdRestart = false;
    _stop('sign_out');
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _signedIn = false;
    _stop('dispose');
  }

  /// User tapped a recovery action on the status line.
  Future<void> onUserRecoveryAction() async {
    if (_disposed || !_wantsWatch) return;
    switch (_status) {
      case DriverLocationStatusKind.permissionBlocked:
        await _source.openPermissionSettings();
      case DriverLocationStatusKind.servicesDisabled:
        await _source.openLocationSettings();
      case DriverLocationStatusKind.permissionNeeded:
      case DriverLocationStatusKind.unavailable:
      case DriverLocationStatusKind.poorAccuracy:
        _holdRestart = false;
        if (_subscription != null) {
          _stop('user_retry');
        }
        _reconcile();
      case DriverLocationStatusKind.hidden:
      case DriverLocationStatusKind.acquiring:
      case DriverLocationStatusKind.ready:
        break;
    }
  }

  bool get _wantsWatch {
    if (_disposed || !_signedIn || _offline || !_foreground) return false;
    if (_surface != DriverLocationSurface.assignedRide) return false;
    final rideId = _rideId;
    if (rideId == null || rideId.isEmpty) return false;
    return driverLocationShouldWatch(_rideState);
  }

  void _reconcile() {
    if (_disposed) return;
    if (!_wantsWatch) {
      _stop('inactive');
      // Keep holdRestart while we remain on the same assigned ride so a
      // transient null/non-watchable state cannot restart acquisition.
      if (_rideId == null || _surface != DriverLocationSurface.assignedRide) {
        _holdRestart = false;
      }
      return;
    }
    if (_subscription != null || _holdRestart) return;
    _start();
  }

  void _start() {
    if (_subscription != null) return;
    final generation = _generation;
    final rideId = _rideId;
    _watchStartedAt = _now();
    _loggedFirstCallback = false;
    _loggedFirstAccepted = false;
    _log('location_watch_started', {'rideId': rideId});
    late final StreamSubscription<DriverLocationReading> subscription;
    subscription = _source.watch().listen(
      (reading) {
        if (generation != _generation) return;
        _onReading(reading);
      },
      onError: (Object error, StackTrace _) {
        if (generation != _generation) return;
        _log('location_acquisition_failed', {
          'rideId': rideId,
          'errorType': error.runtimeType.toString(),
        });
        _holdRestart = true;
        _emit(DriverLocationStatusKind.unavailable);
      },
      onDone: () {
        if (generation != _generation) return;
        if (!identical(_subscription, subscription)) return;
        _subscription = null;
        // Never leave the UI on "Getting your location…" after the stream
        // ends without a terminal status.
        if (_status == DriverLocationStatusKind.acquiring) {
          _holdRestart = true;
          _emit(DriverLocationStatusKind.unavailable);
        }
        _log('location_watch_stopped', {
          'rideId': rideId,
          'reason': 'stream_ended',
        });
        _onWatchStopped?.call('stream_ended');
      },
      cancelOnError: false,
    );
    _subscription = subscription;
    _emit(DriverLocationStatusKind.acquiring);
    _onWatchStarted?.call();
    // Safety net: if the platform permission sheet hangs, never leave the
    // driver on "Getting your location…" indefinitely.
    _armAcquisitionWatchdog(generation, rideId);
  }

  void _armAcquisitionWatchdog(int generation, String? rideId) {
    _acquisitionWatchdog?.cancel();
    _acquisitionWatchdog = null;
    if (_acquisitionTimeout <= Duration.zero) return;
    _acquisitionWatchdog = Timer(_acquisitionTimeout, () {
      if (_disposed || generation != _generation) return;
      if (_status != DriverLocationStatusKind.acquiring) return;
      _log('location_acquisition_failed', {
        'rideId': rideId,
        'failure': 'acquisitionTimeout',
      });
      _holdRestart = true;
      _emit(DriverLocationStatusKind.unavailable);
      _stop('acquisition_timeout');
    });
  }

  void _stop(String reason) {
    _generation++;
    _acquisitionWatchdog?.cancel();
    _acquisitionWatchdog = null;
    _lastAccepted = null;
    _watchStartedAt = null;
    _loggedFirstCallback = false;
    _loggedFirstAccepted = false;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
      _log('location_watch_stopped', {'rideId': _rideId, 'reason': reason});
      _onWatchStopped?.call(reason);
    }
    // Preserve recovery statuses (permission / services) across transient
    // inactive windows so permanent deny cannot tight-loop.
    if (!_holdRestart) {
      _emit(DriverLocationStatusKind.hidden);
    }
  }

  void _onReading(DriverLocationReading reading) {
    final started = _watchStartedAt;
    if (!_loggedFirstCallback && started != null) {
      _loggedFirstCallback = true;
      _log('location_first_callback', {
        'rideId': _rideId,
        'elapsedMs': _now().difference(started).inMilliseconds,
      });
    }

    switch (reading) {
      case DriverLocationFailureReading(:final failure):
        _log('location_acquisition_failed', {
          'rideId': _rideId,
          'failure': failure.name,
        });
        _holdRestart = true;
        _emit(_statusForFailure(failure));
      case DriverLocationFixReading(:final fix):
        final verdict = _classifier.classify(
          fix,
          now: _now(),
          lastAccepted: _lastAccepted,
        );
        final accuracy = fix.accuracyMeters;
        _log('location_fix_classified', {
          'rideId': _rideId,
          'classification': verdict.classification.logName,
          'accuracyMeters': accuracy.isFinite ? accuracy : 'non_finite',
          if (verdict.detail != null) 'detail': verdict.detail!.name,
        });
        switch (verdict.classification) {
          case DriverLocationClass.accepted:
            _lastAccepted = fix;
            if (!_loggedFirstAccepted && started != null) {
              _loggedFirstAccepted = true;
              _log('location_first_accepted', {
                'rideId': _rideId,
                'elapsedMs': _now().difference(started).inMilliseconds,
                'accuracyMeters': accuracy.isFinite ? accuracy : 'non_finite',
              });
            }
            _emit(DriverLocationStatusKind.ready);
            _onAcceptedFix?.call(fix);
          case DriverLocationClass.poorAccuracy:
            _emit(DriverLocationStatusKind.poorAccuracy);
          case DriverLocationClass.duplicate:
            break;
          case DriverLocationClass.invalid:
          case DriverLocationClass.impossibleSpeed:
          case DriverLocationClass.stale:
          case DriverLocationClass.future:
            _emit(DriverLocationStatusKind.unavailable);
        }
    }
  }

  DriverLocationStatusKind _statusForFailure(
    DriverLocationAcquisitionFailure failure,
  ) {
    return switch (failure) {
      DriverLocationAcquisitionFailure.permissionDenied =>
        DriverLocationStatusKind.permissionNeeded,
      DriverLocationAcquisitionFailure.permissionDeniedForever =>
        DriverLocationStatusKind.permissionBlocked,
      DriverLocationAcquisitionFailure.serviceDisabled =>
        DriverLocationStatusKind.servicesDisabled,
      DriverLocationAcquisitionFailure.unavailable =>
        DriverLocationStatusKind.unavailable,
    };
  }

  void _emit(DriverLocationStatusKind kind) {
    if (_status == kind) return;
    _status = kind;
    statusChangeCount++;
    _onStatus(kind);
  }

  void _log(String message, Map<String, Object?> metadata) {
    _logger.info(message, metadata: _safeLocationMetadata(metadata));
  }
}
