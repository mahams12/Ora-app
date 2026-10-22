import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/core/errors/failure_mapper.dart';
import 'package:ora/core/storage/secure_storage.dart';
import 'package:ora/features/auth/domain/entities/user_profile.dart';
import 'package:ora/features/auth/presentation/view_models/session_user_profile.dart';
import 'package:ora/features/ride/data/secure_ride_compose_draft_store.dart';
import 'package:ora/features/ride/domain/models/resolved_passenger_location.dart';
import 'package:ora/features/ride/domain/models/ride_compose_draft.dart';
import 'package:ora/features/ride/domain/ports/device_location_port.dart';
import 'package:ora/features/ride/domain/ports/place_search_port.dart';
import 'package:ora/features/ride/domain/ports/pricing_estimate_port.dart';
import 'package:ora/features/ride/domain/ports/ride_compose_draft_store.dart';
import 'package:ora/features/ride/domain/use_cases/ride_use_cases.dart';
import 'package:ora/features/ride/presentation/view_models/ride_request_view_model.dart';

const _uid = 'uid-draft-test';

UserProfile _profile(String uid) => UserProfile(
      uid: uid,
      phoneNumber: '+9200000000',
      role: 'passenger',
      profileComplete: true,
    );

class _FixedProfile extends SessionUserProfileNotifier {
  _FixedProfile(this._profile);
  final UserProfile? _profile;
  @override
  UserProfile? build() => _profile;
}

class _DraftStore implements RideComposeDraftStore {
  _DraftStore({this.stored, this.loadDelay = Duration.zero});
  RideComposeDraft? stored;
  Duration loadDelay;
  int writes = 0, clears = 0, loads = 0;
  RideComposeDraft? lastWritten;

  @override
  Future<RideComposeDraft?> loadDraft({required String uid}) async {
    loads++;
    if (loadDelay > Duration.zero) await Future.delayed(loadDelay);
    return stored;
  }

  @override
  Future<void> writeDraft({
    required String uid,
    required RideComposeDraft draft,
  }) async {
    writes++;
    lastWritten = draft;
    stored = draft;
  }

  @override
  Future<void> clearDraft({required String uid}) async {
    clears++;
    stored = null;
  }
}

class _MockCreate extends Mock implements CreateRideUseCase {}

class _FakeDevice implements DeviceLocationPort {
  @override
  Future<ResolvedPassengerLocation> getCurrentLocation() async =>
      const ResolvedPassengerLocation(
        lat: 31.46,
        lng: 74.26,
        source: PassengerLocationSource.gps,
      );
}

class _FakePlaces implements PlaceSearchPort {
  _FakePlaces({this.resolved});
  ResolvedPassengerLocation? resolved;

  @override
  Future<List<PlaceSuggestion>> autocomplete({
    required String query,
    required String sessionToken,
  }) async =>
      const [];

  @override
  Future<ResolvedPassengerLocation> resolvePlace({
    required String placeId,
    required String sessionToken,
  }) async =>
      resolved!;

  @override
  Future<ResolvedPassengerLocation> reverseGeocode({
    required double lat,
    required double lng,
  }) async =>
      ResolvedPassengerLocation(
        lat: lat,
        lng: lng,
        address: 'Johar Town, Lahore',
        source: PassengerLocationSource.gps,
      );
}

class _FailPricing implements PricingEstimatePort {
  @override
  Future<PricingEstimate> estimate(PricingEstimateRequest request) =>
      throw const PricingClientException(
        PricingFailureKind.pricingUnavailable,
        'down',
      );
}

