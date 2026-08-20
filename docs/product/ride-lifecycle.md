# ORA — Ride Lifecycle

Product reference: publicly observable inDrive-style P2P behavior (passenger proposes a price, drivers accept or counter, passenger chooses). This is not a copy of undocumented inDrive internals.

Ride lifecycle and payment lifecycle are **separate**. See `docs/product/payment-flow.md`.

## Ride States (product)

```
DRAFT
ROUTE_READY
REQUEST_CREATED
SEARCHING
OFFERS_AVAILABLE
DRIVER_ASSIGNED
DRIVER_EN_ROUTE
DRIVER_ARRIVED
RIDE_STARTED
RIDE_COMPLETED
CANCELLED
EXPIRED
NO_SHOW
```

`RIDE_CLOSED` remains the post-completion **ride-aggregate** terminal from Phase 0.6 (receipts/outbox drain). It is not a passenger-facing product state.

`DRIVER_SELECTED` is **not** a durable public ride state. Selection commits directly to `DRIVER_ASSIGNED`.

---

## Complete Lifecycle Narrative

### 1. Pre-ride (DRAFT → ROUTE_READY)

The passenger opens the app and confirms pickup and destination. The pricing service calculates the route and returns a **recommended fare**. Client local state is `ROUTE_READY`. No ride document yet.

Recommended fare is guidance only.

### 2. Ride Creation (ROUTE_READY → REQUEST_CREATED → SEARCHING)

Passenger confirms their **offer price** and taps Confirm. App sends `POST /v1/rides` with:

- pickup / destination
- `passengerOfferMinor`
- category
- `paymentMethod` preference
- `pricingSnapshotId`
- idempotencyKey

Server:

1. Validates JWT + App Check
2. Validates offer against `OfferBoundPolicy` if configured
3. Creates `rides` document: `REQUEST_CREATED` then immediately `SEARCHING`
4. Stores `recommendedFareMinor`, `passengerOfferMinor`, `requestVersion`
5. Starts matching / dispatch waves
6. Returns `{ rideId, state: "SEARCHING" }`

`agreedFareMinor` is null. No driver is assigned.

### 3. Dispatch (SEARCHING)

Matching engine finds eligible nearby drivers and **presents** the request (RTDB pending card + FCM). See `docs/algorithms/matching-engine.md`.

Dispatch ≠ assignment. Drivers seeing the card are not assigned.

Waves continue while the ride is `SEARCHING` or `OFFERS_AVAILABLE` until assignment, cancel, or TTL.

### 4. Offers (SEARCHING → OFFERS_AVAILABLE)

Eligible drivers:

- **Accept** passenger price → `RideOffer` type `PASSENGER_PRICE_ACCEPTED`, status `PENDING`
- **Counter** → `RideOffer` type `DRIVER_COUNTEROFFER`, status `PENDING`
- **Decline** → miss record; no offer

First pending offer moves the ride to `OFFERS_AVAILABLE`. Multiple concurrent accepts create **multiple pending offers**, not a winner.

Expired / withdrawn / stale offers cannot be selected.

### 5. Assignment (OFFERS_AVAILABLE → DRIVER_ASSIGNED)

Passenger selects one offer: `POST /v1/rides/{rideId}/offers/{offerId}/select`.

Firestore transaction:

- asserts ride still selectable and unassigned
- asserts offer `PENDING`, not expired, matching `requestVersion`, driver still eligible
- writes `DRIVER_ASSIGNED`, `assignedDriverId`, immutable `agreedFareMinor`
- marks offer `SELECTED`; siblings `SUPERSEDED`
- writes outbox `ride.assigned`

There is no Direct Mode. Driver Accept never assigns.

### 6. Pickup (DRIVER_ASSIGNED → DRIVER_EN_ROUTE → DRIVER_ARRIVED)

Assigned driver navigates to pickup. Passenger sees the driver marker.

Arrive validates proximity and minimum time since assignment.

### 7. Trip (DRIVER_ARRIVED → RIDE_STARTED → RIDE_COMPLETED)

Start and complete remain server-validated (proximity, duration, plausibility).

`RIDE_COMPLETED` ends the operational ride. Payment continues on the **payment aggregate**.

### 8. Payment (separate)

Payment obligation is created from **agreedFare**, never from recommended fare. See `docs/product/payment-flow.md`.

### 9. Rating

Both parties rate. Ratings affect later ranking, not historical agreed fare.

### 10. Cancellation Paths

| Who | When | Penalty |
|---|---|---|
| Passenger | Before DRIVER_ASSIGNED | Free |
| Passenger | After assignment, before DRIVER_ARRIVED | Warning; fee if policy says so |
| Passenger | After DRIVER_ARRIVED | Cancellation fee if policy says so |
| Driver | Before DRIVER_EN_ROUTE | May affect acceptance metrics |
| Driver | After DRIVER_ARRIVED | Stronger penalty if policy says so |
| Server | SEARCHING / OFFERS_AVAILABLE TTL | EXPIRED |
| Server | DRIVER_ARRIVED wait TTL | NO_SHOW |

Pending offers on cancel/expiry become `EXPIRED` or `WITHDRAWN` and cannot assign.

## Key Events Table

| Event | Triggered By | Effect |
|---|---|---|
| `ride.created` | Server | Dispatch begins |
| `ride.offer.created` | Driver Accept/Counter | Pending offer; may enter OFFERS_AVAILABLE |
| `ride.offer.selected` | Passenger select | Selected offer marked; siblings superseded |
| `ride.assigned` | Server transaction | One driver assigned; agreedFare immutable |
| `driver.en_route` | Driver | Passenger sees ETA |
| `driver.arrived` | Server (geofence) / Driver | Wait timer starts |
| `ride.started` | Driver | Trip in progress |
| `ride.completed` | Driver | Payment obligation from agreedFare |
| `ride.cancelled.*` | Passenger / Driver | Offers invalidated |
| `ride.expired` | Server | No selectable assignment |
| `payment.*` | Payment service | Independent payment SM |
