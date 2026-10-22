import '../../domain/models/resolved_passenger_location.dart';
import '../../domain/ports/device_geocoder_port.dart';
import '../../domain/ports/place_search_port.dart';

/// Places-first reverse geocode with a device-geocoder fallback.
///
/// `autocomplete`/`resolvePlace` always delegate to [primary] — the platform
/// geocoder cannot do those. Only `reverseGeocode` falls back, and only when
/// the primary throws or returns an unusable label.
class FallbackPlaceSearch implements PlaceSearchPort {
  const FallbackPlaceSearch({
    required PlaceSearchPort primary,
    required DeviceGeocoderPort deviceGeocoder,
  })  : _primary = primary,
        _device = deviceGeocoder;

  final PlaceSearchPort _primary;
  final DeviceGeocoderPort _device;

  @override
  Future<List<PlaceSuggestion>> autocomplete({
    required String query,
    required String sessionToken,
  }) =>
      _primary.autocomplete(query: query, sessionToken: sessionToken);

  @override
  Future<ResolvedPassengerLocation> resolvePlace({
    required String placeId,
    required String sessionToken,
  }) =>
      _primary.resolvePlace(placeId: placeId, sessionToken: sessionToken);

  @override
  Future<ResolvedPassengerLocation> reverseGeocode({
    required double lat,
    required double lng,
  }) async {
    PlaceSearchException? primaryError;
    try {
      final result = await _primary.reverseGeocode(lat: lat, lng: lng);
      if (result.address?.trim().isNotEmpty == true) return result;
    } on PlaceSearchException catch (e) {
      primaryError = e;
    }
    final label = await _device.localityLabel(lat: lat, lng: lng);
    if (label != null && label.trim().isNotEmpty) {
      return ResolvedPassengerLocation(
        lat: lat,
        lng: lng,
        address: label,
        source: PassengerLocationSource.gps,
      );
    }
    throw primaryError ??
        const PlaceSearchException(
          PlaceSearchFailureKind.empty,
          'No locality available.',
        );
  }
}
