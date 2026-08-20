# ORA — Race Condition Test Suite

## Test A — Three driver offers, not three assignments

Concurrent Accept from three eligible drivers must create three `PENDING` offers. `assignedDriverId` remains null. Ride becomes `OFFERS_AVAILABLE`.

## Test B — Passenger selects one offer

Selecting offer B assigns driver B, copies `agreedFareMinor`, marks B `SELECTED`, siblings `SUPERSEDED`.

## Test C — Concurrent select of two offers (100 repetitions)

Double-send `select(offerA)` and `select(offerB)`. Every run: exactly one assigned driver; the other select is `409 ALREADY_ASSIGNED` or version conflict.

## Test D — Stale / expired offer cannot assign

Expire offer A, then select it → `422 OFFER_EXPIRED`, no assignment.

## Test E — Driver Accept is not assignment

`POST /offers` with `PASSENGER_PRICE_ACCEPTED` returns `201` and `rideState != DRIVER_ASSIGNED`.

```javascript
describe('P2P offer then assignment', () => {
  it('3 concurrent accepts create 3 pending offers, 0 assignments', async () => {
    const { rideId } = await createRide(passengerId, pricingSnapshotId);
    const [resA, resB, resC] = await Promise.all([
      createOffer(driverA, rideId, { type: 'PASSENGER_PRICE_ACCEPTED' }),
      createOffer(driverB, rideId, { type: 'PASSENGER_PRICE_ACCEPTED' }),
      createOffer(driverC, rideId, { type: 'PASSENGER_PRICE_ACCEPTED' }),
    ]);
    expect([resA, resB, resC].every(r => r.status === 201)).toBe(true);
    const ride = await getRide(rideId);
    expect(ride.assignedDriverId).toBeFalsy();
    expect(['SEARCHING', 'OFFERS_AVAILABLE']).toContain(ride.state);
    const offers = await listOffers(rideId);
    expect(offers.filter(o => o.status === 'PENDING').length).toBe(3);
  });

  it('Concurrent select of two offers — 100 repetitions — exactly one assignment', async () => {
    for (let round = 0; round < 100; round++) {
      const { rideId } = await createRide(passengerId, pricingSnapshotId);
      const offerA = await createOffer(driverA, rideId, { type: 'PASSENGER_PRICE_ACCEPTED' });
      const offerB = await createOffer(driverB, rideId, { type: 'DRIVER_COUNTEROFFER', amountMinor: 36000 });
      const [selA, selB] = await Promise.all([
        selectOffer(passengerId, rideId, offerA.offerId),
        selectOffer(passengerId, rideId, offerB.offerId),
      ]);
      const successes = [selA, selB].filter(r => r.status === 200);
      const conflicts = [selA, selB].filter(r => r.status === 409);
      expect(successes.length).toBe(1);
      expect(conflicts.length).toBe(1);
      const ride = await getRide(rideId);
      expect(ride.state).toBe('DRIVER_ASSIGNED');
      expect([driverA, driverB]).toContain(ride.assignedDriverId);
      expect(ride.agreedFareMinor).toBeTruthy();
    }
  });

  it('Expired offer cannot be selected', async () => {
    const offer = await createExpiringOffer(driverA, rideId);
    await advanceTimePast(offer.expiresAt);
    const res = await selectOffer(passengerId, rideId, offer.offerId);
    expect(res.status).toBe(422);
    expect(res.body.error.code).toBe('OFFER_EXPIRED');
    const ride = await getRide(rideId);
    expect(ride.assignedDriverId).toBeFalsy();
  });
});
```

## Secondary Races

### Offer after cancellation

Driver offer after passenger cancel → `409 STATE_CONFLICT`. No offer persisted as PENDING.

### Offer after expiry

Driver offer on expired ride → `409` / `410 RIDE_EXPIRED`.

### Duplicate offer from same driver

Second non-terminal offer for same ride+requestVersion → `409 OFFER_ALREADY_EXISTS` (idempotent replay if same key).

### Driver cannot select

Driver calling select-offer → `403 UNAUTHORIZED`.

### Double status update / simultaneous cancel

Unchanged from Phase 0.6: one terminal ride state; start cannot be applied twice.

## Load Tests

100 simultaneous ride creations remain 201. Assignment load test is concurrent **select**, not concurrent Accept-as-assign.
