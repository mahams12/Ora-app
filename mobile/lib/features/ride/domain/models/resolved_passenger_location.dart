import '../entities/ride.dart';

/// How a passenger location was obtained (UX / telemetry only).
enum PassengerLocationSource {
  gps,
  place,
  mapPin,
  savedPlace,
  recent,
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
    this.displayName,
    this.horizontalAccuracyMeters,
  });

  final double lat;
  final double lng;
  final String? address;
  final String? placeId;
  final PassengerLocationSource source;

  /// GPS horizontal fix accuracy in metres, when the provider reports it.
  /// Fix-quality metadata only — deliberately excluded from `==`/`hashCode`
  /// and never used as address accuracy.
  final double? horizontalAccuracyMeters;

  /// User-assigned label (e.g. a saved-place name like "Home") — UI display
  /// only. Never sent as `address` in the ride create body; a custom name
  /// is not a resolved address.
  final String? displayName;

  bool get hasValidCoordinates =>
      lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;

  LatLngPoint toLatLngPoint() => LatLngPoint(
        lat: lat,
        lng: lng,
        address: address,
      );

  /// Human-readable label for UI. Never exposes raw coordinates.
  String get displayLabel {
    final named = displayName?.trim();
    if (named != null && named.isNotEmpty) return named;
    final trimmed = address?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      if (trimmed.toLowerCase() == 'current location') {
        return 'Location selected';
      }
      return trimmed;
    }
    return 'Location selected';
  }

  @override
  bool operator ==(Object other) {
    return other is ResolvedPassengerLocation &&
        other.lat == lat &&
        other.lng == lng &&
        other.address == address &&
        other.placeId == placeId &&
        other.source == source &&
        other.displayName == displayName;
  }

  @override
  int get hashCode =>
      Object.hash(lat, lng, address, placeId, source, displayName);
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
