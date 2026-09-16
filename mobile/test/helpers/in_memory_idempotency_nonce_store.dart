import 'package:ora/core/storage/idempotency_nonce_store.dart';

/// Test double — no secure storage.
class InMemoryIdempotencyNonceStore implements IdempotencyNonceStore {
  final Map<String, String> keys = {};

  @override
  Future<String> getOrCreate(String operationKey) async {
    return keys.putIfAbsent(operationKey, () => 'nonce:$operationKey');
  }

  @override
  Future<void> clear(String operationKey) async {
    keys.remove(operationKey);
  }
}
