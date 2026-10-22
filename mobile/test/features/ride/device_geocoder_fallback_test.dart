import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:mocktail/mocktail.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/core/errors/failure_mapper.dart';
import 'package:ora/features/ride/data/location/fallback_place_search.dart';
import 'package:ora/features/ride/data/location/geocoding_device_geocoder.dart';
import 'package:ora/features/ride/domain/models/resolved_passenger_location.dart';
import 'package:ora/features/ride/domain/ports/device_geocoder_port.dart';
import 'package:ora/features/ride/domain/ports/device_location_port.dart';
import 'package:ora/features/ride/domain/ports/place_search_port.dart';
import 'package:ora/features/ride/domain/ports/pricing_estimate_port.dart';
import 'package:ora/features/ride/domain/use_cases/ride_use_cases.dart';
import 'package:ora/features/ride/presentation/view_models/ride_request_view_model.dart';

void main() {
  group('devicePlacemarkLabel', () {
    test('street + locality compose and dedupe', () {
      expect(
        devicePlacemarkLabel(
          const geo.Placemark(
            name: '12 Main Boulevard',
            thoroughfare: 'Main Boulevard',
            subLocality: 'Gulberg III',
            locality: 'Lahore',
          ),
        ),
        '12 Main Boulevard, Main Boulevard, Gulberg III',
      );
      // Cap at 3 parts.
      expect(
        devicePlacemarkLabel(
          const geo.Placemark(
            name: 'n',
            thoroughfare: 't',
            subLocality: 's',
            locality: 'l',
            administrativeArea: 'a',
          ),
        ),
        'n, t, s',
      );
    });

    test('locality-only placemark still yields a name', () {
      expect(
        devicePlacemarkLabel(const geo.Placemark(locality: 'Islamabad')),
        'Islamabad',
      );
    });

    test('empty placemark returns null — never invents a label', () {
      expect(devicePlacemarkLabel(const geo.Placemark()), isNull);
      expect(
        devicePlacemarkLabel(const geo.Placemark(name: '  ', locality: '')),
        isNull,
      );
    });
  });

  group('FallbackPlaceSearch', () {
    const namedResult = ResolvedPassengerLocation(
      lat: 31.5,
      lng: 74.3,
      address: 'Gulberg III, Lahore',
      source: PassengerLocationSource.gps,
    );

    PlaceSearchPort primary({Object? error, ResolvedPassengerLocation? ok}) {
      return _FakePrimary(error: error, ok: ok);
    }

    DeviceGeocoderPort device({String? label}) => _FakeDevice(label);

    test('primary success wins — device geocoder not consulted', () async {
      final d = _FakeDevice('Device Town');
      final s = FallbackPlaceSearch(
        primary: primary(ok: namedResult),
        deviceGeocoder: d,
      );
      final r = await s.reverseGeocode(lat: 31.5, lng: 74.3);
      expect(r.address, 'Gulberg III, Lahore');
      expect(d.calls, 0);
    });

    test('primary failure falls back to device label, coords preserved',
        () async {
      final s = FallbackPlaceSearch(
        primary: primary(
          error: const PlaceSearchException(PlaceSearchFailureKind.network),
        ),
        deviceGeocoder: device(label: 'Johar Town, Lahore'),
      );
      final r = await s.reverseGeocode(lat: 31.5, lng: 74.3);
      expect(r.address, 'Johar Town, Lahore');
      expect(r.lat, 31.5);
      expect(r.lng, 74.3);
      expect(r.source, PassengerLocationSource.gps);
    });

    test('primary unlabeled success falls back to device label', () async {
      final s = FallbackPlaceSearch(
        primary: primary(
          ok: const ResolvedPassengerLocation(
            lat: 31.5,
            lng: 74.3,
            source: PassengerLocationSource.gps,
          ),
        ),
        deviceGeocoder: device(label: 'DHA Phase 5'),
      );
      final r = await s.reverseGeocode(lat: 31.5, lng: 74.3);
      expect(r.address, 'DHA Phase 5');
    });

    test('total failure rethrows the primary error honestly', () async {
      final s = FallbackPlaceSearch(
        primary: primary(
          error: const PlaceSearchException(
            PlaceSearchFailureKind.network,
            'off',
          ),
        ),
        deviceGeocoder: device(label: null),
      );
      await expectLater(
        s.reverseGeocode(lat: 31.5, lng: 74.3),
        throwsA(
          isA<PlaceSearchException>().having(
            (e) => e.kind,
            'kind',
            PlaceSearchFailureKind.network,
          ),
        ),
      );
    });
  });

  group('VM accuracy + naming', () {
    test('GPS accuracy propagates to the proposed pickup unchanged', () async {
      final c = ProviderContainer(
        overrides: [
          rideRequestCapabilitiesProvider
              .overrideWithValue(const RideRequestCapabilities()),
          createRideUseCaseProvider.overrideWithValue(_MockCreate()),
          failureMapperProvider.overrideWithValue(const FailureMapper()),
          deviceLocationPortProvider.overrideWithValue(
            _AccurateDeviceLocation(accuracyMeters: 12.4),
          ),
          placeSearchPortProvider.overrideWithValue(
            _FailingPlaces(),
          ),
          pricingEstimatePortProvider.overrideWithValue(_FailingPricing()),
        ],
      );
      addTearDown(c.dispose);
      final sub = c.listen(rideRequestViewModelProvider, (_, __) {});
      addTearDown(sub.close);
      final vm = c.read(rideRequestViewModelProvider.notifier);

      await vm.useCurrentLocationForPickup();

      final proposed =
          c.read(rideRequestViewModelProvider).proposedPickup!;
      // Lookup failed but coords + accuracy are preserved, name honest.
      expect(proposed.lat, 31.46);
      expect(proposed.lng, 74.26);
      expect(proposed.horizontalAccuracyMeters, 12.4);
      expect(proposed.address, isNull);
      expect(
        c.read(rideRequestViewModelProvider).pickupNameUnresolved,
        isTrue,
      );
    });

    test('named lookup keeps the same coords — pin never moves', () async {
      final c = ProviderContainer(
        overrides: [
          rideRequestCapabilitiesProvider
              .overrideWithValue(const RideRequestCapabilities()),
          createRideUseCaseProvider.overrideWithValue(_MockCreate()),
          failureMapperProvider.overrideWithValue(const FailureMapper()),
          deviceLocationPortProvider.overrideWithValue(
            _AccurateDeviceLocation(accuracyMeters: 8.0),
          ),
          placeSearchPortProvider.overrideWithValue(
            _NamedPlaces('Bahria Town, Lahore'),
          ),
          pricingEstimatePortProvider.overrideWithValue(_FailingPricing()),
        ],
      );
      addTearDown(c.dispose);
      final sub = c.listen(rideRequestViewModelProvider, (_, __) {});
      addTearDown(sub.close);
      final vm = c.read(rideRequestViewModelProvider.notifier);

      await vm.useCurrentLocationForPickup();
      final proposed =
          c.read(rideRequestViewModelProvider).proposedPickup!;
      expect(proposed.address, 'Bahria Town, Lahore');
      expect(proposed.lat, 31.46);
      expect(proposed.lng, 74.26);
      expect(proposed.horizontalAccuracyMeters, 8.0);
    });

    test('retry re-runs naming only and preserves coords + accuracy', () async {
      final places = _ToggleablePlaces();
      final c = ProviderContainer(
        overrides: [
          rideRequestCapabilitiesProvider
              .overrideWithValue(const RideRequestCapabilities()),
          createRideUseCaseProvider.overrideWithValue(_MockCreate()),
          failureMapperProvider.overrideWithValue(const FailureMapper()),
          deviceLocationPortProvider.overrideWithValue(
            _AccurateDeviceLocation(accuracyMeters: 21.0),
          ),
          placeSearchPortProvider.overrideWithValue(places),
          pricingEstimatePortProvider.overrideWithValue(_FailingPricing()),
        ],
      );
      addTearDown(c.dispose);
      final sub = c.listen(rideRequestViewModelProvider, (_, __) {});
      addTearDown(sub.close);
      final vm = c.read(rideRequestViewModelProvider.notifier);

      await vm.useCurrentLocationForPickup();
      expect(
        c.read(rideRequestViewModelProvider).pickupNameUnresolved,
        isTrue,
      );

      places.name = 'Iqbal Town, Lahore';
      await vm.retryPickupNameLookup();

      final proposed =
          c.read(rideRequestViewModelProvider).proposedPickup!;
      expect(proposed.address, 'Iqbal Town, Lahore');
      expect(proposed.lat, 31.46);
      expect(proposed.lng, 74.26);
      expect(proposed.horizontalAccuracyMeters, 21.0);
      expect(
        c.read(rideRequestViewModelProvider).pickupNameUnresolved,
        isFalse,
      );
    });
  });
}

