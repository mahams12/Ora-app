import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/di/providers.dart';
import '../../../auth/presentation/view_models/session_user_profile.dart';
import '../../domain/entities/passenger_places.dart';
import '../../domain/passenger_places_policy.dart';
import '../../domain/ports/passenger_places_store.dart';

class PassengerPlacesUiState {
  const PassengerPlacesUiState({
    this.places = const [],
    this.recents = const [],
    this.loading = false,
    this.errorMessage,
  });

  final List<SavedPlace> places;
  final List<RecentDestination> recents;

  /// Initial load only — mutations keep prior content visible.
  final bool loading;

  /// Non-blocking storage error surfaced to the UI; lists stay usable.
  final String? errorMessage;

  PassengerPlacesUiState copyWith({
    List<SavedPlace>? places,
    List<RecentDestination>? recents,
    bool? loading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PassengerPlacesUiState(
      places: places ?? this.places,
      recents: recents ?? this.recents,
      loading: loading ?? this.loading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Saved places + recent destinations for the signed-in passenger.
///
/// Watches [sessionUserProfileProvider] — a uid change (logout/login)
/// rebuilds the notifier and re-loads from that account's scoped keys, so
/// lists can never leak across accounts even if the store weren't cleared.
class PassengerPlacesViewModel extends Notifier<PassengerPlacesUiState> {
  late final PassengerPlacesStore _store;

  /// Current account uid — read (not watched) inside methods; build() watches
  /// the profile so an account change rebuilds and re-loads cleanly.
  String? get _uid => ref.read(sessionUserProfileProvider)?.uid;

  @override
  PassengerPlacesUiState build() {
    _store = ref.read(passengerPlacesStoreProvider);
    final uid = ref.watch(sessionUserProfileProvider)?.uid;
    if (uid != null) {
      Future.microtask(() => _load(uid));
    }
    return PassengerPlacesUiState(loading: uid != null);
  }

  Future<void> _load(String uid) async {
    try {
      final places = await _store.loadSavedPlaces(uid: uid);
      final recents = await _store.loadRecentDestinations(uid: uid);
      if (_uid != uid) return; // account changed mid-load — discard
      state = state.copyWith(
        places: places,
        recents: recents,
        loading: false,
        clearError: true,
      );
    } catch (_) {
      if (_uid != uid) return;
      state = state.copyWith(
        loading: false,
        errorMessage: 'Saved places couldn\'t be loaded.',
      );
    }
  }

  /// Reload after a transient failure — cheap, no account switch.
  Future<void> retryLoad() async {
    final uid = _uid;
    if (uid == null) return;
    state = state.copyWith(loading: true, clearError: true);
    await _load(uid);
  }

  /// Save (or update, when [id] is provided — e.g. 'home'/'work' slots).
  /// Returns an error message on invalid input/storage failure, else null.
  Future<String?> savePlace({
    required String name,
    required double lat,
    required double lng,
    String? addressLabel,
    String? placeId,
    String? id,
  }) async {
    final uid = _uid;
    if (uid == null) return 'Sign in to save places.';
    final normalized = normalizePlaceName(name);
    if (normalized == null) return 'Give this place a name.';
    final place = SavedPlace(
      id: id ?? const Uuid().v4(),
      name: normalized,
      lat: lat,
      lng: lng,
      addressLabel: addressLabel,
      placeId: placeId,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (!place.hasValidCoordinates) {
      return 'That location isn\'t valid — pick it again.';
    }
    final next = upsertSavedPlace(state.places, place);
    state = state.copyWith(places: next, clearError: true);
    return _persist(() => _store.writeSavedPlaces(uid: uid, places: next));
  }

  Future<String?> renamePlace({required String id, required String name}) async {
    final uid = _uid;
    if (uid == null) return 'Sign in to save places.';
    final normalized = normalizePlaceName(name);
    if (normalized == null) return 'Give this place a name.';
    final index = state.places.indexWhere((p) => p.id == id);
    if (index < 0) return null; // already gone — no-op
    final existing = state.places[index];
    final updated = SavedPlace(
      id: existing.id,
      name: normalized,
      lat: existing.lat,
      lng: existing.lng,
      addressLabel: existing.addressLabel,
      placeId: existing.placeId,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    final next = upsertSavedPlace(state.places, updated);
    state = state.copyWith(places: next, clearError: true);
    return _persist(() => _store.writeSavedPlaces(uid: uid, places: next));
  }

  Future<String?> removePlace(String id) async {
    final uid = _uid;
    if (uid == null) return 'Sign in to save places.';
    final next = state.places.where((p) => p.id != id).toList();
    if (next.length == state.places.length) return null;
    state = state.copyWith(places: next, clearError: true);
    return _persist(() => _store.writeSavedPlaces(uid: uid, places: next));
  }

  /// Record a destination the passenger explicitly confirmed.
  /// Fire-and-forget from the ride flow — never blocks confirmation.
  Future<void> recordRecentDestination({
    required double lat,
    required double lng,
    String? label,
    String? placeId,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    final rec = RecentDestination(
      lat: lat,
      lng: lng,
      label: label,
      placeId: placeId,
      lastUsedMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (!rec.hasValidCoordinates) return;
    final next = pushRecentDestination(state.recents, rec);
    state = state.copyWith(recents: next);
    unawaited(
      _persist(() => _store.writeRecentDestinations(uid: uid, recents: next)),
    );
  }

  /// Persist a mutation; keep optimistic state, surface error message.
  Future<String?> _persist(Future<void> Function() write) async {
    try {
      await write();
      return null;
    } catch (_) {
      state = state.copyWith(
        errorMessage: 'Couldn\'t save — check your connection and retry.',
      );
      return state.errorMessage;
    }
  }
}

/// SAVED-PLACES/RECENTS — session-scoped (not autoDispose) so recents
/// recorded mid-flow survive navigation; reloads on account change.
final passengerPlacesProvider =
    NotifierProvider<PassengerPlacesViewModel, PassengerPlacesUiState>(
  PassengerPlacesViewModel.new,
);
