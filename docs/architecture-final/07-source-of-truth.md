# Source-of-Truth Ownership (Single Owner Contract)

Authoritative sources:
- `docs/architecture-review/system-invariants.md`
- `docs/architecture-review/consistency-model.md`
- `docs/architecture/realtime-architecture.md`

For each concept below, there must be **exactly one authoritative owner**. Projections/caches are allowed but must be explicitly derived and recoverable.

## Ownership Table

- Ride status (state + version): **Firestore `rides`** (server transaction)
  - Projection: RTDB `rideSignals/{rideId}`
  - Recovery: Firestore re-read on reconnect

- Ride assignment (winner driver): **Firestore `rides.assignedDriverId` via select transaction**
  - Projection: RTDB `rideSignals`, FCM wake-up
  - Forbidden: Redis/FCM/RTDB must not assign

- Offer status (`rideOffers.status`): **Firestore `rideOffers`** (server-managed)
  - Projection: passenger offer inbox (client reads offers)
  - Recovery: re-query offers from Firestore

- Agreed fare: **Firestore `rides.agreedFareMinor` + `agreedOfferId`**
  - Projection: receipts UI
  - Recovery: re-read ride snapshot
  - Forbidden: client/driver cannot write

- Payment status: **Firestore payment aggregates** (`paymentIntents`, `paymentAttempts`)
  - Projection: ride summary fields / UI
  - Recovery: re-read payment aggregate

- Ledger balance: **Immutable ledger entries (`walletLedgerEntries`)**
  - Projection: `walletAccounts.balanceMinor`
  - Reconciliation: `reconciliationRecords` on mismatch

- Driver availability (business): **Firestore `drivers.availabilityState`** (+ `activeRideId`)
  - Projection: RTDB `driverPresence`
  - Redis: ephemeral `driver:online:*` hint

- Driver location (live): **Server-validated RTDB projection `tripLocations/{rideId}/latest`**
  - Redis: GEO index for dispatch efficiency (non-authoritative)
  - Client: map state (discard & re-attach)

- Passenger location: **Ride request coordinates stored in Firestore ride**
  - Live streaming is not the authoritative store

- ETA (for matching / display): **Server from routing services**, persisted as part of offer/ride projections
  - Projection: UI countdown
  - Recovery: re-fetch ride/offer info

- User identity: **Firebase Auth UID / ID token claims** (server validated)
  - Client cache allowed for UX; server is authoritative for protected operations

- Driver verification/KYC: **Firestore `driverDocuments` + admin approvals**
  - Driver may be marked eligible only after server approval

- Vehicle verification: **Firestore `vehicles.vehicleStatus` and `approvedCategories`**

- Notification delivery: **Outbox durability + subscriber idempotency**
  - FCM success is best-effort
  - Forbidden: notification success is not correctness-critical

- Safety incident: **Firestore `safetyEvents`**
  - Projection: support UI caches

- Rating: **Firestore `ratings`**
  - Projection: metrics/ranking values derived later

## Duplicated/Derived Data (Allowed)

- `drivers.rating` / metrics are derived from ratings history (not authoritative by themselves).
- Wallet balance is a projection; ledger is authoritative.
- Driver presence is ephemeral; Firestore driver availability is authoritative.