void main() {
  group('RideComposeDraft model', () {
    RideComposeDraft sample() => RideComposeDraft(
          savedAtMillis: DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
          categoryId: 'breeze',
          serviceType: 'intercity',
          pickup: const RideComposeDraftPoint(
            lat: 31.46,
            lng: 74.26,
            source: PassengerLocationSource.gps,
            confirmed: true,
            address: 'Johar Town, Lahore',
          ),
          destination: const RideComposeDraftPoint(
            lat: 31.55,
            lng: 74.34,
            source: PassengerLocationSource.mapPin,
            confirmed: false,
          ),
          pickupText: 'Johar Town, Lahore',
          destinationText: 'Location selected',
          passengerOfferDraftText: '430',
        );

    test('JSON round-trip preserves all fields', () {
      final d = sample();
      final decoded = RideComposeDraft.tryFromJson(d.toJson())!;
      expect(decoded.categoryId, 'breeze');
      expect(decoded.serviceType, 'intercity');
      expect(decoded.pickup!.lat, 31.46);
      expect(decoded.pickup!.confirmed, isTrue);
      expect(decoded.pickup!.source, PassengerLocationSource.gps);
      expect(decoded.destination!.confirmed, isFalse);
      expect(decoded.passengerOfferDraftText, '430');
    });

    test('corrupt / partial payloads decode to null', () {
      expect(RideComposeDraft.tryFromJson('junk'), isNull);
      expect(RideComposeDraft.tryFromJson({}), isNull);
      expect(
        RideComposeDraft.tryFromJson({'savedAt': 'x', 'categoryId': 'easy'}),
        isNull,
      );
      // Invalid coords drop the point but keep the draft decodable — the
      // VM's hasValidCoordinates guard rejects them at restore time.
      final bad = sample().toJson()
        ..['pickup'] = {'lat': 999, 'lng': 0, 'source': 'gps'};
      expect(
        RideComposeDraftPoint.tryFromJson(bad['pickup']),
        isNull,
      );
      expect(
        RideComposeDraftPoint.tryFromJson(
          {'lat': 1, 'lng': 2, 'source': 'bogus'},
        ),
        isNull,
      );
    });

    test('staleness boundary', () {
      final now = DateTime.utc(2026, 1, 2);
      final fresh = RideComposeDraft(
        savedAtMillis:
            now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
        categoryId: 'easy',
        serviceType: 'ride',
      );
      expect(fresh.isStaleAt(now), isFalse);
      final old = RideComposeDraft(
        savedAtMillis:
            now.subtract(const Duration(hours: 25)).millisecondsSinceEpoch,
        categoryId: 'easy',
        serviceType: 'ride',
      );
      expect(old.isStaleAt(now), isTrue);
    });
  });

  group('SecureRideComposeDraftStore', () {
    test('round-trip + uid isolation + corrupt tolerance + clear', () async {
      final storage = InMemorySecureStorage();
      final store = SecureRideComposeDraftStore(storage);
      final draft = RideComposeDraft(
        savedAtMillis: DateTime.now().toUtc().millisecondsSinceEpoch,
        categoryId: 'easy',
        serviceType: 'ride',
        pickupText: 'X',
      );
      await store.writeDraft(uid: 'a', draft: draft);
      expect((await store.loadDraft(uid: 'a'))!.pickupText, 'X');
      expect(await store.loadDraft(uid: 'b'), isNull);
      await storage.write(key: 'ora.ride_compose_draft.v1.c', value: '{bad');
      expect(await store.loadDraft(uid: 'c'), isNull);
      await store.clearDraft(uid: 'a');
      expect(await store.loadDraft(uid: 'a'), isNull);
    });
  });

  group('RideRequestViewModel draft integration', () {
    ProviderContainer container({_DraftStore? store, String? uid}) {
      return ProviderContainer(
        overrides: [
          rideRequestCapabilitiesProvider
              .overrideWithValue(const RideRequestCapabilities()),
          createRideUseCaseProvider.overrideWithValue(_MockCreate()),
          failureMapperProvider.overrideWithValue(const FailureMapper()),
          deviceLocationPortProvider.overrideWithValue(_FakeDevice()),
          placeSearchPortProvider.overrideWithValue(_FakePlaces()),
          pricingEstimatePortProvider.overrideWithValue(_FailPricing()),
          rideComposeDraftStoreProvider
              .overrideWithValue(store ?? _DraftStore()),
          if (uid != null)
            sessionUserProfileProvider.overrideWith(
              () => _FixedProfile(_profile(uid)),
            ),
        ],
      );
    }

    RideComposeDraft freshDraft() => RideComposeDraft(
          savedAtMillis: DateTime.now().toUtc().millisecondsSinceEpoch,
          categoryId: 'breeze',
          serviceType: 'intercity',
          pickup: const RideComposeDraftPoint(
            lat: 31.46,
            lng: 74.26,
            source: PassengerLocationSource.gps,
            confirmed: true,
            address: 'Johar Town, Lahore',
          ),
          destination: const RideComposeDraftPoint(
            lat: 31.55,
            lng: 74.34,
            source: PassengerLocationSource.mapPin,
            confirmed: false,
          ),
          pickupText: 'Johar Town, Lahore',
          passengerOfferDraftText: '430',
        );

    Future<void> settle() async {
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await Future<void>.delayed(Duration.zero);
    }

    test('restores endpoints, texts, service type, and offer draft', () async {
      final store = _DraftStore(stored: freshDraft());
      final c = container(store: store, uid: _uid);
      addTearDown(c.dispose);
      final sub = c.listen(rideRequestViewModelProvider, (_, __) {});
      addTearDown(sub.close);
      await settle();

      final s = c.read(rideRequestViewModelProvider);
      expect(s.confirmedPickup!.lat, 31.46);
      expect(s.confirmedPickup!.source, PassengerLocationSource.gps);
      expect(s.proposedDestination!.source, PassengerLocationSource.mapPin);
      expect(s.destinationNameUnresolved, isTrue); // mapPin had no address
      expect(s.serviceType, 'intercity');
      expect(s.categoryId, 'breeze');
      expect(s.pickupText, 'Johar Town, Lahore');
      expect(s.passengerOfferDraftText, '430');
    });

    test('stale draft is discarded and cleared', () async {
      final stale = RideComposeDraft(
        savedAtMillis: DateTime.now()
            .toUtc()
            .subtract(const Duration(hours: 30))
            .millisecondsSinceEpoch,
        categoryId: 'breeze',
        serviceType: 'intercity',
        pickup: const RideComposeDraftPoint(
          lat: 31.46,
          lng: 74.26,
          source: PassengerLocationSource.gps,
          confirmed: true,
        ),
      );
      final store = _DraftStore(stored: stale);
      final c = container(store: store, uid: _uid);
      addTearDown(c.dispose);
      final sub = c.listen(rideRequestViewModelProvider, (_, __) {});
      addTearDown(sub.close);
      await settle();

      expect(store.clears, 1);
      final s = c.read(rideRequestViewModelProvider);
      expect(s.confirmedPickup, isNull);
      expect(s.serviceType, 'ride');
    });

    test(
      'non-pristine compose wins over the draft — user input beats restore',
      () async {
        final store = _DraftStore(
          stored: freshDraft(),
          loadDelay: const Duration(milliseconds: 50),
        );
        final c = container(store: store, uid: _uid);
        addTearDown(c.dispose);
        final sub = c.listen(rideRequestViewModelProvider, (_, __) {});
        addTearDown(sub.close);
        // Passenger types before the load lands.
        c.read(rideRequestViewModelProvider.notifier)
            .setPickupText('typing');
        await Future<void>.delayed(const Duration(milliseconds: 120));

        final s = c.read(rideRequestViewModelProvider);
        expect(s.pickupText, 'typing');
        expect(s.confirmedPickup, isNull);
        expect(s.serviceType, 'ride');
      },
    );

    test('mutations persist a draft (debounced) with the right shape',
        () async {
      final store = _DraftStore();
      final places = _FakePlaces(
        resolved: const ResolvedPassengerLocation(
          lat: 31.52,
          lng: 74.35,
          address: 'Lahore Fort, Lahore',
          placeId: 'p1',
          source: PassengerLocationSource.place,
        ),
      );
      final c = ProviderContainer(
        overrides: [
          rideRequestCapabilitiesProvider
              .overrideWithValue(const RideRequestCapabilities()),
          createRideUseCaseProvider.overrideWithValue(_MockCreate()),
          failureMapperProvider.overrideWithValue(const FailureMapper()),
          deviceLocationPortProvider.overrideWithValue(_FakeDevice()),
          placeSearchPortProvider.overrideWithValue(places),
          pricingEstimatePortProvider.overrideWithValue(_FailPricing()),
          rideComposeDraftStoreProvider.overrideWithValue(store),
          sessionUserProfileProvider.overrideWith(
            () => _FixedProfile(_profile(_uid)),
          ),
        ],
      );
      addTearDown(c.dispose);
      final sub = c.listen(rideRequestViewModelProvider, (_, __) {});
      addTearDown(sub.close);
      await settle();
      final vm = c.read(rideRequestViewModelProvider.notifier);

      await vm.useCurrentLocationForPickup();
      vm.confirmPickup();
      await Future<void>.delayed(const Duration(milliseconds: 900));

      expect(store.writes, greaterThanOrEqualTo(1));
      final d = store.lastWritten!;
      expect(d.pickup!.confirmed, isTrue);
      expect(d.pickup!.lat, 31.46);
      expect(d.pickup!.source, PassengerLocationSource.gps);
      expect(d.serviceType, 'ride');
    });

    test('no uid → no store interaction at all', () async {
      final store = _DraftStore(stored: freshDraft());
      final c = container(store: store); // no uid override
      addTearDown(c.dispose);
      final sub = c.listen(rideRequestViewModelProvider, (_, __) {});
      addTearDown(sub.close);
      await settle();
      c.read(rideRequestViewModelProvider.notifier).setPickupText('x');
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(store.loads, 0);
      expect(store.writes, 0);
    });
  });
}
