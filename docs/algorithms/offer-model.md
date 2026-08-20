# ORA — Offer Model

**Status:** CANONICAL  
**Product reference:** publicly observable inDrive-style P2P pricing (passenger proposes, drivers accept or counter, passenger chooses). This is not a copy of undocumented inDrive internals.

---

## 1. Dispatch Is Not Assignment

| Concept | Meaning | Result |
|---|---|---|
| **Dispatch** | Find eligible drivers and present the ride request | RTDB pending request + FCM; ride stays `SEARCHING` / `OFFERS_AVAILABLE` |
| **Offer** | Driver response to a dispatched request | Durable `rideOffers/{offerId}` |
| **Assignment** | Passenger selects one offer; Firestore transaction commits one driver | `DRIVER_ASSIGNED` + immutable `agreedFare` |

Driver **Accept** does **not** assign the ride.  
Driver **Accept** creates an offer of type `PASSENGER_PRICE_ACCEPTED`.  
Driver **Counter** creates an offer of type `DRIVER_COUNTEROFFER`.  
Driver **Decline** records a miss; no offer is created.

Passenger **Select** is the assignment command.

---

## 2. Fare Concepts (Four Distinct Values)

| Concept | Owner | Mutability |
|---|---|---|
| `recommendedFare` | Server pricing engine | Mutable before request if route/estimate changes; snapshotted at request create |
| `passengerOffer` | Passenger | Immutable for that request version |
| `driverCounterOffer` | Driver | Immutable offer record |
| `agreedFare` | Server, copied from the selected offer | Immutable after assignment |

Recommended fare is **guidance**. It is not the trip price.

---

## 3. Aggregates

### RideRequest (the `rides` document in SEARCHING / OFFERS_AVAILABLE)

Published passenger request containing pickup, destination, category, `passengerOfferMinor`, `recommendedFareMinor`, `requestVersion`, payment method preference.

### RideOffer

Durable driver response.

### CounterOffer

Not a separate aggregate. It is a `RideOffer` with `type = DRIVER_COUNTEROFFER`.

### AgreedFare

Not a separately writable collection. It is a server-written snapshot on the ride at assignment:

- `agreedFareMinor`
- `agreedOfferId`
- `agreedFareCurrency`
- `feePolicySnapshotId` (or inline fee snapshot)

---

## 4. RideOffer Schema

Collection: `rideOffers`  
Document ID: auto-generated `offerId`

```json
{
  "offerId": "offer_01J...",
  "rideId": "ride_abc123",
  "driverId": "drv_456",
  "amountMinor": 34000,
  "currency": "PKR",
  "type": "PASSENGER_PRICE_ACCEPTED",
  "createdAt": "2026-08-18T07:30:12Z",
  "expiresAt": "2026-08-18T07:33:12Z",
  "status": "PENDING",
  "requestVersion": 1,
  "driverSnapshot": {
    "displayName": "Moin Sultan",
    "rating": 4.88,
    "ratingCount": 1247,
    "completedRides": 1192,
    "vehicle": {
      "make": "Suzuki",
      "model": "Alto",
      "color": "White",
      "plate": "LEA-2231",
      "category": "easy"
    },
    "etaMin": 4,
    "distanceToPickupKm": 1.1
  },
  "metadata": {
    "message": null,
    "idempotencyKey": "ride_abc123:offer:drv_456:nonce_789"
  }
}
```

### Offer types

| Type | Meaning |
|---|---|
| `PASSENGER_PRICE_ACCEPTED` | Driver agrees to the passenger's current offer |
| `DRIVER_COUNTEROFFER` | Driver proposes a different `amountMinor` |

### Offer statuses

| Status | Meaning |
|---|---|
| `PENDING` | Visible to passenger; selectable |
| `ACCEPTED` | Driver created it by accepting passenger price (still pending passenger selection; prefer `PENDING` as the selectable state) |
| `SELECTED` | Passenger selected this offer; assignment committed |
| `REJECTED` | Passenger dismissed this offer (optional UX) |
| `EXPIRED` | Past `expiresAt` or ride left offer window |
| `WITHDRAWN` | Driver withdrew before selection |
| `SUPERSEDED` | Ride assigned to a different offer |

