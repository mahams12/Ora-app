# Phase 2G — Post-Assignment Ride Progression

**Status:** CLOSED (implementation + live Firestore proof)  
**Date:** 2026-09-09  
**Architecture:** `docs/implementation/phase-02g-architecture-investigation.md`

---

## 1. Scope

Implemented server-authoritative progression:

`DRIVER_ASSIGNED → DRIVER_EN_ROUTE → DRIVER_ARRIVED → RIDE_STARTED → RIDE_COMPLETED`

plus post-assignment cancel for **passenger owner** and **assigned driver** (through `RIDE_STARTED`, not after `RIDE_COMPLETED`).

Reused Phase 2E/2F: Firestore transactions, durable idempotency, outbox write-only, token-derived auth, modular monolith.

## 2. Files changed

| File | Change |
|------|--------|
| `backend/auth-service/src/rides/types.ts` | New ride states |
| `backend/auth-service/src/rides/state_machine.ts` | Progression + post-assign cancel gates |
| `backend/auth-service/src/rides/ride_service.ts` | `markEnRoute` / `markArrived` / `startRide` / `completeRide`; expanded `cancelRide`; `publicRide` timestamps |
| `backend/auth-service/src/rides/routes.ts` | `/en-route`, `/arrive`, `/start`, `/complete` |
| `backend/auth-service/src/__tests__/rides.test.ts` | Phase 2G matrix; select-vs-cancel updated for post-assign cancel |
| `backend/auth-service/scripts/run_ride_proof.ts` | Select-vs-cancel expectation aligned with 2G |
| `backend/auth-service/scripts/run_ride_firestore_concurrency.ts` | Select-vs-cancel live expectation aligned |
| `backend/auth-service/scripts/run_ride_progression_firestore_concurrency.ts` | **New** live harness |
| `backend/auth-service/package.json` / root `package.json` | `test:ride-progression-firestore-concurrency` |
| `mobile/lib/features/ride/**` | `startedAt`/`completedAt`; progression use cases/repo/datasource |
| `mobile/test/features/ride/ride_progression_entity_test.dart` | **New** |

## 3. State transitions implemented

| From | To | Actor | API |
|------|----|-------|-----|
| DRIVER_ASSIGNED | DRIVER_EN_ROUTE | Assigned driver | POST `/v1/rides/:id/en-route` |
| DRIVER_EN_ROUTE | DRIVER_ARRIVED | Assigned driver | POST `/v1/rides/:id/arrive` |
| DRIVER_ARRIVED | RIDE_STARTED | Assigned driver | POST `/v1/rides/:id/start` |
| RIDE_STARTED | RIDE_COMPLETED | Assigned driver | POST `/v1/rides/:id/complete` |
| ASSIGNED / EN_ROUTE / ARRIVED / STARTED | CANCELLED | Passenger or assigned driver | POST `/v1/rides/:id/cancel` |

Strict ordering enforced via `assertProgression`. No skip/backwards.

## 4. API contracts

Body (progression): `{}` or `{ "expectedVersion": n }` only.  
Header: `Idempotency-Key` required (8–200).  
Response: public ride including `startedAt` / `completedAt` when set.  
Errors: `FORBIDDEN`, `STATE_CONFLICT`, `VERSION_CONFLICT`, `VALIDATION_ERROR`, `IDEMPOTENCY_KEY_REUSED`, `RIDE_NOT_FOUND`.

Concurrency token post-assign: **`ride.version` / `expectedVersion`** (not `requestVersion`).

## 5. Authorization

- Progression: `caller.uid === ride.assignedDriverId` only  
- Post-assign cancel: passenger owner **or** assigned driver  
- Pre-assign cancel: passenger only (unchanged)  
- Identity never trusted from body  

## 6. Idempotency

Durable `idempotencyRecords` with requestHash + actorId; same-key replay; reuse → `IDEMPOTENCY_KEY_REUSED`. Already-at-target treated as success snapshot without second version bump/outbox.

## 7. Concurrency model

