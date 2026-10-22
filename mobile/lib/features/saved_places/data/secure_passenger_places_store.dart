import 'dart:convert';

import '../../../core/storage/secure_storage.dart';
import '../domain/entities/passenger_places.dart';
import '../domain/ports/passenger_places_store.dart';

/// [PassengerPlacesStore] backed by [SecureStorage] (Keychain/Keystore).
///
/// Why secure storage: it is the app's only durable local store and it is
/// wiped on logout (`AuthRepositoryImpl.logout` → `deleteAll`) — saved
/// places and recents can't leak into a different account that later signs
/// in on this device. Keys are additionally uid-scoped as a second guard.
///
/// Data is a small JSON list — no secrets, but encryption-at-rest is free.
/// Corrupt payloads decode to an empty list rather than throwing.
class SecurePassengerPlacesStore implements PassengerPlacesStore {
  SecurePassengerPlacesStore(this._storage);

  final SecureStorage _storage;

  static const _version = 'v1';

  String _savedKey(String uid) => 'ora.saved_places.$_version.$uid';
  String _recentKey(String uid) => 'ora.recent_destinations.$_version.$uid';

  @override
  Future<List<SavedPlace>> loadSavedPlaces({required String uid}) async {
    final raw = await _storage.read(key: _savedKey(uid));
    if (raw == null) return const [];
    return _decodeList(raw, SavedPlace.tryFromJson);
  }

  @override
  Future<void> writeSavedPlaces({
    required String uid,
    required List<SavedPlace> places,
  }) {
    return _storage.write(
      key: _savedKey(uid),
      value: jsonEncode(places.map((p) => p.toJson()).toList()),
    );
  }

  @override
  Future<List<RecentDestination>> loadRecentDestinations({
    required String uid,
  }) async {
    final raw = await _storage.read(key: _recentKey(uid));
    if (raw == null) return const [];
    return _decodeList(raw, RecentDestination.tryFromJson);
  }

  @override
  Future<void> writeRecentDestinations({
    required String uid,
    required List<RecentDestination> recents,
  }) {
    return _storage.write(
      key: _recentKey(uid),
      value: jsonEncode(recents.map((r) => r.toJson()).toList()),
    );
  }

  List<T> _decodeList<T>(String raw, T? Function(Object?) decode) {
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! List) return const [];
      return [
        for (final item in parsed)
          if (decode(item) case final T value) value,
      ];
    } on FormatException {
      return const [];
    }
  }
}
