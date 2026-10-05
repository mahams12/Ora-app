import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../domain/location/driver_location_fix.dart';
import '../../domain/location/driver_location_source.dart';

/// Foreground driver GPS via the existing geolocator dependency.
///
/// [LocationAccuracy.high] is the L1 baseline. No distance filter and no
/// interval are set, so the operating system chooses the callback rate.
/// That rate is measured before any sampling policy is chosen.
///
/// Does not request background location and does not publish fixes.
class GeolocatorDriverLocationSource extends DriverLocationSource {
  const GeolocatorDriverLocationSource();

  @override
  Stream<DriverLocationReading> watch() {
    StreamSubscription<Position>? positionSub;
    var cancelled = false;
    late final StreamController<DriverLocationReading> controller;

    controller = StreamController<DriverLocationReading>(
      onCancel: () async {
        cancelled = true;
        await positionSub?.cancel();
      },
    );

    unawaited(
      _open(
        controller,
        isCancelled: () => cancelled,
        bind: (subscription) => positionSub = subscription,
      ),
    );
    return controller.stream;
  }

  @override
  Future<bool> openPermissionSettings() => Geolocator.openAppSettings();

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  Future<void> _open(
    StreamController<DriverLocationReading> controller, {
    required bool Function() isCancelled,
    required void Function(StreamSubscription<Position> subscription) bind,
  }) async {
    try {
      final failure = await _acquisitionFailure();
      if (isCancelled() || controller.isClosed) {
        await _close(controller);
        return;
      }
      if (failure != null) {
        _add(controller, DriverLocationFailureReading(failure));
        await _close(controller);
        return;
      }

      final subscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          ).listen(
            (position) {
              _add(
                controller,
                DriverLocationFixReading(_fixFromPosition(position)),
              );
            },
            onError: (Object error, StackTrace _) {
              _add(
                controller,
                DriverLocationFailureReading(_failureFromError(error)),
              );
            },
            cancelOnError: false,
          );
      if (isCancelled() || controller.isClosed) {
        await subscription.cancel();
        await _close(controller);
        return;
      }
      bind(subscription);
    } catch (error) {
      if (isCancelled() || controller.isClosed) return;
      _add(controller, DriverLocationFailureReading(_failureFromError(error)));
      await _close(controller);
    }
  }

  void _add(
    StreamController<DriverLocationReading> controller,
    DriverLocationReading reading,
  ) {
    if (controller.isClosed || !controller.hasListener) return;
    controller.add(reading);
  }

  Future<void> _close(
    StreamController<DriverLocationReading> controller,
  ) async {
    if (!controller.isClosed) {
      await controller.close();
    }
  }

  Future<DriverLocationAcquisitionFailure?> _acquisitionFailure() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return DriverLocationAcquisitionFailure.serviceDisabled;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      // Single system prompt per watch start — never loop automatically.
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      return DriverLocationAcquisitionFailure.permissionDenied;
    }
    if (permission == LocationPermission.deniedForever) {
      return DriverLocationAcquisitionFailure.permissionDeniedForever;
    }
    if (permission == LocationPermission.unableToDetermine) {
      return DriverLocationAcquisitionFailure.unavailable;
    }
    return null;
  }

  DriverLocationAcquisitionFailure _failureFromError(Object error) {
    if (error is PermissionDeniedException) {
      return DriverLocationAcquisitionFailure.permissionDenied;
    }
    if (error is LocationServiceDisabledException) {
      return DriverLocationAcquisitionFailure.serviceDisabled;
    }
    return DriverLocationAcquisitionFailure.unavailable;
  }

  DriverLocationFix _fixFromPosition(Position position) {
    return DriverLocationFix(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      speedKmh: driverLocationSpeedKmhFromMetersPerSecond(position.speed),
      headingDegrees: driverLocationHeadingDegrees(position.heading),
      altitudeMeters: driverLocationAltitudeMeters(position.altitude),
      timestamp: position.timestamp,
    );
  }
}
