import 'dart:math' as math;

import 'entities/passenger_places.dart';

/// Bounds + dedup policy for saved places and recent destinations.
/// Pure functions — unit-tested without storage.
const kMaxSavedPlaces = 20;
const kMaxRecentDestinations = 8;
const kMaxPlaceNameLength = 40;

/// Two entries are "the same place" when they share a non-empty placeId or
/// sit within [kSamePlaceMeters] of each other.
const kSamePlaceMeters = 75.0;

/// Reserved ids for the canonical slots — one Home and one Work per account.
const kHomePlaceId = 'home';
const kWorkPlaceId = 'work';

/// Returns the normalized name, or null when the raw input is unusable.
String? normalizePlaceName(String raw) {
  final trimmed = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (trimmed.isEmpty) return null;
  if (trimmed.length > kMaxPlaceNameLength) {
    return trimmed.substring(0, kMaxPlaceNameLength);
  }
  return trimmed;
}

bool isSamePlace(
  ({double lat, double lng, String? placeId}) a,
  ({double lat, double lng, String? placeId}) b,
) {
  final aId = a.placeId?.trim();
  final bId = b.placeId?.trim();
  if (aId != null &&
      aId.isNotEmpty &&
      bId != null &&
      bId.isNotEmpty &&
      aId == bId) {
    return true;
  }
  return _distanceMeters((lat: a.lat, lng: a.lng), (lat: b.lat, lng: b.lng)) <=
      kSamePlaceMeters;
}

/// Upsert: same [SavedPlace.id] replaces (rename/re-pin); otherwise append.
/// Home/Work uniqueness falls out of their fixed ids.
List<SavedPlace> upsertSavedPlace(List<SavedPlace> places, SavedPlace place) {
  final next = <SavedPlace>[
    for (final p in places)
      if (p.id != place.id) p,
    place,
  ];
  // Keep Home/Work first, then most-recently-updated customs.
  next.sort((a, b) {
    int rank(String id) => switch (id) {
          kHomePlaceId => 0,
          kWorkPlaceId => 1,
          _ => 2,
        };
    final r = rank(a.id).compareTo(rank(b.id));
    if (r != 0) return r;
    return b.updatedAtMs.compareTo(a.updatedAtMs);
  });
  if (next.length > kMaxSavedPlaces) {
    next.length = kMaxSavedPlaces;
  }
  return next;
}

/// Push a confirmed destination to the front, dropping duplicates of the
/// same place and capping the list. Most-recently-used first.
List<RecentDestination> pushRecentDestination(
  List<RecentDestination> recents,
  RecentDestination next, {
  int cap = kMaxRecentDestinations,
}) {
  final out = <RecentDestination>[
    next,
    for (final r in recents)
      if (!isSamePlace(
        (lat: r.lat, lng: r.lng, placeId: r.placeId),
        (lat: next.lat, lng: next.lng, placeId: next.placeId),
      ))
        r,
  ];
  if (out.length > cap) {
    out.length = cap;
  }
  return out;
}

double _distanceMeters(
  ({double lat, double lng}) a,
  ({double lat, double lng}) b,
) {
  const earthRadiusM = 6371000.0;
  final lat1 = a.lat * math.pi / 180;
  final lat2 = b.lat * math.pi / 180;
  final dLat = (b.lat - a.lat) * math.pi / 180;
  final dLon = (b.lng - a.lng) * math.pi / 180;
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * earthRadiusM * math.asin(math.sqrt(h));
}
