import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/core/errors/failure_mapper.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';
import 'package:ora/features/ride/domain/models/resolved_passenger_location.dart';
import 'package:ora/features/ride/domain/ports/device_location_port.dart';
import 'package:ora/features/ride/domain/ports/place_search_port.dart';
import 'package:ora/features/ride/domain/ports/pricing_estimate_port.dart';
import 'package:ora/features/ride/domain/use_cases/ride_use_cases.dart';
import 'package:ora/features/ride/presentation/view_models/ride_request_view_model.dart';

class MockCreateRideUseCase extends Mock implements CreateRideUseCase {}

class FakeDeviceLocation extends Fake implements DeviceLocationPort {
  FakeDeviceLocation({this.result, this.error});

  ResolvedPassengerLocation? result;
  Object? error;

  @override
  Future<ResolvedPassengerLocation> getCurrentLocation() async {
    if (error != null) throw error!;
    return result!;
  }
}

class FakePlaceSearch extends Fake implements PlaceSearchPort {
  FakePlaceSearch({
    this.suggestions = const [],
    this.resolved,
    this.autocompleteError,
    this.resolveError,
  });

  List<PlaceSuggestion> suggestions;
  ResolvedPassengerLocation? resolved;
  Object? autocompleteError;
  Object? resolveError;
  int autocompleteCalls = 0;
  int resolveCalls = 0;

  @override
  Future<List<PlaceSuggestion>> autocomplete({
    required String query,
    required String sessionToken,
  }) async {
    autocompleteCalls++;
    if (autocompleteError != null) throw autocompleteError!;
    return suggestions;
  }

  @override
  Future<ResolvedPassengerLocation> resolvePlace({
    required String placeId,
    required String sessionToken,
  }) async {
    resolveCalls++;
    if (resolveError != null) throw resolveError!;
    return resolved!;
  }
}

class FakePricingPort implements PricingEstimatePort {
  FakePricingPort({
    this.estimateResult,
    this.error,
    this.delay,
    this.onEstimate,
  });

  PricingEstimate? estimateResult;
  Object? error;
  Duration? delay;
  void Function(PricingEstimateRequest request)? onEstimate;
  int estimateCalls = 0;
  final List<PricingEstimateRequest> requests = [];

  @override
  Future<PricingEstimate> estimate(PricingEstimateRequest request) async {
    estimateCalls++;
    requests.add(request);
    onEstimate?.call(request);
    if (delay != null) await Future<void>.delayed(delay!);
    if (error != null) throw error!;
    return estimateResult!;
  }
}

PricingEstimate _sampleEstimate({
  String snapshotId = 'ps_backend_abc',
  String category = 'easy',
  String expiresAt = '2099-01-01T00:00:00.000Z',
}) {
  return PricingEstimate(
    pricingSnapshotId: snapshotId,
    recommendedFareMinor: 42000,
    offerBoundMinMinor: 30000,
    offerBoundMaxMinor: 75000,
    currency: 'PKR',
    pricingRulesVersion: 'v1',
    computedAt: '2026-01-01T00:00:00.000Z',
    expiresAt: expiresAt,
    distanceKm: 3.6,
    durationMin: 12,
    category: category,
  );
}

Ride _sampleRide() {
  return const Ride(
    rideId: 'ride-abc-123456',
    passengerId: 'p1',
    state: 'SEARCHING',
    version: 1,
    requestVersion: 1,
    category: 'easy',
    serviceType: 'ride',
    pickup: LatLngPoint(lat: 24.86, lng: 67.0, address: 'A'),
    destination: LatLngPoint(lat: 24.9, lng: 67.1, address: 'B'),
    pricingSnapshotId: 'ps_backend_abc',
    recommendedFareMinor: 42000,
    passengerOfferMinor: 42000,
    paymentMethod: 'CASH',
    passengerCount: 1,
    expiresAt: '2099-01-01T00:00:00.000Z',
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
  );
}

const _pickupResolved = ResolvedPassengerLocation(
  lat: 31.5204,
  lng: 74.3587,
  address: 'Lahore Fort, Lahore',
  placeId: 'place-pickup',
  source: PassengerLocationSource.place,
);

