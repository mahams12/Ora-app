/// Interim passenger city for pricingRules / create (Phase 5C).
///
/// Freeze allows: suggested locality from Places address components
/// (normalized slug), shown for confirm — not IP, not silent hardcode.
library;

/// Major PK localities used as interim explicit options when inference fails.
const kPassengerCityOptions = <({String id, String label})>[
  (id: 'lahore', label: 'Lahore'),
  (id: 'karachi', label: 'Karachi'),
  (id: 'islamabad', label: 'Islamabad'),
  (id: 'rawalpindi', label: 'Rawalpindi'),
  (id: 'faisalabad', label: 'Faisalabad'),
  (id: 'multan', label: 'Multan'),
  (id: 'peshawar', label: 'Peshawar'),
  (id: 'quetta', label: 'Quetta'),
];

/// Normalize a city id to backend slug shape (lowercase, hyphenated words).
String? normalizePassengerCitySlug(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim().toLowerCase();
  if (trimmed.isEmpty) return null;
  final collapsed = trimmed
      .replaceAll(RegExp(r'[^a-z0-9\s-]'), ' ')
      .replaceAll(RegExp(r'\s+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  if (collapsed.isEmpty) return null;
  if (!RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(collapsed)) {
    return null;
  }
  return collapsed;
}

/// Suggest a city slug from a Places/GPS display address.
String? suggestCitySlugFromAddress(String? address) {
  if (address == null || address.trim().isEmpty) return null;
  final lower = address.toLowerCase();
  for (final city in kPassengerCityOptions) {
    final needle = city.label.toLowerCase();
    if (lower.contains(needle)) {
      return city.id;
    }
  }
  return null;
}

/// Prefer destination address, then pickup — both are passenger-confirmed.
String? suggestCitySlugFromTrip({
  String? pickupAddress,
  String? destinationAddress,
}) {
  return suggestCitySlugFromAddress(destinationAddress) ??
      suggestCitySlugFromAddress(pickupAddress);
}

String? passengerCityLabel(String? slug) {
  if (slug == null) return null;
  for (final c in kPassengerCityOptions) {
    if (c.id == slug) return c.label;
  }
  return slug;
}
