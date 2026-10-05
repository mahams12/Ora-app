import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../domain/location/driver_location_lifecycle.dart';
import '../../domain/location/driver_location_status.dart';
import '../view_models/driver_assigned_ride_view_model.dart';

/// Local GPS session for one assigned ride. Auto-disposed with the screen.
class DriverLocationSession
    extends AutoDisposeFamilyNotifier<DriverLocationStatusKind, String> {
  late DriverLocationLifecycleController _controller;
  var _alive = true;

  @override
  DriverLocationStatusKind build(String arg) {
    _alive = true;
    _controller = DriverLocationLifecycleController(
      source: ref.read(driverLocationSourceProvider),
      logger: ref.read(appLoggerProvider),
      onStatus: (kind) {
        if (!_alive || state == kind) return;
        state = kind;
      },
    );

    ref.onDispose(() {
      _alive = false;
      _controller.dispose();
    });

    ref.listen<String?>(
      driverAssignedRideViewModelProvider(arg).select((s) => s.ride?.state),
      (previous, next) {
        _controller.onRide(rideId: arg, rideState: next);
      },
    );

    Future<void>.microtask(() {
      if (!_alive) return;
      final rideState = ref.read(
        driverAssignedRideViewModelProvider(arg).select((s) => s.ride?.state),
      );
      _controller.onRide(rideId: arg, rideState: rideState);
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
      case AppLifecycleState.inactive:
        break;
    }
  }

  /// Cancels the watch before navigation finishes tearing the screen down.
  void onSignedOut() {
    if (!_alive) return;
    _controller.onSignedOut();
  }

  /// User-initiated recovery (allow location / open settings / try again).
  Future<void> onUserRecoveryAction() async {
    if (!_alive) return;
    await _controller.onUserRecoveryAction();
  }
}

final driverLocationSessionProvider = NotifierProvider.autoDispose
    .family<DriverLocationSession, DriverLocationStatusKind, String>(
      DriverLocationSession.new,
    );
