import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/core/storage/secure_storage.dart';
import 'package:ora/features/auth/domain/entities/user_profile.dart';
import 'package:ora/features/auth/presentation/view_models/session_user_profile.dart';
import 'package:ora/features/saved_places/data/secure_passenger_places_store.dart';
import 'package:ora/features/saved_places/domain/entities/passenger_places.dart';
import 'package:ora/features/saved_places/domain/passenger_places_policy.dart';
import 'package:ora/features/saved_places/domain/ports/passenger_places_store.dart';
import 'package:ora/features/saved_places/presentation/view_models/passenger_places_view_model.dart';

SavedPlace _place({
  String id = 'p1',
  String name = 'Gym',
  double lat = 31.5,
  double lng = 74.3,
  String? addressLabel,
  String? placeId,
  int updatedAtMs = 100,
}) =>
    SavedPlace(
      id: id,
      name: name,
      lat: lat,
      lng: lng,
      addressLabel: addressLabel,
      placeId: placeId,
      updatedAtMs: updatedAtMs,
    );

RecentDestination _recent({
  double lat = 31.5,
  double lng = 74.3,
  String? label,
  String? placeId,
  int lastUsedMs = 100,
}) =>
    RecentDestination(
      lat: lat,
      lng: lng,
      label: label,
      placeId: placeId,
      lastUsedMs: lastUsedMs,
    );

