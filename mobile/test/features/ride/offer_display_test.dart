import 'package:flutter_test/flutter_test.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';
import 'package:ora/features/ride/presentation/offers/offer_display.dart';

void main() {
  test('formatOfferAmountMinor formats PKR from server minor units', () {
    expect(formatOfferAmountMinor(25000, 'PKR'), 'Rs 250');
    expect(formatOfferAmountMinor(25050, 'PKR'), 'Rs 250.50');
  });

  test('offerDriverLabel never invents names from null snapshot', () {
    const offer = RideOffer(
      offerId: 'o1',
      rideId: 'r1',
      driverId: 'd1',
      amountMinor: 1000,
      currency: 'PKR',
      type: 'COUNTER',
      status: 'PENDING',
      requestVersion: 1,
      expiresAt: '2099-01-01T00:00:00.000Z',
      createdAt: '2026-01-01T00:00:00.000Z',
      driverSnapshot: {'displayName': null, 'role': 'driver'},
    );
    expect(offerDriverLabel(offer), 'Driver offer');
  });

  test('offerDriverLabel uses real displayName when present', () {
    const offer = RideOffer(
      offerId: 'o1',
      rideId: 'r1',
      driverId: 'd1',
      amountMinor: 1000,
      currency: 'PKR',
      type: 'COUNTER',
      status: 'PENDING',
      requestVersion: 1,
      expiresAt: '2099-01-01T00:00:00.000Z',
      createdAt: '2026-01-01T00:00:00.000Z',
      driverSnapshot: {'displayName': 'Sana', 'role': 'driver'},
    );
    expect(offerDriverLabel(offer), 'Sana');
  });

  test('mergeOffersById deduplicates by offerId', () {
    RideOffer o(String id) => RideOffer(
          offerId: id,
          rideId: 'r1',
          driverId: 'd1',
          amountMinor: 1000,
          currency: 'PKR',
          type: 'COUNTER',
          status: 'PENDING',
          requestVersion: 1,
          expiresAt: '2099-01-01T00:00:00.000Z',
          createdAt: '2026-01-01T00:00:00.000Z',
        );
    final merged = mergeOffersById([o('a'), o('b'), o('a')]);
    expect(merged.map((e) => e.offerId).toList(), ['a', 'b']);
  });
}
