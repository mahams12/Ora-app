import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/storage/secure_storage.dart';

enum RecentActivityKind { ride, intercity, logistics, rental, service }

class RecentActivity {
  const RecentActivity({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageAsset,
    required this.route,
    required this.atMs,
  });

  final RecentActivityKind kind;
  final String id;
  final String title;
  final String subtitle;
  final String imageAsset;
  final String route;
  final int atMs;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'imageAsset': imageAsset,
    'route': route,
    'atMs': atMs,
  };

  factory RecentActivity.fromJson(Map<String, Object?> json) {
    final kindName = json['kind'] as String;
    final kind = RecentActivityKind.values.firstWhere(
      (value) => value.name == kindName,
    );
    return RecentActivity(
      kind: kind,
      id: json['id'] as String,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String,
      imageAsset: json['imageAsset'] as String,
      route: json['route'] as String,
      atMs: json['atMs'] as int,
    );
  }
}

abstract interface class RecentActivityStorage {
  Future<String?> read();

  Future<void> write(String value);
}

const recentActivityStorageKey = 'ora.recent_activity.v1';

class SecureRecentActivityStorage implements RecentActivityStorage {
  const SecureRecentActivityStorage(this._storage);

  final SecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: recentActivityStorageKey);

  @override
  Future<void> write(String value) =>
      _storage.write(key: recentActivityStorageKey, value: value);
}

class InMemoryRecentActivityStorage implements RecentActivityStorage {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

final recentActivityStorageProvider = Provider<RecentActivityStorage>(
  (ref) => SecureRecentActivityStorage(ref.watch(secureStorageProvider)),
);

final recentActivityProvider =
    NotifierProvider<RecentActivityNotifier, List<RecentActivity>>(
      RecentActivityNotifier.new,
    );

class RecentActivityNotifier extends Notifier<List<RecentActivity>> {
  late RecentActivityStorage _storage;
  late Future<void> _loadFuture;
  Future<void> _writeQueue = Future<void>.value();
  var _revision = 0;

  Future<void> get ready => _loadFuture;

  Future<void> get flushed => _writeQueue;

  @override
  List<RecentActivity> build() {
    _storage = ref.watch(recentActivityStorageProvider);
    _loadFuture = _load(_revision);
    return const [];
  }

  Future<void> _load(int initialRevision) async {
    try {
      final raw = await _storage.read();
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;

      final loaded = <RecentActivity>[];
      final loadedIdentities = <String>{};
      for (final item in decoded) {
        if (item is Map) {
          try {
            final activity = RecentActivity.fromJson(
              Map<String, Object?>.from(item),
            );
            if (loadedIdentities.add(_identity(activity))) loaded.add(activity);
          } catch (_) {
            // Ignore malformed entries while preserving other recent items.
          }
        }
      }
      loaded.sort((a, b) => b.atMs.compareTo(a.atMs));

      if (_revision == initialRevision) {
        state = List.unmodifiable(loaded.take(3));
        return;
      }

      final currentIdentities = state.map(_identity).toSet();
      final merged = [
        ...state,
        ...loaded.where(
          (activity) => currentIdentities.add(_identity(activity)),
        ),
      ].take(3);
      state = List.unmodifiable(merged);
      _persist(state);
    } catch (_) {
      if (_revision == initialRevision) state = const [];
    }
  }

  void record(RecentActivity activity) {
    _revision++;
    state = List.unmodifiable(
      [
        activity,
        ...state.where((item) => _identity(item) != _identity(activity)),
      ].take(3),
    );
    _persist(state);
  }

  void _persist(List<RecentActivity> activities) {
    final value = jsonEncode(
      activities.map((activity) => activity.toJson()).toList(),
    );
    _writeQueue = _writeQueue.then<void>((_) async {
      try {
        await _storage.write(value);
      } catch (_) {
        // Recent activity is best-effort and must never block navigation.
      }
    });
  }

  String _identity(RecentActivity activity) =>
      '${activity.kind.name}:${activity.id}';
}
