import 'package:flutter_test/flutter_test.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';

void main() {
  test('Ride holds startedAt and completedAt for Phase 2G', () {
    const ride = Ride(
      rideId: 'r1',
      passengerId: 'p1',
      state: 'RIDE_COMPLETED',
      version: 6,
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
      updatedAt: '2026-01-01T00:10:00.000Z',
      assignedDriverId: 'd1',
      agreedFareMinor: 26000,
      startedAt: '2026-01-01T00:05:00.000Z',
      completedAt: '2026-01-01T00:10:00.000Z',
    );
    expect(ride.startedAt, isNotNull);
    expect(ride.completedAt, isNotNull);
    expect(ride.state, 'RIDE_COMPLETED');
  });

  test('Ride holds closedAt for Phase 2H', () {
    const ride = Ride(
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
      assignedDriverId: 'd1',
      agreedFareMinor: 26000,
      startedAt: '2026-01-01T00:05:00.000Z',
      completedAt: '2026-01-01T00:10:00.000Z',
      closedAt: '2026-01-01T00:12:00.000Z',
    );
    expect(ride.closedAt, isNotNull);
    expect(ride.state, 'RIDE_CLOSED');
  });

  test('Ride holds arrivedAt for Phase 2L', () {
    const ride = Ride(
      rideId: 'r1',
      passengerId: 'p1',
      state: 'DRIVER_ARRIVED',
      version: 4,
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
      updatedAt: '2026-01-01T00:04:00.000Z',
      assignedDriverId: 'd1',
      agreedFareMinor: 26000,
      arrivedAt: '2026-01-01T00:04:00.000Z',
    );
    expect(ride.arrivedAt, '2026-01-01T00:04:00.000Z');
    expect(ride.state, 'DRIVER_ARRIVED');
  });

  test('Ride holds NO_SHOW state for Phase 2M', () {
    const ride = Ride(
      rideId: 'r1',
      passengerId: 'p1',
      state: 'NO_SHOW',
      version: 5,
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
      updatedAt: '2026-01-01T00:09:00.000Z',
      assignedDriverId: 'd1',
      agreedFareMinor: 26000,
      arrivedAt: '2026-01-01T00:04:00.000Z',
    );
    expect(ride.state, 'NO_SHOW');
    expect(ride.arrivedAt, isNotNull);
    expect(ride.closedAt, isNull);
  });

  test('RideRating holds Phase 2N stars-only fields', () {
    const rating = RideRating(
      ratingId: 'r1_passenger_rates_driver',
      rideId: 'r1',
      raterId: 'p1',
      ratedId: 'd1',
      ratingType: 'passenger_rates_driver',
      stars: 5,
      createdAt: '2026-01-01T00:10:00.000Z',
    );
    expect(rating.stars, 5);
    expect(rating.ratingType, 'passenger_rates_driver');
    expect(rating.ratingId, 'r1_passenger_rates_driver');
  });
}
