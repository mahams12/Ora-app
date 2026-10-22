import 'package:flutter_test/flutter_test.dart';
import 'package:ora/features/driver/domain/driver_earnings_summary.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';

Ride _ride({
  required String id,
  String state = 'RIDE_CLOSED',
  int? agreedFareMinor,
  String? agreedFareCurrency,
  int? driverPayoutMinor,
  String? payoutCurrency,
  String? feePolicyResolution,
  String? completedAt,
  String? closedAt,
  String createdAt = '2026-03-01T10:00:00.000Z',
}) {
  return Ride(
    rideId: id,
    passengerId: 'p1',
    assignedDriverId: 'd1',
    state: state,
    version: 1,
    requestVersion: 1,
    category: 'easy',
    serviceType: 'ride',
    pickup: const LatLngPoint(lat: 1, lng: 2),
    destination: const LatLngPoint(lat: 3, lng: 4),
    pricingSnapshotId: 'snap',
    recommendedFareMinor: 20000,
    passengerOfferMinor: 20000,
    paymentMethod: 'CASH',
    passengerCount: 1,
    expiresAt: '2099-01-01T00:00:00.000Z',
    createdAt: createdAt,
    updatedAt: createdAt,
    agreedFareMinor: agreedFareMinor,
    agreedFareCurrency: agreedFareCurrency,
    driverPayoutMinor: driverPayoutMinor,
    payoutCurrency: payoutCurrency,
    feePolicyResolution: feePolicyResolution,
    completedAt: completedAt,
    closedAt: closedAt,
  );
}

