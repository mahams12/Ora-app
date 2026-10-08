import '../../../domain/entities/ride.dart';

/// Human-readable place label for ride cards and summaries.
///
/// Never invents localities. Never exposes raw coordinates to normal users.
/// Maps the legacy GPS placeholder `"Current location"` to a graceful fallback.
String rideCardLocationLabel(
  LatLngPoint point, {
  String fallback = 'Location selected',
}) {
  return humanReadablePlaceLabel(point.address, fallback: fallback);
}

/// Shared place-name sanitizer for stored addresses and resolved GPS labels.
String humanReadablePlaceLabel(
  String? address, {
  String fallback = 'Location selected',
}) {
  final trimmed = address?.trim();
  if (trimmed == null || trimmed.isEmpty) return fallback;
  if (trimmed.toLowerCase() == 'current location') return fallback;
  return trimmed;
}
