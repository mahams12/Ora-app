import '../models/ride_compose_draft.dart';

/// Local persistence port for the in-progress ride compose draft.
///
/// Reads/writes are scoped to an authenticated [uid] — one account's draft
/// must never surface under another account on the same device.
abstract interface class RideComposeDraftStore {
  /// Null when no draft exists, the payload is corrupt, or it is stale.
  Future<RideComposeDraft?> loadDraft({required String uid});

  Future<void> writeDraft({required String uid, required RideComposeDraft draft});

  Future<void> clearDraft({required String uid});
}
