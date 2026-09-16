import 'package:flutter_test/flutter_test.dart';
import 'package:ora/core/storage/idempotency_nonce_store.dart';
import 'package:ora/core/storage/secure_storage.dart';

void main() {
  group('SecureIdempotencyNonceStore', () {
    late InMemorySecureStorage storage;
    late SecureIdempotencyNonceStore store;
    var counter = 0;

    setUp(() {
      storage = InMemorySecureStorage();
      counter = 0;
      store = SecureIdempotencyNonceStore(
        secureStorage: storage,
        createNonce: () => 'nonce-${++counter}',
      );
    });

    test('reuses same nonce for same operationKey', () async {
      final a = await store.getOrCreate('ride_create_client1');
      final b = await store.getOrCreate('ride_create_client1');
      expect(a, b);
      expect(a, 'nonce-1');
    });

    test('different operations get different nonces', () async {
      final a = await store.getOrCreate('op-a');
      final b = await store.getOrCreate('op-b');
      expect(a, isNot(b));
    });

    test('clear allows a new nonce', () async {
      final a = await store.getOrCreate('op');
      await store.clear('op');
      final b = await store.getOrCreate('op');
      expect(a, isNot(b));
    });

    test('concurrent getOrCreate shares one nonce', () async {
      final results = await Future.wait([
        store.getOrCreate('same'),
        store.getOrCreate('same'),
        store.getOrCreate('same'),
      ]);
      expect(results.toSet(), hasLength(1));
    });

    test('survives store recreation (app restart simulation)', () async {
      final first = await store.getOrCreate('persist');
      final restarted = SecureIdempotencyNonceStore(
        secureStorage: storage,
        createNonce: () => 'should-not-use',
      );
      final second = await restarted.getOrCreate('persist');
      expect(second, first);
    });
  });
}