class _FakePrimary implements PlaceSearchPort {
  _FakePrimary({this.error, this.ok});
  final Object? error;
  final ResolvedPassengerLocation? ok;

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
      ok!;

  @override
  Future<ResolvedPassengerLocation> reverseGeocode({
    required double lat,
    required double lng,
  }) async {
    if (error != null) throw error!;
    return ok!;
  }
}

class _FakeDevice implements DeviceGeocoderPort {
  _FakeDevice(this.label);
  final String? label;
  int calls = 0;

  @override
  Future<String?> localityLabel({
    required double lat,
    required double lng,
  }) async {
    calls++;
    return label;
  }
}

class _MockCreate extends Mock implements CreateRideUseCase {}

class _AccurateDeviceLocation implements DeviceLocationPort {
  _AccurateDeviceLocation({required this.accuracyMeters});
  final double accuracyMeters;

  @override
  Future<ResolvedPassengerLocation> getCurrentLocation() async =>
      ResolvedPassengerLocation(
        lat: 31.46,
        lng: 74.26,
        source: PassengerLocationSource.gps,
        horizontalAccuracyMeters: accuracyMeters,
      );
}

class _FailingPlaces implements PlaceSearchPort {
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
      throw UnimplementedError();

  @override
  Future<ResolvedPassengerLocation> reverseGeocode({
    required double lat,
    required double lng,
  }) =>
      throw const PlaceSearchException(
        PlaceSearchFailureKind.network,
        'down',
      );
}

class _NamedPlaces extends _FailingPlaces {
  _NamedPlaces(this.name);
  final String name;

  @override
  Future<ResolvedPassengerLocation> reverseGeocode({
    required double lat,
    required double lng,
  }) async =>
      ResolvedPassengerLocation(
        lat: lat,
        lng: lng,
        address: name,
        source: PassengerLocationSource.gps,
      );
}

class _ToggleablePlaces extends _FailingPlaces {
  String? name;

  @override
  Future<ResolvedPassengerLocation> reverseGeocode({
    required double lat,
    required double lng,
  }) async {
    final n = name;
    if (n == null) {
      throw const PlaceSearchException(
        PlaceSearchFailureKind.network,
        'down',
      );
    }
    return ResolvedPassengerLocation(
      lat: lat,
      lng: lng,
      address: n,
      source: PassengerLocationSource.gps,
    );
  }
}

class _FailingPricing implements PricingEstimatePort {
  @override
  Future<PricingEstimate> estimate(PricingEstimateRequest request) =>
      throw const PricingClientException(
        PricingFailureKind.pricingUnavailable,
        'down',
      );
}