void main() {
  group('normalizePlaceName', () {
    test('trims, collapses whitespace, caps length', () {
      expect(normalizePlaceName('  Home  '), 'Home');
      expect(normalizePlaceName('My   Gym\tPlace'), 'My Gym Place');
      expect(normalizePlaceName('x' * 60)!.length, kMaxPlaceNameLength);
      expect(normalizePlaceName('   '), isNull);
      expect(normalizePlaceName(''), isNull);
    });
  });

  group('upsertSavedPlace', () {
    test('same id replaces (rename/re-pin), Home/Work sort first', () {
      var list = [_place(id: 'a', name: 'Gym', updatedAtMs: 1)];
      list = upsertSavedPlace(list, _place(id: kHomePlaceId, name: 'Home'));
      list = upsertSavedPlace(
        list,
        _place(id: 'a', name: 'Gym 24', updatedAtMs: 9),
      );
      expect(list.map((p) => p.id), [kHomePlaceId, 'a']);
      expect(list[1].name, 'Gym 24');
    });

    test('caps at kMaxSavedPlaces', () {
      var list = <SavedPlace>[];
      for (var i = 0; i < kMaxSavedPlaces + 5; i++) {
        list = upsertSavedPlace(
          list,
          _place(id: 'c$i', name: 'P$i', updatedAtMs: i),
        );
      }
      expect(list.length, kMaxSavedPlaces);
    });
  });

  group('pushRecentDestination', () {
    test('dedupes same placeId and nearby coords, newest first, capped', () {
      var recents = <RecentDestination>[];
      recents = pushRecentDestination(
        recents,
        _recent(label: 'Gulberg', placeId: 'pg', lastUsedMs: 1),
      );
      // Same placeId, different coords → deduped.
      recents = pushRecentDestination(
        recents,
        _recent(lat: 32.0, lng: 75.0, placeId: 'pg', lastUsedMs: 2),
      );
      expect(recents.length, 1);
      expect(recents.first.lastUsedMs, 2);

      // ~10m away (no placeId) → same place, deduped.
      recents = pushRecentDestination(
        recents,
        _recent(lat: 32.00009, lng: 75.0, lastUsedMs: 3),
      );
      expect(recents.length, 1);

      // Far away → new entry.
      recents = pushRecentDestination(
        recents,
        _recent(lat: 33.0, lng: 73.0, lastUsedMs: 4),
      );
      expect(recents.length, 2);
      expect(recents.first.lastUsedMs, 4);

      // Cap respected.
      for (var i = 0; i < 20; i++) {
        recents = pushRecentDestination(
          recents,
          _recent(lat: 40.0 + i, lng: 70.0 + i, lastUsedMs: 10 + i),
        );
      }
      expect(recents.length, kMaxRecentDestinations);
    });
  });

  group('SecurePassengerPlacesStore', () {
    test('roundtrip + uid isolation + corrupt-payload tolerance', () async {
      final storage = InMemorySecureStorage();
      final store = SecurePassengerPlacesStore(storage);

      await store.writeSavedPlaces(
        uid: 'uid-a',
        places: [_place(name: 'Home', addressLabel: 'Gulberg III')],
      );
      await store.writeRecentDestinations(
        uid: 'uid-a',
        recents: [_recent(label: 'DHA')],
      );

      final places =
          await store.loadSavedPlaces(uid: 'uid-a');
      expect(places.single.name, 'Home');
      expect(places.single.addressLabel, 'Gulberg III');
      expect(
        (await store.loadRecentDestinations(uid: 'uid-a')).single.label,
        'DHA',
      );

      // uid-b sees nothing — cross-account isolation.
      expect(await store.loadSavedPlaces(uid: 'uid-b'), isEmpty);
      expect(await store.loadRecentDestinations(uid: 'uid-b'), isEmpty);

      // Corrupt payloads decode to empty, never throw.
      await storage.write(key: 'ora.saved_places.v1.uid-c', value: '{bad');
      await storage.write(
        key: 'ora.recent_destinations.v1.uid-c',
        value: '[{"lat":"oops"}]',
      );
      expect(await store.loadSavedPlaces(uid: 'uid-c'), isEmpty);
      expect(await store.loadRecentDestinations(uid: 'uid-c'), isEmpty);
    });

    test('skips malformed entries and invalid coordinates', () async {
      final storage = InMemorySecureStorage();
      await storage.write(
        key: 'ora.saved_places.v1.uid-a',
        value:
            '[{"id":"ok","name":"A","lat":31,"lng":74,"updatedAtMs":1},'
            '{"id":"bad","name":"B","lat":999,"lng":74},'
            '{"no_id":true},42]',
      );
      final store = SecurePassengerPlacesStore(storage);
      final places = await store.loadSavedPlaces(uid: 'uid-a');
      expect(places.single.id, 'ok');
    });
  });

  group('PassengerPlacesViewModel', () {
    ProviderContainer containerFor(String uid, PassengerPlacesStore store) {
      return ProviderContainer(
        overrides: [
          passengerPlacesStoreProvider.overrideWithValue(store),
          sessionUserProfileProvider.overrideWith(
            () => _FixedProfile(UserProfile(
              uid: uid,
              phoneNumber: '+9200000000',
              role: 'passenger',
              profileComplete: true,
            )),
          ),
        ],
      );
    }

    test('savePlace persists, rename/remove update state + store', () async {
      final storage = InMemorySecureStorage();
      final store = SecurePassengerPlacesStore(storage);
      final c = containerFor('uid-a', store);
      addTearDown(c.dispose);
      // Trigger build + wait for initial load.
      c.read(passengerPlacesProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final vm = c.read(passengerPlacesProvider.notifier);

      expect(await vm.savePlace(name: 'Home', lat: 31.5, lng: 74.3), isNull);
      expect(c.read(passengerPlacesProvider).places.single.name, 'Home');
      final saved = await store.loadSavedPlaces(uid: 'uid-a');
      expect(saved.single.name, 'Home');

      final id = c.read(passengerPlacesProvider).places.single.id;
      expect(await vm.renamePlace(id: id, name: 'Ami'), isNull);
      expect(c.read(passengerPlacesProvider).places.single.name, 'Ami');
      expect(
        (await store.loadSavedPlaces(uid: 'uid-a')).single.name,
        'Ami',
      );

      expect(await vm.removePlace(id), isNull);
      expect(c.read(passengerPlacesProvider).places, isEmpty);
      expect(await store.loadSavedPlaces(uid: 'uid-a'), isEmpty);
    });

    test('invalid input rejected — no fake data persisted', () async {
      final c = containerFor('uid-a', SecurePassengerPlacesStore(
        InMemorySecureStorage(),
      ));
      addTearDown(c.dispose);
      c.read(passengerPlacesProvider);
      await Future<void>.delayed(Duration.zero);
      final vm = c.read(passengerPlacesProvider.notifier);

      expect(
        await vm.savePlace(name: '  ', lat: 31, lng: 74),
        isNotNull,
      );
      expect(
        await vm.savePlace(name: 'Nowhere', lat: 999, lng: 74),
        isNotNull,
      );
      expect(c.read(passengerPlacesProvider).places, isEmpty);
    });

    test('recordRecentDestination dedupes and persists', () async {
      final store = SecurePassengerPlacesStore(InMemorySecureStorage());
      final c = containerFor('uid-a', store);
      addTearDown(c.dispose);
      c.read(passengerPlacesProvider);
      await Future<void>.delayed(Duration.zero);
      final vm = c.read(passengerPlacesProvider.notifier);

      await vm.recordRecentDestination(lat: 31.5, lng: 74.3, label: 'Gulberg');
      await vm.recordRecentDestination(lat: 31.5001, lng: 74.3);
      await vm.recordRecentDestination(lat: 33.0, lng: 73.0);
      final recents = c.read(passengerPlacesProvider).recents;
      expect(recents.length, 2);
      expect(recents.first.lat, 33.0);
      // Await the fire-and-forget persist microtask queue.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        (await store.loadRecentDestinations(uid: 'uid-a')).length,
        2,
      );
    });

    test('account scoping — uid-b cannot see uid-a data', () async {
      final storage = InMemorySecureStorage();
      final store = SecurePassengerPlacesStore(storage);
      await store.writeSavedPlaces(
        uid: 'uid-a',
        places: [_place(name: 'Home')],
      );

      final c = containerFor('uid-b', store);
      addTearDown(c.dispose);
      c.read(passengerPlacesProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(passengerPlacesProvider).places, isEmpty);
    });
  });
}

class _FixedProfile extends SessionUserProfileNotifier {
  _FixedProfile(this._profile);

  final UserProfile _profile;

  @override
  UserProfile? build() => _profile;
}
