# Database Model Audit (Firestore + Redis + RTDB)

Authoritative sources:
- `docs/database/firestore-schema.md`
- `docs/database/realtime-schema.md`
- `docs/database/redis-schema.md`
- `docs/database/indexes.md`

## Firestore (durable truth)

Collections (high-level):
- `users/{uid}` (profile + role + driverStatus + read-safe profile fields)
- `drivers/{driverId}` (approval-derived state + availabilityState + metrics)
- `vehicles/{vehicleId}` (vehicle approval + category eligibility)
- `driverDocuments/{driverId}` (document records and per-document review state)
- `rides/{rideId}` (authoritative ride aggregate: state, version, offers references, agreedFare snapshot, TTL)
- `rideOffers/{offerId}` (driver offers; status + requestVersion + expiration)
- `pricingSnapshots/{snapshotId}` and `pricingRules` / `feePolicies` (pricing config and snapshotted fee policy)
- `outboxEvents/{eventId}` (durable outbox event records — server-only)
- `rideEvents` (append-only audit log)
- Payments:
  - `paymentIntents/{id}`
  - `paymentAttempts/{id}`
  - `paymentProviderCallbacks/{provider}_{eventId}`
  - `walletAccounts/{uid}` (projection)
  - `walletLedgerEntries` (append-only ledger)
  - `driverPayouts`, `refunds`, `reconciliationRecords`
- Ratings:
  - `ratings/{rideId}_{ratingType}`
- Safety:
  - `safetyEvents/{eventId}`
- Places:
  - `savedPlaces/{placeId}` (nested under user)
- Misc:
  - `serviceAreas`, `hotZones`, `referrals`, `supportTickets` (mentioned in master plan; see master plan for details)

Ownership:
- **Server-only writes** for any correctness-critical aggregate and financial entities.

TTL / lifecycle:
- `rides.expiresAt` drives ride expiry sweeper (`docs/ORA_STATE_MACHINE.md`)
- `pricingSnapshots.expiresAt` for estimate snapshots
- Some ephemeral/cleanup is RTDB-driven after outbox projections.

## Redis (ephemeral / coordination / GEO)

Key patterns:
- `geo:drivers:{city}` — GEO index
- `lock:ride:{rideId}` — optional passenger select lock (contention reducer)
- `dispatch:notified:{rideId}` — list of dispatched drivers for cleanup
- `offer:dedup:{rideId}:{driverId}` — offer spam / duplicate offer prevention
- `idempotency:{key}` — optional cache hint only
- `driver:online:{driverId}` — cached presence hint (non-authoritative)
- Demand counters and rate-limiting counters

Redis degraded-mode:
- Correctness remains via Firestore; redis outages degrade dispatch performance/availability, not assignment authority.

## RTDB (ephemeral / projections)

Paths:
- `driverPresence/{driverId}` — driver presence (driver writes own)
- `rideAccess/{rideId}/{uid}` — server-managed access projection (client read gating)
- `tripLocations/{rideId}/latest` + bounded `recent` — server projection (writes are server-only)
- `rideSignals/{rideId}` — server projection for ride state/assignment signals
- `rideRequests/{driverId}/pending/{rideId}` — server writes for dispatch to a specific driver; deleted on assignment/cancel/TTL

## Indexes

Index guidance:
- single-field indexes auto-created for frequently queried fields
- composite indexes required as per `docs/database/indexes.md`
- **Index Exemptions** explicitly forbid indexing large/unqueried fields (e.g. `ride.routePolyline`)

## Phase 1.6 Freeze

The prior security/TTL gaps are now closed by:
- `docs/architecture-final/24-phase-1.6-condition-closure.md` section 1 (full collection-level security matrix)
- `docs/architecture-final/24-phase-1.6-condition-closure.md` section 11 (TTL/index freeze)

All correctness-critical collections are now classified as:
- client-readable
- client-writable (only where explicitly low-risk and authorized)
- backend-only
- admin/system-job only

No sensitive financial, assignment, verification, idempotency, or outbox collection remains unspecified.

