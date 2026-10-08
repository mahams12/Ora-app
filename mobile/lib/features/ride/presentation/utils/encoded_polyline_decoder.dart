import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Google Encoded Polyline Algorithm Format decoder (MAP-1).
///
/// Isolated from UI widgets — returns an empty list on missing/invalid input
/// and never throws.
class EncodedPolylineDecoder {
  EncodedPolylineDecoder._();

  /// Decodes an encoded polyline into Google Maps [LatLng] points.
  static List<LatLng> decode(String? encoded) {
    final input = encoded?.trim();
    if (input == null || input.isEmpty) return const <LatLng>[];

    final coordinates = <LatLng>[];
    var index = 0;
    var lat = 0;
    var lng = 0;

    try {
      while (index < input.length) {
        var result = 0;
        var shift = 0;
        int b;
        do {
          if (index >= input.length) return const <LatLng>[];
          b = input.codeUnitAt(index++) - 63;
          result |= (b & 0x1f) << shift;
          shift += 5;
        } while (b >= 0x20);
        final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
        lat += dlat;

        result = 0;
        shift = 0;
        do {
          if (index >= input.length) return const <LatLng>[];
          b = input.codeUnitAt(index++) - 63;
          result |= (b & 0x1f) << shift;
          shift += 5;
        } while (b >= 0x20);
        final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
        lng += dlng;

        final latitude = lat / 1e5;
        final longitude = lng / 1e5;
        if (latitude < -90 ||
            latitude > 90 ||
            longitude < -180 ||
            longitude > 180) {
          return const <LatLng>[];
        }
        coordinates.add(LatLng(latitude, longitude));
      }
    } catch (_) {
      return const <LatLng>[];
    }

    return List<LatLng>.unmodifiable(coordinates);
  }
}
