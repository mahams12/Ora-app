import '../storage/secure_storage.dart';
import '../storage/storage_keys.dart';

/// Durable client-side Idempotency-Key store for ride mutations.
///
/// Same logical operation reuses the same nonce until [clear] after a
/// terminal success. Concurrent callers for the same [operationKey] share
/// one in-flight future so duplicate UI taps cannot mint different keys.
abstract interface class IdempotencyNonceStore {
  /// Returns an existing nonce for [operationKey], or creates and persists one.
  Future<String> getOrCreate(String operationKey);

  /// Removes a completed mutation nonce.
  Future<void> clear(String operationKey);
}

class SecureIdempotencyNonceStore implements IdempotencyNonceStore {
  SecureIdempotencyNonceStore({
    required SecureStorage secureStorage,
    required String Function() createNonce,
  })  : _secureStorage = secureStorage,
        _createNonce = createNonce;

  final SecureStorage _secureStorage;
  final String Function() _createNonce;
  final Map<String, Future<String>> _inflight = {};

  String _storageKey(String operationKey) =>
      '${StorageKeys.idempotencyKeyPrefix}$operationKey';

  void _dropInflight(String operationKey, Future<String> owned) {
    if (identical(_inflight[operationKey], owned)) {
      // Map.remove returns the Future value; discard without awaiting.
      // ignore: unawaited_futures
      _inflight.remove(operationKey);
    }
  }

  @override
  Future<String> getOrCreate(String operationKey) async {
    final existing = _inflight[operationKey];
    if (existing != null) return existing;

    final future = _loadOrCreate(operationKey);
    _inflight[operationKey] = future;
    try {
      return await future;
    } finally {
      _dropInflight(operationKey, future);
    }
  }

  Future<String> _loadOrCreate(String operationKey) async {
    final key = _storageKey(operationKey);
    final stored = await _secureStorage.read(key: key);
    if (stored != null && stored.isNotEmpty) {
      return stored;
    }
    final created = _createNonce();
    await _secureStorage.write(key: key, value: created);
    return created;
  }

  @override
  Future<void> clear(String operationKey) async {
    // ignore: unawaited_futures
    _inflight.remove(operationKey);
    await _secureStorage.delete(key: _storageKey(operationKey));
  }
}
