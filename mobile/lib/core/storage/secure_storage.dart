import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SecureStorage {
  Future<void> write({required String key, required String value});

  Future<String?> read({required String key});

  Future<void> delete({required String key});

  /// Delete every entry in the secure store.  Called on logout.
  Future<void> deleteAll();
}

/// Production implementation backed by the OS Keychain/Keystore via
/// flutter_secure_storage.  Access tokens, refresh tokens, and
/// OTP session IDs are stored here — never in SharedPreferences or logs.
class FlutterSecureStorageImpl implements SecureStorage {
  FlutterSecureStorageImpl({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              // Android: use the default cipher-backed storage (v11+).
              aOptions: AndroidOptions(),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

/// In-memory placeholder used only in unit tests (never in production or
/// integration builds) so no OS keychain is required.
class InMemorySecureStorage implements SecureStorage {
  InMemorySecureStorage();

  final Map<String, String> _store = {};

  @override
  Future<void> write({required String key, required String value}) async {
    _store[key] = value;
  }

  @override
  Future<String?> read({required String key}) async => _store[key];

  @override
  Future<void> delete({required String key}) async {
    _store.remove(key);
  }

  @override
  Future<void> deleteAll() async => _store.clear();
}