Per-ride Firestore transaction; one version increment per successful transition; cancel vs progression → one legal persisted state (`DRIVER_EN_ROUTE` or `CANCELLED`, etc.).

## 8. Transaction boundaries

Each mutation: read idempotency → read ride → auth + state assert → update ride → idempotency SUCCEEDED → outbox event.

## 9. Outbox events

| Transition | eventType |
|------------|-----------|
| EN_ROUTE | `ride.driver.en_route` |
| ARRIVED | `ride.driver.arrived` |
| START | `ride.started` |
| COMPLETE | `ride.completed` |
| CANCEL | `ride.cancelled` |

Atomic with mutation; no FCM/RTDB/Redis consumers.

## 10. Cancellation semantics

- `CANCELLED` + `cancelledBy` = `passenger` \| `driver`  
- `cancellationFeeMinor: 0` (fee policy deferred)  
- **Retain** `assignedDriverId` after post-assign cancel (audit)  
- Reject cancel after `RIDE_COMPLETED`  
- Idempotent replay if already `CANCELLED` for authorized actor  

**Note:** Concurrent select + cancel may yield CANCELLED with both HTTP 200 (select then post-assign cancel). Tests/harnesses updated accordingly — not a double-assignment.

## 11. Test matrix (executed)

| Suite | Command | Result |
|-------|---------|--------|
| Vitest rides + offer_lifecycle | `npx vitest run src/__tests__/offer_lifecycle.test.ts src/__tests__/rides.test.ts` | **58/58 PASS** |
| Ride proof (memoryDb) | `npm run test:ride-proof` | **17/17 PASS** |
| Live progression Firestore | `FIRESTORE_EMULATOR_HOST=127.0.0.1:8181 npm run test:ride-progression-firestore-concurrency` | **8/8 PASS** |
| Flutter progression entity | `flutter test test/features/ride/ride_progression_entity_test.dart` | **PASS** |
| Flutter analyze ride | `flutter analyze lib/features/ride` | **No issues** |

Live harness covered: happy path, 2/10-way en-route, 50-way complete, same-key concurrent, en-route vs cancel, driver cancel after start, skip/completed-cancel reject. Contention: `contendedTxns=64`, `FIRESTORE_CONTENTION_OBSERVED=yes`.

## 12. Live Firestore proof

**STATE: LIVE FIRESTORE PROGRESSION CONCURRENCY PROVEN**

Harness: `scripts/run_ride_progression_firestore_concurrency.ts`  
Environment: firebase-admin + real `runTransaction` + emulator `:8181` from `/tmp/ora-auth-nospace`.

## 13. Regression results

- Phase 2E ride-proof concurrency 2/10/50: PASS  
- Phase 2F vitest (embedded in rides suite): PASS  
- Select-vs-cancel expectations updated for legal post-assign cancel (documented)  

Flutter: `flutter analyze lib/features/ride` — **No issues**. Entity test import fixed to `package:ora/...`.

## 14. Bugs discovered / fixed

| Issue | Fix |
|-------|-----|
| Short Idempotency-Key in new tests (`g-en-1`) → 400 | Lengthened keys |
| Select-vs-cancel tests assumed cancel cannot follow assign | Updated to Phase 2G legal outcomes |

No production defect in assignment/idempotency core.

## 15. Known limitations

- No proximity/GPS validation (deferred)  
- No RTDB/FCM/Redis  
- No payment on complete  
- No `RIDE_CLOSED` / NO_SHOW / sweepers  
- No ride UI  

## 16. Explicit non-goals

Maps, GPS, RTDB, Redis, FCM, payments, `RIDE_CLOSED`, NO_SHOW, Cargo, Delivery, Admin, UI, navigation, ML matching.

## 17. Definition of Done

Met: transitions, cancel, auth, idempotency, outbox, Flutter data layer, unit tests, **live Firestore concurrency**, 2E/2F regression.

## 18. Final verdict

# PASS — PHASE 2G CLOSED

Phase 2H was **not** started.
