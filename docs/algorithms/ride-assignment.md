# ORA — Ride Assignment Algorithm (Atomic)

## Problem Statement

Ora is a P2P offered-fare marketplace.

- Dispatch presents a request to eligible drivers.
- Drivers create **offers** (accept passenger price or counter).
- The **passenger selects one offer**.
- Exactly one driver may be assigned.
- The selected offer amount becomes immutable `agreedFareMinor`.

Driver Accept is **not** assignment.

## Dispatch vs Assignment

```
DISPATCH (matching engine)
  → notify eligible drivers
  → ride remains SEARCHING / OFFERS_AVAILABLE
  → no assignedDriverId

OFFER (driver accept or counter)
  → durable rideOffers document
  → still no assignment

ASSIGNMENT (passenger select)
  → Firestore transaction
  → assignedDriverId + agreedFareMinor
```

See `docs/algorithms/offer-model.md` and `docs/algorithms/matching-engine.md`.

---

## Assignment Command

`POST /v1/rides/{rideId}/offers/{offerId}/select`

Actor: passenger who owns the ride.  
Drivers cannot call this endpoint.

---

## Solution: Firestore Authoritative Selection Transaction

### Phase 1: Optional Redis contention lock

```redis
SET lock:ride:{rideId} {passengerId} NX EX 30
```

Used only to reduce double-tap contention on **select**. It is **not** the correctness barrier. It is **not** taken on driver accept.

### Phase 2: Firestore transaction

```javascript
await firestore.runTransaction(async (txn) => {
  const rideRef = firestore.doc(`rides/${rideId}`);
  const offerRef = firestore.doc(`rideOffers/${offerId}`);
  const ride = (await txn.get(rideRef)).data();
  const offer = (await txn.get(offerRef)).data();

  if (ride.passengerId !== callerUid) throw new Error('UNAUTHORIZED');
  if (ride.assignedDriverId) throw new Error('ALREADY_ASSIGNED');
  if (!['SEARCHING', 'OFFERS_AVAILABLE'].includes(ride.state)) {
    throw new Error('INVALID_STATE_TRANSITION');
  }
  if (offer.rideId !== rideId) throw new Error('OFFER_MISMATCH');
  if (offer.status !== 'PENDING') throw new Error('OFFER_NOT_SELECTABLE');
  if (offer.expiresAt.toMillis() <= Date.now()) throw new Error('OFFER_EXPIRED');
  if (offer.requestVersion !== ride.requestVersion) throw new Error('OFFER_STALE');
  // re-validate driver eligibility here

  txn.update(rideRef, {
    state: 'DRIVER_ASSIGNED',
    assignedDriverId: offer.driverId,
    agreedFareMinor: offer.amountMinor,
    agreedOfferId: offerId,
    feePolicySnapshot: feeSnapshot, // computed server-side
    assignedAt: serverTimestamp(),
    version: ride.version + 1,
  });

  txn.update(offerRef, { status: 'SELECTED' });

  txn.set(firestore.doc(`outboxEvents/${eventId}`), {
    eventId,
    eventType: 'ride.assigned',
    aggregateType: 'ride',
    aggregateId: rideId,
    aggregateVersion: ride.version + 1,
    schemaVersion: 1,
    occurredAt: serverTimestamp(),
    producer: 'ride-engine',
    correlationId: requestId,
    causationId: commandId,
    status: 'PENDING',
    attemptCount: 0,
    nextAttemptAt: serverTimestamp(),
    payload: {
      offerId,
      driverId: offer.driverId,
      agreedFareMinor: offer.amountMinor,
    },
  });
});
```

Sibling pending offers are marked `SUPERSEDED` in the same transaction or a tightly coupled follow-up that cannot resurrect them as selectable.

### Phase 3: Outbox-driven cleanup

After Firestore commit, assignment is authoritative.

Async projector:

1. Write `rideSignals/{rideId}` with `DRIVER_ASSIGNED`, `aggregateVersion`, `eventSequence`
2. Delete RTDB pending request cards for all dispatched drivers except the winner (winner card replaced by assigned trip UI)
3. Publish Pub/Sub / FCM: selected driver, losing drivers, passenger

---

## Driver Accept / Counter (Not Assignment)

`POST /v1/rides/{rideId}/offers`

```
1. Validate driver JWT, App Check, eligibility, dispatch membership
2. Enforce one non-terminal offer per driver per ride+requestVersion
3. If type = PASSENGER_PRICE_ACCEPTED: amountMinor must equal ride.passengerOfferMinor
4. If type = DRIVER_COUNTEROFFER: amountMinor must pass OfferBoundPolicy
5. Write rideOffers with status PENDING
6. If ride.state == SEARCHING → OFFERS_AVAILABLE
7. Outbox: ride.offer.received
```

Concurrent accepts from three drivers produce **three pending offers**, not one winner.

---

## Failure Scenarios

### Redis unavailable

Skip optional lock. Firestore transaction still guarantees one assignment.

### Select of expired offer

Transaction fails. `422 OFFER_EXPIRED`. Ride remains selectable if other pending offers exist.

### Concurrent select of two offers

Exactly one transaction commits. The other gets `409 ALREADY_ASSIGNED` or version conflict.

### Driver accept after assignment

`409 STATE_CONFLICT` / `ALREADY_ASSIGNED`. No new offer.

### Server crash after assignment commit, before RTDB

Outbox retries projections. Client recovers from Firestore.

---

## Race Tests (Required)

### Test A — Three driver offers, not three assignments

```
Drivers A, B, C all accept passenger price concurrently.
Expected: 3 PENDING offers, ride state OFFERS_AVAILABLE, assignedDriverId == null
```

### Test B — Passenger selects one offer

```
Passenger selects offer B.
Expected: assignedDriverId == B, agreedFareMinor == offer B amount, offer B SELECTED, A and C SUPERSEDED
```

### Test C — Concurrent select of two offers (100 repetitions)

```
Passenger double-sends select(offerA) and select(offerB).
Expected every run: exactly one assigned driver; the other select is 409
```

### Test D — Stale offer cannot assign

```
Expire offer A, then select offer A.
Expected: 422 OFFER_EXPIRED, no assignment
```
