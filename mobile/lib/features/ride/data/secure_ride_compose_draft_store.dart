import 'dart:convert';

import '../../../core/storage/secure_storage.dart';
import '../domain/models/ride_compose_draft.dart';
import '../domain/ports/ride_compose_draft_store.dart';

/// [RideComposeDraftStore] backed by [SecureStorage] (Keychain/Keystore).
///
/// Same rationale as saved places: SecureStorage is the app's only durable
/// local store and is wiped on logout (`deleteAll`), so a draft can't leak
/// into a different account that later signs in on this device. The key is
/// additionally uid-scoped as a second guard.
///
/// Corrupt payloads decode to null (→ "no draft") rather than throwing.
class SecureRideComposeDraftStore implements RideComposeDraftStore {
  SecureRideComposeDraftStore(this._storage);

  final SecureStorage _storage;

  static const _version = 'v1';

  String _key(String uid) => 'ora.ride_compose_draft.$_version.$uid';

  @override
  Future<RideComposeDraft?> loadDraft({required String uid}) async {
    final raw = await _storage.read(key: _key(uid));
    if (raw == null) return null;
    try {
      return RideComposeDraft.tryFromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> writeDraft({
    required String uid,
    required RideComposeDraft draft,
  }) {
    return _storage.write(key: _key(uid), value: jsonEncode(draft.toJson()));
  }

  @override
  Future<void> clearDraft({required String uid}) {
    return _storage.delete(key: _key(uid));
  }
}
