import 'driver_location_fix.dart';

/// Why a foreground watch could not produce a fix.
enum DriverLocationAcquisitionFailure {
  permissionDenied,
  permissionDeniedForever,
  serviceDisabled,
  unavailable,
}

sealed class DriverLocationReading {
  const DriverLocationReading();
}

final class DriverLocationFixReading extends DriverLocationReading {
  const DriverLocationFixReading(this.fix);

  final DriverLocationFix fix;
}

final class DriverLocationFailureReading extends DriverLocationReading {
  const DriverLocationFailureReading(this.failure);

  final DriverLocationAcquisitionFailure failure;
}

/// Foreground GPS watch. Implementations must not request background location
/// and must not publish samples over the network.
abstract class DriverLocationSource {
  const DriverLocationSource();

  /// A new watch. The caller cancels the subscription to stop it.
  ///
  /// The stream emits domain readings. It must not throw permission or
  /// service failures as uncaught errors; those are
  /// [DriverLocationFailureReading] events.
  Stream<DriverLocationReading> watch();

  /// Opens the system app-settings page so the user can change location
  /// permission. Returns whether the settings screen was opened.
  Future<bool> openPermissionSettings() async => false;

  /// Opens system location-services settings when location is turned off.
  Future<bool> openLocationSettings() async => false;
}
