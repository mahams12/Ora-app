import 'package:geocoding/geocoding.dart' as geo;

import '../../domain/models/resolved_passenger_location.dart';
import '../../domain/ports/place_search_port.dart';
import 'geocoding_device_geocoder.dart';

/// Platform-geocoder place search — the last-resort [PlaceSearchPort] when
/// the primary network provider (Nominatim/Places) fails or is unreachable.
///
/// Uses the device's own `Geocoder` backend (Google Play Services on most
/// Android builds, platform service on iOS) — zero API key, zero billing.
///
/// Honesty constraints:
/// - Suggestions carry the user's own query text as the label — the device
///   geocoder returns coordinates only, so no address is invented.
/// - placeId encodes coordinates + the query (`geo:<lat>:<lng>:<q>`) so
///   `resolvePlace` needs no second call.
/// - When the platform geocoder is absent (some ROMs / no Play Services)
///   throws [PlaceSearchFailureKind.unavailable] — callers surface an
///   honest error and the manual map-pin path remains available.
class DeviceGeocoderPlaceSearch implements PlaceSearchPort {
  DeviceGeocoderPlaceSearch({geo.Geocoding? geocoding}) : _injected = geocoding;

  final geo.Geocoding? _injected;
  geo.Geocoding? _resolved;
  geo.Geocoding get _geocoding =>
      _resolved ??= _injected ?? geo.Geocoding();

  static const _idPrefix = 'geo:';
  static const _maxSuggestions = 3;

  @override
  Future<List<PlaceSuggestion>> autocomplete({
    required String query,
    required String sessionToken,
  }) async {
    final q = query.trim();
    if (q.length < 3) return const [];
    try {
      if (!await _geocoding.isPresent()) {
        throw const PlaceSearchException(
          PlaceSearchFailureKind.unavailable,
          'Device geocoder unavailable.',
        );
      }
      final locations = await _geocoding.locationFromAddress(q);
      final out = <PlaceSuggestion>[];
      for (final loc in locations) {
        final lat = loc.latitude;
        final lng = loc.longitude;
        if (lat.abs() > 90 || lng.abs() > 180) continue;
        final id = '$_idPrefix$lat:$lng:$q';
        if (out.any((s) => s.placeId == id)) continue;
        out.add(PlaceSuggestion(
          placeId: id,
          primaryText: q,
          secondaryText: 'Approximate match · device geocoder',
        ));
        if (out.length >= _maxSuggestions) break;
      }
      return out;
    } on PlaceSearchException {
      rethrow;
    } catch (_) {
      throw const PlaceSearchException(
        PlaceSearchFailureKind.unavailable,
        'Device geocoder lookup isn\'t available right now.',
      );
    }
  }

  @override
  Future<ResolvedPassengerLocation> resolvePlace({
    required String placeId,
    required String sessionToken,
  }) async {
    final id = placeId.trim();
    if (!id.startsWith(_idPrefix)) {
      throw const PlaceSearchException(
        PlaceSearchFailureKind.invalid,
        'Unknown place reference.',
      );
    }
    final rest = id.substring(_idPrefix.length);
    final firstColon = rest.indexOf(':');
    final secondColon =
        firstColon < 0 ? -1 : rest.indexOf(':', firstColon + 1);
    final lat = firstColon < 0
        ? null
        : double.tryParse(rest.substring(0, firstColon));
    final lng = secondColon < 0
        ? null
        : double.tryParse(rest.substring(firstColon + 1, secondColon));
    final name = secondColon < 0 ? '' : rest.substring(secondColon + 1);
    if (lat == null || lng == null) {
      throw const PlaceSearchException(
        PlaceSearchFailureKind.invalid,
        'Malformed place reference.',
      );
    }
    return ResolvedPassengerLocation(
      lat: lat,
      lng: lng,
      address: name.isEmpty ? null : name,
      placeId: id,
      source: PassengerLocationSource.place,
    );
  }

  @override
  Future<ResolvedPassengerLocation> reverseGeocode({
    required double lat,
    required double lng,
  }) async {
    try {
      if (!await _geocoding.isPresent()) {
        throw const PlaceSearchException(
          PlaceSearchFailureKind.unavailable,
          'Device geocoder unavailable.',
        );
      }
      final marks = await _geocoding.placemarkFromCoordinates(lat, lng);
      for (final mark in marks) {
        final label = devicePlacemarkLabel(mark);
        if (label != null) {
          return ResolvedPassengerLocation(
            lat: lat,
            lng: lng,
            address: label,
            source: PassengerLocationSource.gps,
          );
        }
      }
      throw const PlaceSearchException(
        PlaceSearchFailureKind.empty,
        'No place found for coordinates.',
      );
    } on PlaceSearchException {
      rethrow;
    } catch (_) {
      throw const PlaceSearchException(
        PlaceSearchFailureKind.unavailable,
        'Device geocoder lookup isn\'t available right now.',
      );
    }
  }
}
