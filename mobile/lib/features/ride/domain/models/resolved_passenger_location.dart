import '../entities/ride.dart';

/// How a passenger location was obtained (UX / telemetry only).
enum PassengerLocationSource {
  gps,
  place,
  mapPin,
  savedPlace,
}

/// Passenger-confirmed (or proposed) location — Phase 4A.
///
/// Durable create body still uses [LatLngPoint] only (`lat`/`lng`/`address?`).
/// Provider SDKs must not leak into this type.
class ResolvedPassengerLocation {
  const ResolvedPassengerLocation({
    required this.lat,
    required this.lng,
    required this.source,
    this.address,
    this.placeId,
  });

  final double lat;
  final double lng;
  final String? address;
  final String? placeId;
  final PassengerLocationSource source;

  bool get hasValidCoordinates =>
      lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;

  LatLngPoint toLatLngPoint() => LatLngPoint(
        lat: lat,
        lng: lng,
        address: address,
      );

  String get displayLabel {
    final trimmed = address?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
  }

  @override
  bool operator ==(Object other) {
    return other is ResolvedPassengerLocation &&
        other.lat == lat &&
        other.lng == lng &&
        other.address == address &&
        other.placeId == placeId &&
        other.source == source;
  }

  @override
  int get hashCode => Object.hash(lat, lng, address, placeId, source);
}

/// Autocomplete row before Place Details resolves coordinates.
class PlaceSuggestion {
  const PlaceSuggestion({
    required this.placeId,
    required this.primaryText,
    this.secondaryText,
  });

  final String placeId;
  final String primaryText;
  final String? secondaryText;

  String get displayText {
    final secondary = secondaryText?.trim();
    if (secondary == null || secondary.isEmpty) return primaryText;
    return '$primaryText, $secondary';
  }

  @override
  bool operator ==(Object other) {
    return other is PlaceSuggestion &&
        other.placeId == placeId &&
        other.primaryText == primaryText &&
        other.secondaryText == secondaryText;
  }

  @override
  int get hashCode => Object.hash(placeId, primaryText, secondaryText);
}
