abstract interface class LocalStorage {
  Future<void> writeString({required String key, required String value});

  Future<String?> readString({required String key});

  Future<void> delete({required String key});
}

/// Phase 1 placeholder — hive_ce integration in Phase 3+.
class InMemoryLocalStorage implements LocalStorage {
  InMemoryLocalStorage();

  final Map<String, String> _store = {};

  @override
  Future<void> writeString({required String key, required String value}) async {
    _store[key] = value;
  }

  @override
  Future<String?> readString({required String key}) async => _store[key];

  @override
  Future<void> delete({required String key}) async {
    _store.remove(key);
  }
}