Canonical selectable status is **`PENDING`**.  
`ACCEPTED` in the product sense means “driver accepted the passenger price”; persist that as `type = PASSENGER_PRICE_ACCEPTED` with `status = PENDING` until the passenger selects it. After selection, status becomes `SELECTED`.

Do not treat offer `ACCEPTED` as ride `DRIVER_ASSIGNED`.

---

## 5. Offer Rules

1. A driver may have **at most one non-terminal offer** per `rideId` + `requestVersion`.
2. Driver must be in `dispatch:notified:{rideId}` (or pass the same eligibility checks at offer time).
3. Driver cannot offer on another passenger's ride.
4. Driver cannot offer if they have an active non-terminal assigned ride.
5. `DRIVER_COUNTEROFFER.amountMinor` must pass the same configurable offer-bound policy as passenger offers, evaluated against the request's `recommendedFareMinor`.
6. `PASSENGER_PRICE_ACCEPTED.amountMinor` must equal the ride's current `passengerOfferMinor`.
7. Offers are immutable except `status` transitions performed by the server.
8. An offer with `status != PENDING` or `expiresAt <= now` **must never** become an assignment.

---

## 6. Assignment From Selection

Passenger command: `POST /v1/rides/{rideId}/offers/{offerId}/select`

Firestore transaction (authoritative):

1. Read ride; assert `state in {SEARCHING, OFFERS_AVAILABLE}`
2. Assert `assignedDriverId == null`
3. Assert `version == expectedVersion` (or current version check)
4. Read offer; assert `offer.rideId == rideId`
5. Assert `offer.status == PENDING`
6. Assert `offer.expiresAt > now`
7. Assert `offer.requestVersion == ride.requestVersion`
8. Re-validate driver eligibility
9. Write:
   - `state = DRIVER_ASSIGNED`
   - `assignedDriverId = offer.driverId`
   - `agreedFareMinor = offer.amountMinor`
   - `agreedOfferId = offerId`
   - `version++`
   - snapshot `FeePolicy` into the ride
10. Mark selected offer `SELECTED`; mark sibling pending offers `SUPERSEDED`
11. Write outbox `ride.assigned`

Exactly one such transaction can commit.

---

## 7. Stale Offer Handling

| Condition | Server behavior |
|---|---|
| Offer expired | Sweeper sets `EXPIRED`; select returns `422 OFFER_EXPIRED` |
| Ride already assigned | Select returns `409 RIDE_CONFLICT` / `ALREADY_ASSIGNED` |
| Ride cancelled/expired | Select returns `409 STATE_CONFLICT`; offers set `EXPIRED` |
| `requestVersion` mismatch | Select returns `422 OFFER_STALE` |
| Driver went offline / became ineligible | Select returns `422 DRIVER_NOT_ELIGIBLE`; offer withdrawn or rejected |
| Duplicate select same offer | Idempotent success if already `SELECTED` for this ride |

Passenger UI must refresh from Firestore. A locally cached offer card is never sufficient to assign.

---

## 8. Realtime Projection

- Passenger listens to Firestore `rideOffers` where `rideId == current` and `status == PENDING`
- Driver pending request lives in RTDB `rideRequests/{driverId}/pending/{rideId}` until they offer, decline, TTL, or the ride is assigned/cancelled
- After assignment, RTDB deletes remaining pending request cards
- Selected driver receives `ride.assigned`; others receive ride-closed / superseded signals

---

## 9. Security

| Actor | Allowed |
|---|---|
| Passenger | Create own ride + `passengerOffer`; select an offer on own ride |
| Driver | Create offer only if dispatched/eligible for that ride |
| Driver | Cannot select themselves; no select-offer API for drivers |
| Any client | Cannot write `agreedFareMinor`, `assignedDriverId`, offer `status`, ledger, payment state |
