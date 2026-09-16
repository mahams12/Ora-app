# Phase 2F — Ride Offers

**Status:** Implemented on closed Phase 2E foundation (modular monolith).

## Scope delivered

- Hardened `POST /v1/rides/:id/offers` (eligibility, uniqueness, active-assignment guard, durable idempotency)
- Hardened `GET /v1/rides/:id/offers` (passenger-only, `requestVersion` filter, read-boundary expiry → `EXPIRED`)
- Hardened `POST /v1/rides/:id/offers/:oid/withdraw` (owner-only, expiry/state gates, `ride.offer.withdrawn` outbox)
- Shared `offer_lifecycle` helpers for PENDING / SELECTED / WITHDRAWN / SUPERSEDED / EXPIRED
- Index: `rides (assignedDriverId, state)` for active-assignment check
- Flutter: `withdrawnAt` on `RideOffer` parse path
- No Maps / GPS / RTDB / Redis / FCM / payments / dispatch / trip lifecycle / UI

## Offer lifecycle (server)

| From | To | How |
|------|----|-----|
| — | PENDING | Driver create offer |
| PENDING | SELECTED | Passenger select (Phase 2E assignment txn) |
| PENDING | WITHDRAWN | Driver withdraw |
| PENDING | SUPERSEDED | Sibling cleanup on assignment |
| PENDING | EXPIRED | Read/mutation boundary when `expiresAt <= now` (no sweeper in 2F) |

Illegal transitions remain rejected (`OFFER_NOT_SELECTABLE`, `OFFER_EXPIRED`, `ALREADY_ASSIGNED`, `STATE_CONFLICT`).

## Live Firestore offer-create concurrency

**STATE: LIVE FIRESTORE OFFER-CREATE CONCURRENCY PROVEN**

Harness: `backend/auth-service/scripts/run_ride_offer_create_firestore_concurrency.ts`  
Command: `npm run test:ride-offer-create-firestore-concurrency` (or root `npm run test:ride-offer-create-firestore-concurrency` via `emulators:exec`).

Proven against real Admin SDK `runTransaction` on Firestore emulator:

| Scenario | Result |
|----------|--------|
| Same driver 2/10/50 concurrent creates | Exactly 1 persisted offer; losers `OFFER_ALREADY_EXISTS` |
| Same idempotency key concurrent | Both 201 replay; version +1 once |
| Different keys same driver | 1 offer + uniqueness conflict |
| Different drivers | One offer per driver (`rideId_driverId_v{requestVersion}`) |
| Create vs cancel | One legal authoritative outcome |
| Create vs expired ride | `STATE_CONFLICT`; zero offers |

Contention observed (`updateFunction` multi-invocation / `contendedTxns > 0`).

## Explicitly not in Phase 2F

Maps, GPS, RTDB, Redis, FCM, production dispatch, proximity matching, payments, trip start/complete, Cargo, Delivery, Admin, ride UI.
