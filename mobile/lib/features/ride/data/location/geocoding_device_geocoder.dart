import 'package:geocoding/geocoding.dart' as geo;

import '../../domain/ports/device_geocoder_port.dart';

/// Pick the most specific honest label parts from a platform [geo.Placemark].
///
/// Order: street detail (name/thoroughfare) → sub-locality → locality →
/// sub-admin → admin. Never fabricates; returns null when nothing usable.
String? devicePlacemarkLabel(geo.Placemark p) {
  final parts = <String>[];
  void add(String? v) {
    final t = v?.trim();
    if (t != null && t.isNotEmpty && !parts.contains(t)) parts.add(t);
  }

  // `name` on Android Geocoder is often the street address or a plus code;
  // keep it but prefer pairing it with locality context.
  add(p.name);
  add(p.thoroughfare);
  add(p.subLocality);
  add(p.locality);
  add(p.subAdministrativeArea);
  if (parts.isEmpty) add(p.administrativeArea);

  // Cap at 3 parts — longer strings are noise for a label.
  final label = parts.take(3).join(', ');
  return label.isEmpty ? null : label;
}

/// [DeviceGeocoderPort] on the `geocoding` plugin (Android `Geocoder`,
/// iOS `CLGeocoder`). Zero billing/quota — the platform resolves locally.
class GeocodingDeviceGeocoder implements DeviceGeocoderPort {
  // Lazy: geo.Geocoding() touches the platform channel at construction —
  // building it eagerly would crash unit tests (no plugin instance) and any
  // container that wires this port but never calls it.
  GeocodingDeviceGeocoder({geo.Geocoding? geocoding})
      : _injected = geocoding;

  final geo.Geocoding? _injected;
  geo.Geocoding? _resolved;
  geo.Geocoding get _geocoding =>
      _resolved ??= _injected ?? geo.Geocoding();

  @override
  Future<String?> localityLabel({
    required double lat,
    required double lng,
  }) async {
    try {
      final geocoding = _geocoding;
      final present = await geocoding.isPresent();
      if (!present) return null;
      final marks = await geocoding.placemarkFromCoordinates(lat, lng);
      for (final mark in marks) {
        final label = devicePlacemarkLabel(mark);
        if (label != null) return label;
      }
      return null;
    } catch (_) {
      // Platform geocoder absent/disabled — callers treat as "no fallback".
      return null;
    }
  }
}
