import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/core/errors/failure_mapper.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';
import 'package:ora/features/ride/domain/use_cases/ride_use_cases.dart';
import 'package:ora/features/ride/presentation/view_models/ride_request_view_model.dart';

class MockCreateRideUseCase extends Mock implements CreateRideUseCase {}

Ride _sampleRide({String state = 'REQUESTED'}) {
  return Ride(
    rideId: 'ride-abc-123456',
    passengerId: 'p1',
    state: state,
    version: 1,
    requestVersion: 1,
    category: 'easy',
    serviceType: 'ride',
    pickup: const LatLngPoint(lat: 24.86, lng: 67.0, address: 'A'),
    destination: const LatLngPoint(lat: 24.9, lng: 67.1, address: 'B'),
    pricingSnapshotId: 'snap-1',
    recommendedFareMinor: 25000,
    passengerOfferMinor: 25000,
    paymentMethod: 'CASH',
    passengerCount: 1,
    expiresAt: '2099-01-01T00:00:00.000Z',
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
  });

  ProviderContainer container({
    RideRequestCapabilities caps = const RideRequestCapabilities(),
    MockCreateRideUseCase? createRide,
  }) {
    final mock = createRide ?? MockCreateRideUseCase();
    return ProviderContainer(
      overrides: [
        rideRequestCapabilitiesProvider.overrideWithValue(caps),
        createRideUseCaseProvider.overrideWithValue(mock),
        failureMapperProvider.overrideWithValue(const FailureMapper()),
      ],
    );
  }

  test('starts in compose and blocks incomplete review', () {
    final c = container();
    addTearDown(c.dispose);
    final vm = c.read(rideRequestViewModelProvider.notifier);
    expect(c.read(rideRequestViewModelProvider).phase, RideRequestPhase.compose);

    vm.goToReview();
    expect(
      c.read(rideRequestViewModelProvider).blockReason,
      RideRequestBlockReason.incomplete,
    );
  });

  test('advances to review when pickup and destination text exist', () {
    final c = container();
    addTearDown(c.dispose);
    final vm = c.read(rideRequestViewModelProvider.notifier);
    vm.setPickupText('Gulberg');
    vm.setDestinationText('Liberty');
    vm.goToReview();
    expect(c.read(rideRequestViewModelProvider).phase, RideRequestPhase.review);
  });

  test('category selection updates state', () {
    final c = container();
    addTearDown(c.dispose);
    final vm = c.read(rideRequestViewModelProvider.notifier);
    vm.selectCategory('premium');
    expect(c.read(rideRequestViewModelProvider).categoryId, 'premium');
  });

  test('pricing gate — createRide is NOT called without snapshot', () async {
    final createRide = MockCreateRideUseCase();
    final c = container(createRide: createRide);
    addTearDown(c.dispose);
    final vm = c.read(rideRequestViewModelProvider.notifier);
    vm.setPickupText('A');
    vm.setDestinationText('B');
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

  test('location gate when pricing exists but coords do not', () async {
    final createRide = MockCreateRideUseCase();
    final c = container(
      createRide: createRide,
      caps: const RideRequestCapabilities(
        pricingSnapshotId: 'snap-1',
        passengerOfferMinor: 25000,
      ),
    );
    addTearDown(c.dispose);
    final vm = c.read(rideRequestViewModelProvider.notifier);
    vm.setPickupText('A');
    vm.setDestinationText('B');
    vm.goToReview();
    await vm.submit();

    expect(
      c.read(rideRequestViewModelProvider).blockReason,
      RideRequestBlockReason.locationUnavailable,
    );
    verifyNever(
      () => createRide(
        body: any(named: 'body'),
        operationKey: any(named: 'operationKey'),
      ),
    );
  });

  test('create path calls CreateRideUseCase with valid body once', () async {
    final createRide = MockCreateRideUseCase();
    when(
      () => createRide(
        body: any(named: 'body'),
        operationKey: any(named: 'operationKey'),
      ),
    ).thenAnswer((_) async => _sampleRide());

    final caps = RideRequestCapabilities(
      pricingSnapshotId: 'snap-1',
      passengerOfferMinor: 25000,
      resolvedPickup: const LatLngPoint(lat: 24.86, lng: 67.0, address: 'A'),
      resolvedDestination:
          const LatLngPoint(lat: 24.9, lng: 67.1, address: 'B'),
    );
    final c = container(caps: caps, createRide: createRide);
    addTearDown(c.dispose);
    final vm = c.read(rideRequestViewModelProvider.notifier);
    vm.setPickupText('A');
    vm.setDestinationText('B');
    vm.selectCategory('easy');
    vm.goToReview();
    await vm.submit();

    final state = c.read(rideRequestViewModelProvider);
    expect(state.phase, RideRequestPhase.created);
    expect(state.createdRide?.rideId, 'ride-abc-123456');
    verify(
      () => createRide(
        body: any(
          named: 'body',
          that: isA<Map<String, Object?>>()
              .having((b) => b['pricingSnapshotId'], 'snap', 'snap-1')
              .having((b) => b['category'], 'category', 'easy')
              .having((b) => b['paymentMethod'], 'pay', 'CASH')
              .having((b) => b['passengerOfferMinor'], 'offer', 25000),
        ),
        operationKey: any(named: 'operationKey'),
      ),
    ).called(1);
  });

  test('duplicate submit while submitting is ignored', () async {
    final createRide = MockCreateRideUseCase();
    when(
      () => createRide(
        body: any(named: 'body'),
        operationKey: any(named: 'operationKey'),
      ),
    ).thenAnswer((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      return _sampleRide();
    });

    final caps = RideRequestCapabilities(
      pricingSnapshotId: 'snap-1',
      passengerOfferMinor: 25000,
      resolvedPickup: const LatLngPoint(lat: 1, lng: 2),
      resolvedDestination: const LatLngPoint(lat: 3, lng: 4),
    );
    final c = container(caps: caps, createRide: createRide);
    addTearDown(c.dispose);
    final vm = c.read(rideRequestViewModelProvider.notifier);
    vm.setPickupText('A');
    vm.setDestinationText('B');
    vm.goToReview();

    final first = vm.submit();
    final second = vm.submit();
    await Future.wait([first, second]);

    verify(
      () => createRide(
        body: any(named: 'body'),
        operationKey: any(named: 'operationKey'),
      ),
    ).called(1);
  });

  test('maps create failures to safe error phase', () async {
    final createRide = MockCreateRideUseCase();
    when(
      () => createRide(
        body: any(named: 'body'),
        operationKey: any(named: 'operationKey'),
      ),
    ).thenThrow(Exception('raw dio boom'));

    final caps = RideRequestCapabilities(
      pricingSnapshotId: 'snap-1',
      passengerOfferMinor: 25000,
      resolvedPickup: const LatLngPoint(lat: 1, lng: 2),
      resolvedDestination: const LatLngPoint(lat: 3, lng: 4),
    );
    final c = container(caps: caps, createRide: createRide);
    addTearDown(c.dispose);
    final vm = c.read(rideRequestViewModelProvider.notifier);
    vm.setPickupText('A');
    vm.setDestinationText('B');
    vm.goToReview();
    await vm.submit();

    final state = c.read(rideRequestViewModelProvider);
    expect(state.phase, RideRequestPhase.error);
    expect(state.errorMessage, isNotNull);
    expect(state.errorMessage!.toLowerCase(), isNot(contains('dio')));
    expect(state.errorMessage!.toLowerCase(), isNot(contains('exception')));
  });
}
