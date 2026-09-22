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

/// Places autocomplete + details. Implementations may use Google Places HTTP.
abstract class PlaceSearchPort {
  Future<List<PlaceSuggestion>> autocomplete({
    required String query,
    required String sessionToken,
  });

  Future<ResolvedPassengerLocation> resolvePlace({
    required String placeId,
    required String sessionToken,
  });
}
