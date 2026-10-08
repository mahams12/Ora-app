/// Builds a human-readable locality label from Places API (New) nearby results.
///
/// Pure parsing — no network. Never invents localities; returns null when no
/// real place data is available.
String? localityLabelFromPlacesNearby(List<dynamic> places) {
  for (final raw in places) {
    if (raw is! Map) continue;
    final fromComponents = _fromAddressComponents(raw['addressComponents']);
    if (fromComponents != null) return fromComponents;
  }

  for (final raw in places) {
    if (raw is! Map) continue;
    final shortened = _shortFormattedAddress(raw['formattedAddress']);
    if (shortened != null) return shortened;
  }

  for (final raw in places) {
    if (raw is! Map) continue;
    final displayName = raw['displayName'];
    if (displayName is Map) {
      final text = displayName['text']?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
  }

  return null;
}

String? _fromAddressComponents(Object? componentsRaw) {
  if (componentsRaw is! List) return null;

  String? neighborhood;
  String? sublocalityLevel1;
  String? sublocalityOther;
  String? locality;
  String? admin2;

  for (final c in componentsRaw) {
    if (c is! Map) continue;
    final types = c['types'];
    if (types is! List) continue;
    final typeSet = types.map((t) => t.toString()).toSet();
    // Places API (New) uses longText; Geocoding JSON uses long_name.
    final longName = (c['longText'] ?? c['long_name'])?.toString().trim();
    if (longName == null || longName.isEmpty) continue;

    if (typeSet.contains('neighborhood')) {
      neighborhood ??= longName;
    }
    if (typeSet.contains('sublocality_level_1')) {
      sublocalityLevel1 ??= longName;
    } else if (typeSet.contains('sublocality') &&
        !typeSet.contains('sublocality_level_2') &&
        !typeSet.contains('sublocality_level_3')) {
      sublocalityOther ??= longName;
    }
    if (typeSet.contains('locality')) {
      locality ??= longName;
    }
    if (typeSet.contains('administrative_area_level_2')) {
      admin2 ??= longName;
    }
  }

  // Prefer named locality areas (Gulberg III) over micro-neighborhoods (Block N).
  final primary = sublocalityLevel1 ?? neighborhood ?? sublocalityOther;
  final secondary = locality ?? admin2;

  if (primary != null &&
      secondary != null &&
      primary.toLowerCase() != secondary.toLowerCase()) {
    return '$primary, $secondary';
  }
  if (primary != null) return primary;
  if (locality != null &&
      admin2 != null &&
      locality.toLowerCase() != admin2.toLowerCase()) {
    return '$locality, $admin2';
  }
  if (locality != null) return locality;
  return null;
}

String? _shortFormattedAddress(Object? formattedRaw) {
  final formatted = formattedRaw?.toString().trim();
  if (formatted == null || formatted.isEmpty) return null;

  final parts = formatted
      .split(',')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .where((p) => !_looksLikePlusCode(p))
      .toList();
  if (parts.isEmpty) return null;
  if (parts.length == 1) return parts.first;
  // Prefer last two meaningful segments when first looks like a street/route.
  if (parts.length >= 3) {
    final a = parts[parts.length - 2];
    final b = parts[parts.length - 1];
    // Drop country-only trailing "Pakistan" when we have a better pair.
    if (b.toLowerCase() == 'pakistan' && parts.length >= 3) {
      return '${parts[parts.length - 3]}, ${parts[parts.length - 2]}';
    }
    return '$a, $b';
  }
  return '${parts[0]}, ${parts[1]}';
}

bool _looksLikePlusCode(String part) {
  // Open Location Code / plus-code fragments e.g. "9688+HR"
  return RegExp(r'^[A-Z0-9]{4,}\+[A-Z0-9]+', caseSensitive: false)
      .hasMatch(part);
}
