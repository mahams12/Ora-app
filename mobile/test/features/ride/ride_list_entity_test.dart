import 'package:flutter_test/flutter_test.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';
import 'package:ora/features/ride/domain/repositories/ride_repository.dart';
import 'package:ora/features/ride/domain/use_cases/ride_use_cases.dart';

class _FakeRideRepository implements RideRepository {
  RideListPage? lastPage;
  Map<String, Object?>? lastArgs;

  @override
  Future<RideListPage> listRides({
    int? limit,
    String? cursor,
    String? status,
    String? serviceType,
  }) async {
    lastArgs = {
      'limit': limit,
      'cursor': cursor,
      'status': status,
      'serviceType': serviceType,
    };
    return lastPage ??
        const RideListPage(rides: [], nextCursor: null);
  }

  @override
  Future<Ride> createRide({
    required Map<String, Object?> body,
    required String operationKey,
  }) =>
      throw UnimplementedError();

  @override
  Future<Ride> getRide(String rideId) => throw UnimplementedError();

  @override
  Future<OpenRideListPage> listOpenRides({
    int? limit,
    String? cursor,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<RideOffer>> listOffers(String rideId) =>
      throw UnimplementedError();

  @override
  Future<RideOffer> createOffer({
    required String rideId,
    required Map<String, Object?> body,
    required String operationKey,
  }) =>
      throw UnimplementedError();

  @override
  Future<RideOffer> withdrawOffer({
    required String rideId,
    required String offerId,
    required String operationKey,
  }) =>
      throw UnimplementedError();

  @override
  Future<RideAssignment> selectOffer({
    required String rideId,
    required String offerId,
    int? expectedVersion,
    required String operationKey,
  }) =>
      throw UnimplementedError();

  @override
  Future<Ride> cancelRide({
    required String rideId,
    String? reason,
    required String operationKey,
  }) =>
      throw UnimplementedError();

  @override
  Future<Ride> markEnRoute({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  }) =>
      throw UnimplementedError();

  @override
  Future<Ride> markArrived({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  }) =>
      throw UnimplementedError();

  @override
  Future<Ride> startRide({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  }) =>
      throw UnimplementedError();

  @override
  Future<Ride> completeRide({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  }) =>
      throw UnimplementedError();

  @override
  Future<Ride> closeRide({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  }) =>
      throw UnimplementedError();

  @override
  Future<RideRating> submitRating({
    required String rideId,
    required int stars,
    required String operationKey,
  }) =>
      throw UnimplementedError();

  @override
  Future<RideRating> getMyRating(String rideId) => throw UnimplementedError();
}

void main() {
  test('RideListPage holds rides and nextCursor', () {
    const page = RideListPage(
      rides: [
        Ride(
          rideId: 'r1',
          passengerId: 'p1',
          state: 'RIDE_CLOSED',
          version: 7,
          requestVersion: 1,
          category: 'economy',
          serviceType: 'ride',
          pickup: LatLngPoint(lat: 1, lng: 2),
          destination: LatLngPoint(lat: 3, lng: 4),
          pricingSnapshotId: 'snap',
          recommendedFareMinor: 25000,
          passengerOfferMinor: 25000,
          paymentMethod: 'CASH',
          passengerCount: 1,
          expiresAt: '2026-01-01T00:00:00.000Z',
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:12:00.000Z',
        ),
      ],
      nextCursor: 'opaque-cursor',
    );
    expect(page.rides, hasLength(1));
    expect(page.nextCursor, 'opaque-cursor');
  });

  test('ListRidesUseCase forwards filters to repository', () async {
    final repo = _FakeRideRepository()
      ..lastPage = const RideListPage(rides: [], nextCursor: 'next');
    final useCase = ListRidesUseCase(repo);
    final page = await useCase(
      limit: 10,
      cursor: 'c1',
      status: 'completed',
      serviceType: 'ride',
    );
    expect(page.nextCursor, 'next');
    expect(repo.lastArgs, {
      'limit': 10,
      'cursor': 'c1',
      'status': 'completed',
      'serviceType': 'ride',
    });
  });
}