void main() {
  final now = DateTime(2026, 3, 10, 15);

  String iso(DateTime t) => t.toUtc().toIso8601String();

  test('sums agreed fares across completed rides only', () {
    final summary = computeDriverEarnings([
      _ride(id: 'r1', agreedFareMinor: 50000, completedAt: iso(now)),
      _ride(id: 'r2', agreedFareMinor: 30000, completedAt: iso(now)),
      _ride(id: 'r3', state: 'CANCELLED', agreedFareMinor: 99900),
      _ride(id: 'r4', state: 'RIDE_STARTED', agreedFareMinor: 99900),
      _ride(id: 'r5', state: 'NO_SHOW', agreedFareMinor: 99900),
    ], now: now);

    expect(summary.completedRideCount, 2);
    expect(summary.allTime.faresMinor, 80000);
    expect(summary.allTime.currency, 'PKR');
    expect(summary.ridesWithFare, 2);
    expect(summary.ridesMissingFare, 0);
  });

  test('completed rides without a fare are counted but excluded from totals', () {
    final summary = computeDriverEarnings([
      _ride(id: 'r1', agreedFareMinor: 40000, completedAt: iso(now)),
      _ride(id: 'r2', completedAt: iso(now)), // no agreed fare recorded
    ], now: now);

    expect(summary.completedRideCount, 2);
    expect(summary.ridesWithFare, 1);
    expect(summary.ridesMissingFare, 1);
    expect(summary.allTime.faresMinor, 40000);
    expect(summary.allTime.rideCount, 2);
  });

  test('today / last-7-days windows bucket by completion time', () {
    final summary = computeDriverEarnings([
      _ride(id: 'today', agreedFareMinor: 10000, completedAt: iso(now)),
      _ride(
        id: 'week',
        agreedFareMinor: 20000,
        completedAt: iso(now.subtract(const Duration(days: 3))),
      ),
      _ride(
        id: 'old',
        agreedFareMinor: 40000,
        completedAt: iso(now.subtract(const Duration(days: 30))),
      ),
    ], now: now);

    expect(summary.today.rideCount, 1);
    expect(summary.today.faresMinor, 10000);
    expect(summary.last7Days.rideCount, 2);
    expect(summary.last7Days.faresMinor, 30000);
    expect(summary.allTime.rideCount, 3);
    expect(summary.allTime.faresMinor, 70000);
  });

  test('mixed currencies disable the uniform currency label', () {
    final summary = computeDriverEarnings([
      _ride(id: 'a', agreedFareMinor: 10000, agreedFareCurrency: 'PKR'),
      _ride(id: 'b', agreedFareMinor: 500, agreedFareCurrency: 'USD'),
    ], now: now);

    expect(summary.allTime.currency, isNull);
    expect(summary.allTime.faresMinor, 10500);
  });

  test('falls back to closedAt then createdAt when completedAt is absent', () {
    final at = driverEarningsCompletionTime(
      _ride(id: 'r', closedAt: '2026-03-05T08:00:00.000Z'),
    );
    expect(at, isNotNull);
    expect(at!.toUtc(), DateTime.utc(2026, 3, 5, 8));
  });

  test('unparseable timestamps count in all-time but not windows', () {
    final summary = computeDriverEarnings([
      _ride(id: 'r', agreedFareMinor: 10000, completedAt: 'not-a-date',
          closedAt: 'also-bad', createdAt: ''),
    ], now: now);

    expect(summary.completedRideCount, 1);
    expect(summary.allTime.rideCount, 1);
    expect(summary.allTime.faresMinor, 10000);
    expect(summary.today.rideCount, 0);
    expect(summary.last7Days.rideCount, 0);
  });

  test('empty history yields zeroed summary', () {
    final summary = computeDriverEarnings(const [], now: now);
    expect(summary.completedRideCount, 0);
    expect(summary.allTime.faresMinor, 0);
    expect(summary.ridesMissingFare, 0);
  });

  test('payout-backed rides sum driverPayoutMinor as the payout basis', () {
    final summary = computeDriverEarnings([
      _ride(
        id: 'r1',
        agreedFareMinor: 50000,
        driverPayoutMinor: 50000, // launch NONE fee → payout == fare
        payoutCurrency: 'PKR',
        feePolicyResolution: 'LAUNCH_DEFAULT',
        completedAt: iso(now),
      ),
      _ride(
        id: 'r2',
        agreedFareMinor: 30000,
        driverPayoutMinor: 25000, // a future fee world: payout != fare
        payoutCurrency: 'PKR',
        feePolicyResolution: 'APPLIED',
        completedAt: iso(now),
      ),
    ], now: now);

    expect(summary.ridesWithPayout, 2);
    expect(summary.ridesWithFare, 0); // both rides had a payout snapshot
    expect(summary.allTime.fareOnlyMinor, 0);
    expect(summary.allTime.payoutMinor, 75000);
    expect(summary.allTime.faresMinor, 75000); // payout basis preferred
    expect(summary.allTime.payoutRideCount, 2);
  });

  test('mixed payout + fare-only rides keep separate bases', () {
    final summary = computeDriverEarnings([
      _ride(
        id: 'new',
        agreedFareMinor: 50000,
        driverPayoutMinor: 50000,
        payoutCurrency: 'PKR',
        feePolicyResolution: 'APPLIED',
        completedAt: iso(now),
      ),
      _ride(
        id: 'old',
        agreedFareMinor: 30000, // pre-payout ride: fare only
        completedAt: iso(now),
      ),
    ], now: now);

    expect(summary.ridesWithPayout, 1);
    expect(summary.ridesWithFare, 1);
    expect(summary.allTime.payoutMinor, 50000);
    expect(summary.allTime.fareOnlyMinor, 30000);
    expect(summary.allTime.faresMinor, 80000); // effective total
  });

  test('payout present but fare absent still counts (not missing)', () {
    final summary = computeDriverEarnings([
      _ride(
        id: 'r',
        driverPayoutMinor: 42000,
        payoutCurrency: 'PKR',
        feePolicyResolution: 'APPLIED',
        completedAt: iso(now),
      ),
    ], now: now);

    expect(summary.ridesWithPayout, 1);
    expect(summary.ridesMissingFare, 0);
    expect(summary.allTime.faresMinor, 42000);
  });
}
