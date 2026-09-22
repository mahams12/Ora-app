import '../models/resolved_passenger_location.dart';

enum DeviceLocationFailureKind {
  permissionDenied,
  permissionDeniedForever,
  serviceDisabled,
  timeout,
  unavailable,
}

class DeviceLocationException implements Exception {
  const DeviceLocationException(this.kind, [this.message]);

  final DeviceLocationFailureKind kind;
  final String? message;

  @override
  String toString() => 'DeviceLocationException($kind, $message)';
}

/// One-shot passenger GPS (no background tracking).
abstract class DeviceLocationPort {
  Future<ResolvedPassengerLocation> getCurrentLocation();
}
