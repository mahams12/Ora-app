# Phase 2E — Ride Core Vertical Slice

**Status:** Implemented in `backend/auth-service` (modular monolith) + Flutter domain/data foundation.

## Scope delivered

- `POST/GET /v1/rides`, offers create/list/withdraw/select, passenger cancel (pre-assign)
- Firestore-authoritative ride + top-level `rideOffers`
- Durable `idempotencyRecords` with request hash + actor binding
- Assignment via Firestore transaction; agreed fare from selected offer only
- Bounded sibling supersede (`MAX_OFFERS_SUPERSEDE_IN_TXN = 50`)
- Outbox write for `ride.created` / `ride.offer.received` / `ride.offer.selected` / `ride.assigned` / `ride.cancelled` (no Pub/Sub yet)
- Pricing via fixture `pricingSnapshots/{id}` only (no Maps / live pricing)
- Flutter: `Ride` / `RideOffer`, repository, use cases, `IdempotencyNonceStore` on secure storage
- No ride UI, Maps, RTDB, Redis, FCM, payments

## States (this phase)

`SEARCHING` → `OFFERS_AVAILABLE` → `DRIVER_ASSIGNED` | `CANCELLED` | `EXPIRED` (EXPIRED reserved; search expiry not auto-swept yet)

Select rejects expired ride search windows (`ride.expiresAt`) with `STATE_CONFLICT` before assignment.

## Concurrency guarantee

Assignment correctness gate is `rides/{id}.assignedDriverId` + `state`. Sibling offer cleanup is best-effort within the 50-offer txn bound; cleanup failure cannot create a second assignment.

- Memory proof: `npm run test:ride-proof` (serialized memoryDb domain gates)
- **Live Firestore emulator proof:** `npm run test:ride-firestore-concurrency` (repo root) — real Admin SDK transactions against emulator port `8181`

Known harness notes:

- Optional pickup/destination `address` is omitted when absent (Firestore rejects `undefined`). Fixed in `parseLatLng`.
- Loading `firebase-admin` can hang when `node_modules` lives under a workspace path containing spaces; CI paths and no-space copies work.

## Phase 2E status

**CLOSED** — live Firestore concurrency proven; optional-address Firestore write bug fixed and regression-tested.

## Known limitations

- No production driver supply / dispatch / location
- Auth API envelope remains flat; ride APIs use `{ data, requestId, timestamp }`
- Local Vitest/tsx can hang when the workspace path contains spaces; CI (no spaces) and `test:ride-proof` (esbuild bundle) are the reliable local paths