const _destResolved = ResolvedPassengerLocation(
  lat: 31.5497,
  lng: 74.3436,
  address: 'Data Darbar, Lahore',
  placeId: 'place-dest',
  source: PassengerLocationSource.place,
);

const _gpsResolved = ResolvedPassengerLocation(
  lat: 31.46,
  lng: 74.26,
  address: 'Current location',
  source: PassengerLocationSource.gps,
);

void main() {
  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
  });

  ProviderContainer container({
    RideRequestCapabilities caps = const RideRequestCapabilities(),
    MockCreateRideUseCase? createRide,
    DeviceLocationPort? device,
    PlaceSearchPort? places,
    PricingEstimatePort? pricing,
  }) {
    final mock = createRide ?? MockCreateRideUseCase();
    return ProviderContainer(
      overrides: [
        rideRequestCapabilitiesProvider.overrideWithValue(caps),
        createRideUseCaseProvider.overrideWithValue(mock),
        failureMapperProvider.overrideWithValue(const FailureMapper()),
        deviceLocationPortProvider.overrideWithValue(
          device ?? FakeDeviceLocation(result: _gpsResolved),
        ),
        placeSearchPortProvider.overrideWithValue(
          places ??
              FakePlaceSearch(
                suggestions: const [
                  PlaceSuggestion(
                    placeId: 'place-pickup',
                    primaryText: 'Lahore Fort',
                    secondaryText: 'Lahore',
                  ),
                ],
                resolved: _pickupResolved,
              ),
        ),
        pricingEstimatePortProvider.overrideWithValue(
          pricing ??
              FakePricingPort(
                error: const PricingClientException(
                  PricingFailureKind.pricingUnavailable,
                  'Pricing isn\'t available right now.',
                ),
              ),
        ),
      ],
    );
  }

  Future<void> confirmBoth(
    RideRequestViewModel vm, {
    FakePlaceSearch? places,
  }) async {
    places?.resolved = _pickupResolved;
    await vm.selectPlaceSuggestion(
      field: LocationField.pickup,
      suggestion: const PlaceSuggestion(
        placeId: 'place-pickup',
        primaryText: 'Lahore Fort',
      ),
    );
    vm.confirmPickup();
    places?.resolved = _destResolved;
    await vm.selectPlaceSuggestion(
      field: LocationField.destination,
      suggestion: const PlaceSuggestion(
        placeId: 'place-dest',
        primaryText: 'Data Darbar',
      ),
    );
    vm.confirmDestination();
    await vm.requestPricingEstimate(force: true);
  }

  test('A — initial state has no resolved pickup/destination', () {
    final c = container();
    addTearDown(c.dispose);
    final state = c.read(rideRequestViewModelProvider);
    final caps = c.read(rideRequestViewModelProvider.notifier).capabilities;
    expect(state.confirmedPickup, isNull);
    expect(state.confirmedDestination, isNull);
    expect(caps.hasResolvedLocations, isFalse);
    expect(caps.hasPricing, isFalse);
  });

  test('B — successful place resolution creates coordinates', () async {
    final places = FakePlaceSearch(resolved: _pickupResolved);
    final c = container(places: places);
    addTearDown(c.dispose);
    final vm = c.read(rideRequestViewModelProvider.notifier);
    await vm.selectPlaceSuggestion(
      field: LocationField.pickup,
      suggestion: const PlaceSuggestion(
        placeId: 'place-pickup',
        primaryText: 'Lahore Fort',
      ),
    );
    final proposed = c.read(rideRequestViewModelProvider).proposedPickup;
    expect(proposed?.lat, 31.5204);
    expect(proposed?.lng, 74.3587);
    expect(proposed?.placeId, 'place-pickup');
  });

  test('C/D — GPS resolution creates coordinates with gps source', () async {
    final c = container(device: FakeDeviceLocation(result: _gpsResolved));
    addTearDown(c.dispose);
    final vm = c.read(rideRequestViewModelProvider.notifier);
    await vm.useCurrentLocationForPickup();
    final proposed = c.read(rideRequestViewModelProvider).proposedPickup;
    expect(proposed?.source, PassengerLocationSource.gps);
    expect(proposed?.lat, 31.46);
    expect(proposed?.lng, 74.26);
  });

  test('E — place source is marked correctly', () async {
    final places = FakePlaceSearch(resolved: _pickupResolved);
    final c = container(places: places);
    addTearDown(c.dispose);
    final vm = c.read(rideRequestViewModelProvider.notifier);
    await vm.selectPlaceSuggestion(
      field: LocationField.pickup,
      suggestion: const PlaceSuggestion(
        placeId: 'place-pickup',
        primaryText: 'Lahore Fort',
      ),
    );
    expect(
      c.read(rideRequestViewModelProvider).proposedPickup?.source,
      PassengerLocationSource.place,
    );
  });

  test('F — unresolved text does NOT produce coordinates', () {
    final c = container();
    addTearDown(c.dispose);
    final vm = c.read(rideRequestViewModelProvider.notifier);
    vm.setPickupText('Clifton');
    vm.setDestinationText('Saddar');
    final state = c.read(rideRequestViewModelProvider);
    expect(state.confirmedPickup, isNull);
    expect(state.confirmedDestination, isNull);
    expect(state.proposedPickup, isNull);
    expect(vm.capabilities.hasResolvedLocations, isFalse);
    expect(state.canAdvanceToReview, isFalse);
  });

  test('G — permission denial leaves pickup unresolved', () async {
    final c = container(
      device: FakeDeviceLocation(
        error: const DeviceLocationException(
          DeviceLocationFailureKind.permissionDenied,
        ),
      ),
    );
    addTearDown(c.dispose);
    final vm = c.read(rideRequestViewModelProvider.notifier);
    await vm.useCurrentLocationForPickup();
    final state = c.read(rideRequestViewModelProvider);
    expect(state.proposedPickup, isNull);
    expect(state.confirmedPickup, isNull);
    expect(state.pickupLookupError, contains('permission'));
  });

  test('H — Places failure leaves destination unresolved', () async {
    final places = FakePlaceSearch(
      resolveError: const PlaceSearchException(
        PlaceSearchFailureKind.network,
      ),
    );
    final c = container(places: places);
    addTearDown(c.dispose);
    final vm = c.read(rideRequestViewModelProvider.notifier);
    await vm.selectPlaceSuggestion(
      field: LocationField.destination,
      suggestion: const PlaceSuggestion(
        placeId: 'x',
        primaryText: 'Somewhere',
      ),
    );
    final state = c.read(rideRequestViewModelProvider);
    expect(state.proposedDestination, isNull);
    expect(state.confirmedDestination, isNull);
    expect(state.destinationLookupError, contains('available'));
  });

  test('I — confirming preserves resolved coordinates in capabilities', () async {
    final places = FakePlaceSearch(resolved: _pickupResolved);
    final c = container(places: places);
    addTearDown(c.dispose);
    final vm = c.read(rideRequestViewModelProvider.notifier);
    await confirmBoth(vm, places: places);
    await Future<void>.delayed(Duration.zero);
    final caps = vm.capabilities;
    expect(caps.resolvedPickup?.lat, 31.5204);
    expect(caps.resolvedDestination?.lat, 31.5497);
    expect(caps.hasResolvedLocations, isTrue);
    expect(caps.hasPricing, isFalse);
  });

  test('J — changing pickup text invalidates stale resolved state', () async {
    final places = FakePlaceSearch(resolved: _pickupResolved);
    final c = container(places: places);
    addTearDown(c.dispose);
    final vm = c.read(rideRequestViewModelProvider.notifier);
    await vm.selectPlaceSuggestion(
      field: LocationField.pickup,
      suggestion: const PlaceSuggestion(
        placeId: 'place-pickup',
        primaryText: 'Lahore Fort',
      ),
    );
    vm.confirmPickup();
    expect(c.read(rideRequestViewModelProvider).confirmedPickup, isNotNull);
    vm.setPickupText('Something else');
    final state = c.read(rideRequestViewModelProvider);
    expect(state.confirmedPickup, isNull);
    expect(state.proposedPickup, isNull);
  });

  test('K — changing destination invalidates old destination coordinates',
      () async {
    final places = FakePlaceSearch(resolved: _destResolved);
    final c = container(places: places);
    addTearDown(c.dispose);
    final vm = c.read(rideRequestViewModelProvider.notifier);
    await vm.selectPlaceSuggestion(
      field: LocationField.destination,
      suggestion: const PlaceSuggestion(
        placeId: 'place-dest',
        primaryText: 'Data Darbar',
      ),
    );
    vm.confirmDestination();
    vm.setDestinationText('New search');
    expect(c.read(rideRequestViewModelProvider).confirmedDestination, isNull);
  });

  test('pricing gate remains when estimate fails — no createRide', () async {
    final createRide = MockCreateRideUseCase();
    final places = FakePlaceSearch(resolved: _pickupResolved);
    final pricing = FakePricingPort(
      error: const PricingClientException(
        PricingFailureKind.pricingUnavailable,
      ),
    );
    final c = container(
      createRide: createRide,
      places: places,
      pricing: pricing,
    );
    addTearDown(c.dispose);
    final vm = c.read(rideRequestViewModelProvider.notifier);
    await confirmBoth(vm, places: places);
    vm.goToReview();
    await vm.submit();
    expect(
      c.read(rideRequestViewModelProvider).blockReason,
      RideRequestBlockReason.pricingUnavailable,
    );
    verifyNever(
      () => createRide(
        body: any(named: 'body'),
        operationKey: any(named: 'operationKey'),
      ),
    );
  });

  test('create path works when pricing + confirmed coords exist', () async {
    final createRide = MockCreateRideUseCase();
    when(
      () => createRide(
        body: any(named: 'body'),
        operationKey: any(named: 'operationKey'),
      ),
    ).thenAnswer((_) async => _sampleRide());

    final places = FakePlaceSearch(resolved: _pickupResolved);
    final c = container(
      createRide: createRide,
      places: places,
      caps: const RideRequestCapabilities(
        pricingSnapshotId: 'snap-1',
        passengerOfferMinor: 25000,
      ),
    );
    addTearDown(c.dispose);
    final vm = c.read(rideRequestViewModelProvider.notifier);
    await confirmBoth(vm, places: places);
    vm.goToReview();
    await vm.submit();
    expect(c.read(rideRequestViewModelProvider).phase, RideRequestPhase.created);
    verify(
      () => createRide(
        body: any(named: 'body'),
        operationKey: any(named: 'operationKey'),
      ),
    ).called(1);
  });

  test('stale place resolve does not overwrite newer selection', () async {
    late Completer<ResolvedPassengerLocation> first;
    late Completer<ResolvedPassengerLocation> second;
    var calls = 0;

    final c = container(
      places: _ResolveRacePlaceSearch(
        onResolve: () {
          calls++;
          if (calls == 1) {
            first = Completer<ResolvedPassengerLocation>();
            return first.future;
          }
          second = Completer<ResolvedPassengerLocation>();
          return second.future;
        },
      ),
    );
    addTearDown(c.dispose);
    final vm = c.read(rideRequestViewModelProvider.notifier);

    final firstFuture = vm.selectPlaceSuggestion(
      field: LocationField.pickup,
      suggestion: const PlaceSuggestion(
        placeId: 'a',
        primaryText: 'First',
      ),
    );
    final secondFuture = vm.selectPlaceSuggestion(
      field: LocationField.pickup,
      suggestion: const PlaceSuggestion(
        placeId: 'b',
        primaryText: 'Second',
      ),
    );

    second.complete(_destResolved);
    await secondFuture;
    first.complete(_pickupResolved);
    await firstFuture;

    final proposed = c.read(rideRequestViewModelProvider).proposedPickup;
    expect(proposed?.placeId, 'place-dest');
    expect(proposed?.lat, 31.5497);
  });

  group('Phase 5C pricing', () {
    test('1 confirmed locations trigger pricing request', () async {
      final pricing = FakePricingPort(estimateResult: _sampleEstimate());
      final places = FakePlaceSearch(resolved: _pickupResolved);
      final c = container(places: places, pricing: pricing);
      addTearDown(c.dispose);
      final vm = c.read(rideRequestViewModelProvider.notifier);
      await confirmBoth(vm, places: places);
      expect(pricing.estimateCalls, greaterThanOrEqualTo(1));
    });

    test('2/3 request contains coords category city — not fare fields', () async {
      final pricing = FakePricingPort(estimateResult: _sampleEstimate());
      final places = FakePlaceSearch(resolved: _pickupResolved);
      final c = container(places: places, pricing: pricing);
      addTearDown(c.dispose);
      final vm = c.read(rideRequestViewModelProvider.notifier);
      await confirmBoth(vm, places: places);
      final json = pricing.requests.last.toJson();
      expect(json['pickup'], isA<Map>());
      expect((json['pickup'] as Map)['lat'], 31.5204);
      expect((json['pickup'] as Map)['lng'], 74.3587);
      expect((json['destination'] as Map)['lat'], 31.5497);
      expect(json['category'], 'easy');
      expect(json['city'], 'lahore');
      expect(json.containsKey('distanceKm'), isFalse);
      expect(json.containsKey('durationMin'), isFalse);
      expect(json.containsKey('recommendedFareMinor'), isFalse);
      expect(json.containsKey('pricingSnapshotId'), isFalse);
      expect(json.containsKey('minFareMinor'), isFalse);
      expect(json.containsKey('maxFareMinor'), isFalse);
    });

    test('4/5/6 success stores backend pricingSnapshotId exactly', () async {
      final pricing = FakePricingPort(
        estimateResult: _sampleEstimate(snapshotId: 'ps_backend_xyz'),
      );
      final places = FakePlaceSearch(resolved: _pickupResolved);
      final c = container(places: places, pricing: pricing);
      addTearDown(c.dispose);
      final vm = c.read(rideRequestViewModelProvider.notifier);
      await confirmBoth(vm, places: places);
      final state = c.read(rideRequestViewModelProvider);
      expect(state.pricingStatus, PricingStatus.success);
      expect(state.pricingEstimate?.pricingSnapshotId, 'ps_backend_xyz');
      expect(vm.capabilities.pricingSnapshotId, 'ps_backend_xyz');
      expect(state.pricingEstimate?.pricingSnapshotId.startsWith('ps_'), isTrue);
    });

    test('7/8/9/10 estimate fields retained for display', () async {
      final pricing = FakePricingPort(estimateResult: _sampleEstimate());
      final places = FakePlaceSearch(resolved: _pickupResolved);
      final c = container(places: places, pricing: pricing);
      addTearDown(c.dispose);
      final vm = c.read(rideRequestViewModelProvider.notifier);
      await confirmBoth(vm, places: places);
      final e = c.read(rideRequestViewModelProvider).pricingEstimate!;
      expect(e.recommendedFareMinor, 42000);
      expect(e.offerBoundMinMinor, 30000);
      expect(e.offerBoundMaxMinor, 75000);
      expect(e.distanceKm, 3.6);
      expect(e.durationMin, 12);
      expect(e.currency, 'PKR');
    });

    test('11 pricing failure blocks ride creation', () async {
      final createRide = MockCreateRideUseCase();
      final pricing = FakePricingPort(
        error: const PricingClientException(
          PricingFailureKind.pricingUnavailable,
        ),
      );
      final places = FakePlaceSearch(resolved: _pickupResolved);
      final c = container(
        createRide: createRide,
        places: places,
        pricing: pricing,
      );
      addTearDown(c.dispose);
      final vm = c.read(rideRequestViewModelProvider.notifier);
      await confirmBoth(vm, places: places);
      vm.goToReview();
      await vm.submit();
      expect(
        c.read(rideRequestViewModelProvider).blockReason,
        RideRequestBlockReason.pricingUnavailable,
      );
      verifyNever(
        () => createRide(
          body: any(named: 'body'),
          operationKey: any(named: 'operationKey'),
        ),
      );
    });

    test('12 pricing loading blocks ride creation', () async {
      final createRide = MockCreateRideUseCase();
      final pricing = FakePricingPort(
        estimateResult: _sampleEstimate(),
        delay: const Duration(milliseconds: 200),
      );
      final places = FakePlaceSearch(resolved: _pickupResolved);
      final c = container(
        createRide: createRide,
        places: places,
        pricing: pricing,
      );
      addTearDown(c.dispose);
      final vm = c.read(rideRequestViewModelProvider.notifier);
      places.resolved = _pickupResolved;
      await vm.selectPlaceSuggestion(
        field: LocationField.pickup,
        suggestion: const PlaceSuggestion(
          placeId: 'place-pickup',
          primaryText: 'Lahore Fort',
        ),
      );
      vm.confirmPickup();
      places.resolved = _destResolved;
      await vm.selectPlaceSuggestion(
        field: LocationField.destination,
        suggestion: const PlaceSuggestion(
          placeId: 'place-dest',
          primaryText: 'Data Darbar',
        ),
      );
      vm.confirmDestination();
      // Force a delayed estimate and submit while loading.
      final pending = vm.requestPricingEstimate(force: true);
      expect(
        c.read(rideRequestViewModelProvider).pricingStatus,
        PricingStatus.loading,
      );
      await vm.submit();
      expect(
        c.read(rideRequestViewModelProvider).blockReason,
        RideRequestBlockReason.pricingUnavailable,
      );
      verifyNever(
        () => createRide(
          body: any(named: 'body'),
          operationKey: any(named: 'operationKey'),
        ),
      );
      await pending;
    });

    test('13 missing snapshot blocks ride creation', () async {
      final createRide = MockCreateRideUseCase();
      final places = FakePlaceSearch(resolved: _pickupResolved);
      final c = container(createRide: createRide, places: places);
      addTearDown(c.dispose);
      final vm = c.read(rideRequestViewModelProvider.notifier);
      await confirmBoth(vm, places: places);
      expect(vm.capabilities.pricingSnapshotId, isNull);
      await vm.submit();
      verifyNever(
        () => createRide(
          body: any(named: 'body'),
          operationKey: any(named: 'operationKey'),
        ),
      );
    });

    test('14 expired snapshot blocks ride creation', () async {
      final createRide = MockCreateRideUseCase();
      final pricing = FakePricingPort(
        estimateResult: _sampleEstimate(
          expiresAt: '2020-01-01T00:00:00.000Z',
        ),
      );
      final places = FakePlaceSearch(resolved: _pickupResolved);
      final c = container(
        createRide: createRide,
        places: places,
        pricing: pricing,
      );
      addTearDown(c.dispose);
      final vm = c.read(rideRequestViewModelProvider.notifier);
      await confirmBoth(vm, places: places);
      expect(c.read(rideRequestViewModelProvider).hasUsablePricing, isFalse);
      await vm.submit();
      verifyNever(
        () => createRide(
          body: any(named: 'body'),
          operationKey: any(named: 'operationKey'),
        ),
      );
    });

    test('15 pickup edit invalidates previous pricing', () async {
      final pricing = FakePricingPort(estimateResult: _sampleEstimate());
      final places = FakePlaceSearch(resolved: _pickupResolved);
      final c = container(places: places, pricing: pricing);
      addTearDown(c.dispose);
      final vm = c.read(rideRequestViewModelProvider.notifier);
      await confirmBoth(vm, places: places);
      expect(c.read(rideRequestViewModelProvider).pricingEstimate, isNotNull);
      vm.setPickupText('edited');
      final state = c.read(rideRequestViewModelProvider);
      expect(state.pricingEstimate, isNull);
      expect(state.pricingStatus, PricingStatus.idle);
      expect(vm.capabilities.pricingSnapshotId, isNull);
    });

    test('16 destination edit invalidates previous pricing', () async {
      final pricing = FakePricingPort(estimateResult: _sampleEstimate());
      final places = FakePlaceSearch(resolved: _pickupResolved);
      final c = container(places: places, pricing: pricing);
      addTearDown(c.dispose);
      final vm = c.read(rideRequestViewModelProvider.notifier);
      await confirmBoth(vm, places: places);
      vm.setDestinationText('edited dest');
      expect(c.read(rideRequestViewModelProvider).pricingEstimate, isNull);
      expect(vm.capabilities.pricingSnapshotId, isNull);
    });

    test('17 stale pricing response cannot overwrite newer pricing', () async {
      final completers = <Completer<PricingEstimate>>[];
      final pricing = _RacePricingPort(
        onEstimate: () {
          final c = Completer<PricingEstimate>();
          completers.add(c);
          return c.future;
        },
      );
      final places = FakePlaceSearch(resolved: _pickupResolved);
      final c = container(places: places, pricing: pricing);
      addTearDown(c.dispose);
      final vm = c.read(rideRequestViewModelProvider.notifier);
      places.resolved = _pickupResolved;
      await vm.selectPlaceSuggestion(
        field: LocationField.pickup,
        suggestion: const PlaceSuggestion(
          placeId: 'place-pickup',
          primaryText: 'Lahore Fort',
        ),
      );
      vm.confirmPickup();
      places.resolved = _destResolved;
      await vm.selectPlaceSuggestion(
        field: LocationField.destination,
        suggestion: const PlaceSuggestion(
          placeId: 'place-dest',
          primaryText: 'Data Darbar',
        ),
      );
      vm.confirmDestination();
      // Auto estimate from confirm is completers[0].
      final older = vm.requestPricingEstimate(force: true);
      final newer = vm.requestPricingEstimate(force: true);
      expect(completers.length, 3);

      completers[2].complete(_sampleEstimate(snapshotId: 'ps_newer'));
      await newer;
      completers[1].complete(_sampleEstimate(snapshotId: 'ps_stale'));
      await older;
      completers[0].complete(_sampleEstimate(snapshotId: 'ps_oldest'));

      expect(
        c.read(rideRequestViewModelProvider).pricingEstimate?.pricingSnapshotId,
        'ps_newer',
      );
    });

    test('18 retry performs a fresh estimate', () async {
      final pricing = FakePricingPort(estimateResult: _sampleEstimate());
      final places = FakePlaceSearch(resolved: _pickupResolved);
      final c = container(places: places, pricing: pricing);
      addTearDown(c.dispose);
      final vm = c.read(rideRequestViewModelProvider.notifier);
      await confirmBoth(vm, places: places);
      final before = pricing.estimateCalls;
      await vm.retryPricing();
      expect(pricing.estimateCalls, greaterThan(before));
    });

    test('19/20/21 success create includes backend snapshot + city', () async {
      final createRide = MockCreateRideUseCase();
      Map<String, Object?>? captured;
      when(
        () => createRide(
          body: any(named: 'body'),
          operationKey: any(named: 'operationKey'),
        ),
      ).thenAnswer((invocation) async {
        captured = Map<String, Object?>.from(
          invocation.namedArguments[#body] as Map,
        );
        return _sampleRide();
      });

      final pricing = FakePricingPort(
        estimateResult: _sampleEstimate(snapshotId: 'ps_live_99'),
      );
      final places = FakePlaceSearch(resolved: _pickupResolved);
      final c = container(
        createRide: createRide,
        places: places,
        pricing: pricing,
      );
      addTearDown(c.dispose);
      final vm = c.read(rideRequestViewModelProvider.notifier);
      await confirmBoth(vm, places: places);
      vm.goToReview();
      await vm.submit();
      expect(c.read(rideRequestViewModelProvider).phase, RideRequestPhase.created);
      expect(captured?['pricingSnapshotId'], 'ps_live_99');
      expect(captured?['city'], 'lahore');
      expect(captured?['passengerOfferMinor'], 42000);
      expect(pricing.requests.last.toJson()['city'], 'lahore');
    });
  });
}

class _ResolveRacePlaceSearch implements PlaceSearchPort {
  _ResolveRacePlaceSearch({required this.onResolve});

  final Future<ResolvedPassengerLocation> Function() onResolve;

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
  }) =>
      onResolve();
}

class _RacePricingPort implements PricingEstimatePort {
  _RacePricingPort({required this.onEstimate});

  final Future<PricingEstimate> Function() onEstimate;

  @override
  Future<PricingEstimate> estimate(PricingEstimateRequest request) =>
      onEstimate();
}
