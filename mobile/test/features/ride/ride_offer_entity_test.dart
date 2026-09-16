import 'package:flutter_test/flutter_test.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';

void main() {
  test('RideOffer holds withdrawnAt and terminal statuses', () {
    const pending = RideOffer(
      offerId: 'o1',
      rideId: 'r1',
      driverId: 'd1',
      amountMinor: 26000,
      currency: 'PKR',
      type: 'DRIVER_COUNTEROFFER',
      status: 'PENDING',
      requestVersion: 1,
      expiresAt: '2026-09-09T12:03:00.000Z',
      createdAt: '2026-09-09T12:00:00.000Z',
    );
    expect(pending.withdrawnAt, isNull);
    expect(pending.status, 'PENDING');

    const withdrawn = RideOffer(
      offerId: 'o1',
      rideId: 'r1',
      driverId: 'd1',
      amountMinor: 26000,
      currency: 'PKR',
      type: 'DRIVER_COUNTEROFFER',
      status: 'WITHDRAWN',
      requestVersion: 1,
      expiresAt: '2026-09-09T12:03:00.000Z',
      createdAt: '2026-09-09T12:00:00.000Z',
      withdrawnAt: '2026-09-09T12:01:00.000Z',
    );
    expect(withdrawn.withdrawnAt, '2026-09-09T12:01:00.000Z');
    expect(withdrawn.status, 'WITHDRAWN');
  });
}
