import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../domain/location/driver_location_lifecycle.dart';
import '../../domain/location/driver_location_status.dart';
import '../../domain/location/driver_trip_location_publisher.dart';
import '../view_models/driver_assigned_ride_view_model.dart';

/// Local GPS session + trip location publisher for one assigned ride.
///
/// Auto-disposed with the screen. No keepAlive. No Flutter RTDB writes.
class DriverLocationSession
    extends AutoDisposeFamilyNotifier<DriverLocationStatusKind, String> {
  late DriverLocationLifecycleController _controller;
  late DriverTripLocationPublisher _publisher;
  var _alive = true;

  /// Test/metrics access to the session-owned publisher.
  DriverTripLocationPublisher get publisher => _publisher;

  @override
  DriverLocationStatusKind build(String arg) {
    _alive = true;
    _publisher = DriverTripLocationPublisher(
      rideId: arg,
      remote: ref.read(driverLocationRemoteDataSourceProvider),
      logger: ref.read(appLoggerProvider),
    );

    _controller = DriverLocationLifecycleController(
      source: ref.read(driverLocationSourceProvider),
      logger: ref.read(appLoggerProvider),
      onStatus: (kind) {
        if (!_alive || state == kind) return;
        state = kind;
      },
      onAcceptedFix: (fix) {
        if (!_alive) return;
        _publisher.onAcceptedFix(fix);
      },
      onWatchStarted: () {
        if (!_alive) return;
        _publisher.onWatchStarted();
      },
      onWatchStopped: (reason) {
        if (!_alive) return;
        _publisher.onWatchStopped(reason);
      },
    );

    // AutoDispose with the assigned-ride screen: leave/pop must stop GPS.
    // holdRestart already covers permission-sheet lifecycle without keepAlive.
    ref.onDispose(() {
      _alive = false;
      _publisher.dispose();
      _controller.dispose();
    });

    ref.listen<String?>(
      driverAssignedRideViewModelProvider(arg).select((s) => s.ride?.state),
      (previous, next) {
        _controller.onRide(rideId: arg, rideState: next);
        _publisher.onRideState(next);
        if (next != null && !driverLocationShouldWatch(next)) {
          // Permanent stop for terminal/completed on this ride session.
          if (_isTerminalPublishState(next)) {
            _publisher.stop(reason: 'ride_${next.toLowerCase()}');
          }
        }
      },
    );

    Future<void>.microtask(() {
      if (!_alive) return;
      final rideState = ref.read(
        driverAssignedRideViewModelProvider(arg).select((s) => s.ride?.state),
      );
      _controller.onRide(rideId: arg, rideState: rideState);
      _publisher.onRideState(rideState);
    });

    return DriverLocationStatusKind.hidden;
  }

  int get statusChangeCount => _controller.statusChangeCount;

  void onAppLifecycle(AppLifecycleState lifecycle) {
    if (!_alive) return;
    switch (lifecycle) {
      case AppLifecycleState.resumed:
        _controller.onForeground();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _controller.onBackground();
        _publisher.onWatchStopped('background');
      case AppLifecycleState.inactive:
        break;
    }
  }

  /// Cancels the watch before navigation finishes tearing the screen down.
  void onSignedOut() {
    if (!_alive) return;
    _controller.onSignedOut();
    _publisher.stop(reason: 'sign_out');
  }

  /// User-initiated recovery (allow location / open settings / try again).
  Future<void> onUserRecoveryAction() async {
    if (!_alive) return;
    await _controller.onUserRecoveryAction();
  }

  bool _isTerminalPublishState(String state) {
    switch (state.toUpperCase()) {
      case 'CANCELLED':
      case 'NO_SHOW':
      case 'EXPIRED':
      case 'RIDE_COMPLETED':
      case 'RIDE_CLOSED':
        return true;
      default:
        return false;
    }
  }
}

final driverLocationSessionProvider = NotifierProvider.autoDispose
    .family<DriverLocationSession, DriverLocationStatusKind, String>(
      DriverLocationSession.new,
    );
