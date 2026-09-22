import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../domain/models/resolved_passenger_location.dart';
import '../../domain/ports/device_location_port.dart';

class GeolocatorDeviceLocation implements DeviceLocationPort {
  const GeolocatorDeviceLocation({
    this.timeLimit = const Duration(seconds: 15),
  });

  final Duration timeLimit;

  @override
  Future<ResolvedPassengerLocation> getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const DeviceLocationException(
        DeviceLocationFailureKind.serviceDisabled,
        'Location services are turned off.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const DeviceLocationException(
        DeviceLocationFailureKind.permissionDenied,
        'Location permission was denied.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const DeviceLocationException(
        DeviceLocationFailureKind.permissionDeniedForever,
        'Location permission is permanently denied.',
      );
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeLimit,
        ),
      );
      final location = ResolvedPassengerLocation(
        lat: position.latitude,
        lng: position.longitude,
        source: PassengerLocationSource.gps,
        address: 'Current location',
      );
      if (!location.hasValidCoordinates) {
        throw const DeviceLocationException(
          DeviceLocationFailureKind.unavailable,
          'Received invalid coordinates.',
        );
      }
      return location;
    } on DeviceLocationException {
      rethrow;
    } on TimeoutException {
      throw const DeviceLocationException(
        DeviceLocationFailureKind.timeout,
        'Timed out waiting for GPS.',
      );
    } catch (_) {
      throw const DeviceLocationException(
        DeviceLocationFailureKind.unavailable,
        'Could not obtain current location.',
      );
    }
  }
}
