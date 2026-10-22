/// Passenger saved place ("favorite") — Phase 2 local feature.
///
/// Stored locally per authenticated uid (SecureStorage). Coordinates are
/// authoritative; [addressLabel] holds only a genuinely resolved label —
/// never an invented address.
class SavedPlace {
  const SavedPlace({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.addressLabel,
    this.placeId,
    required this.updatedAtMs,
  });

  /// 'home' | 'work' | uuid — stable identity for rename/remove.
  final String id;

  /// User-facing name (e.g. "Home", "Office") — user-authored, never a
  /// fabricated address.
  final String name;

  final double lat;
  final double lng;

  /// Genuinely resolved street/area label, or null when unavailable.
  final String? addressLabel;
  final String? placeId;
  final int updatedAtMs;

  bool get hasValidCoordinates =>
      lat.isFinite &&
      lng.isFinite &&
      lat >= -90 &&
      lat <= 90 &&
      lng >= -180 &&
      lng <= 180;

  /// Subtitle for list rows — genuine label only; null renders nothing
  /// rather than faking an address.
  String? get secondaryLabel {
    final trimmed = addressLabel?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'lat': lat,
        'lng': lng,
        if (addressLabel != null) 'addressLabel': addressLabel,
        if (placeId != null) 'placeId': placeId,
        'updatedAtMs': updatedAtMs,
      };

  static SavedPlace? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    final lat = raw['lat'];
    final lng = raw['lng'];
    final updatedAtMs = raw['updatedAtMs'];
    if (id is! String || id.isEmpty) return null;
    if (name is! String || name.trim().isEmpty) return null;
    if (lat is! num || lng is! num) return null;
    final place = SavedPlace(
      id: id,
      name: name,
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      addressLabel:
          raw['addressLabel'] is String ? raw['addressLabel'] as String : null,
      placeId: raw['placeId'] is String ? raw['placeId'] as String : null,
      updatedAtMs: updatedAtMs is num ? updatedAtMs.toInt() : 0,
    );
    return place.hasValidCoordinates ? place : null;
  }

  @override
  bool operator ==(Object other) =>
      other is SavedPlace &&
      other.id == id &&
      other.name == name &&
      other.lat == lat &&
      other.lng == lng &&
      other.addressLabel == addressLabel &&
      other.placeId == placeId &&
      other.updatedAtMs == updatedAtMs;

  @override
  int get hashCode =>
      Object.hash(id, name, lat, lng, addressLabel, placeId, updatedAtMs);
}

/// A previously confirmed destination — recorded only after the passenger
/// explicitly confirms it (never from an abandoned search).
class RecentDestination {
  const RecentDestination({
    required this.lat,
    required this.lng,
    this.label,
    this.placeId,
    required this.lastUsedMs,
  });

  final double lat;
  final double lng;

  /// Genuine resolved label, or null when the confirmed point had no name.
  final String? label;
  final String? placeId;
  final int lastUsedMs;

  bool get hasValidCoordinates =>
      lat.isFinite &&
      lng.isFinite &&
      lat >= -90 &&
      lat <= 90 &&
      lng >= -180 &&
      lng <= 180;

  /// Honest display label — never coordinates-as-address.
  String get displayLabel {
    final trimmed = label?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    return 'Pinned location';
  }

  Map<String, Object?> toJson() => {
        'lat': lat,
        'lng': lng,
        if (label != null) 'label': label,
        if (placeId != null) 'placeId': placeId,
        'lastUsedMs': lastUsedMs,
      };

  static RecentDestination? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final lat = raw['lat'];
    final lng = raw['lng'];
    final lastUsedMs = raw['lastUsedMs'];
    if (lat is! num || lng is! num) return null;
    final rec = RecentDestination(
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      label: raw['label'] is String ? raw['label'] as String : null,
      placeId: raw['placeId'] is String ? raw['placeId'] as String : null,
      lastUsedMs: lastUsedMs is num ? lastUsedMs.toInt() : 0,
    );
    return rec.hasValidCoordinates ? rec : null;
  }

  @override
  bool operator ==(Object other) =>
      other is RecentDestination &&
      other.lat == lat &&
      other.lng == lng &&
      other.label == label &&
      other.placeId == placeId &&
      other.lastUsedMs == lastUsedMs;

  @override
  int get hashCode => Object.hash(lat, lng, label, placeId, lastUsedMs);
}
