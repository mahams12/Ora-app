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
class DriverLocationLifecycleController {
  DriverLocationLifecycleController({
    required DriverLocationSource source,
    required AppLogger logger,
    required void Function(DriverLocationStatusKind kind) onStatus,
    DriverLocationClassifier classifier = const DriverLocationClassifier(),
    DateTime Function()? now,
  }) : _source = source,
       _logger = logger,
       _onStatus = onStatus,
       _classifier = classifier,
       _now = now ?? DateTime.now;

  final DriverLocationSource _source;
  final AppLogger _logger;
  final void Function(DriverLocationStatusKind kind) _onStatus;
  final DriverLocationClassifier _classifier;
  final DateTime Function() _now;

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
    final changed = _rideId != rideId || _rideState != rideState;
    _rideId = rideId;
    _rideState = rideState;
    if (changed) _holdRestart = false;
    _reconcile();
  }

  void onBackground() {
    _foreground = false;
    _holdRestart = false;
    _stop('background');
  }

  void onForeground() {
    _foreground = true;
    // Returning from system settings: allow one reconcile attempt.
    _holdRestart = false;
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
      _holdRestart = false;
      _stop('inactive');
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
      },
      cancelOnError: false,
    );
    _subscription = subscription;
    _emit(DriverLocationStatusKind.acquiring);
  }

  void _stop(String reason) {
    _generation++;
    _lastAccepted = null;
    _watchStartedAt = null;
    _loggedFirstCallback = false;
    _loggedFirstAccepted = false;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
      _log('location_watch_stopped', {'rideId': _rideId, 'reason': reason});
    }
    // Keep visible recovery statuses if the ride still wants a watch and we
    // are holding for user action; otherwise clear.
    if (!_wantsWatch || !_holdRestart) {
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
