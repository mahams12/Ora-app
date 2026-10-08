import '../models/resolved_passenger_location.dart';

enum PlaceSearchFailureKind {
  notConfigured,
  network,
  empty,
  invalid,
  unavailable,
}

class PlaceSearchException implements Exception {
  const PlaceSearchException(this.kind, [this.message]);

  final PlaceSearchFailureKind kind;
  final String? message;

  @override
  String toString() => 'PlaceSearchException($kind, $message)';
}

/// Places autocomplete + details + reverse geocode.
/// Implementations may use Google Places / Geocoding HTTP (no new SDK).
abstract class PlaceSearchPort {
  Future<List<PlaceSuggestion>> autocomplete({
    required String query,
    required String sessionToken,
  });

  Future<ResolvedPassengerLocation> resolvePlace({
    required String placeId,
    required String sessionToken,
  });

  /// Resolve GPS coordinates to a human-readable locality/place name.
  ///
  /// Coordinates remain authoritative; the returned [address] is display-only.
  /// Throws [PlaceSearchException] on failure — callers must soft-fail.
  Future<ResolvedPassengerLocation> reverseGeocode({
    required double lat,
    required double lng,
  });
}
