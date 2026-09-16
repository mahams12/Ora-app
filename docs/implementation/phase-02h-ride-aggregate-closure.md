# Phase 2H — Ride Aggregate Closure

**Status:** CLOSED  
**Date:** 2026-09-09  
**Architecture:** `docs/implementation/phase-02h-architecture-investigation.md`

---

## 1. Scope

Implemented:

`RIDE_COMPLETED → RIDE_CLOSED` via `POST /v1/rides/:rideId/close`

with server `closedAt`, durable idempotency, Firestore transactions, single version increment, atomic `ride.closed` outbox, passenger-owner or assigned-driver auth, Flutter domain/data only.

## 2. Architecture basis

Locked SM + ADR-008 + Case 28: close is ride-aggregate terminal and may precede payment. No payment coupling introduced.

## 3. Files changed

| File | Change |
|------|--------|
| `backend/auth-service/src/rides/types.ts` | `RIDE_CLOSED` state |
| `backend/auth-service/src/rides/state_machine.ts` | `assertCloseable`; TERMINAL = CANCELLED/EXPIRED/`RIDE_CLOSED` |
| `backend/auth-service/src/rides/ride_service.ts` | `closeRide`; `publicRide.closedAt` |
| `backend/auth-service/src/rides/routes.ts` | `POST /:rideId/close` + structured log |
| `backend/auth-service/src/__tests__/rides.test.ts` | Phase 2H matrix |
| `backend/auth-service/scripts/run_ride_close_firestore_concurrency.ts` | **New** live harness |
| `backend/auth-service/package.json` / root `package.json` | `test:ride-close-firestore-concurrency` |
| `docs/architecture-review/event-contracts.md` | `ride.closed` listed |
| `mobile/lib/features/ride/**` | `closedAt`, `CloseRideUseCase`, repo/datasource |
| `mobile/test/features/ride/ride_progression_entity_test.dart` | CLOSED entity coverage |

## 4. State-machine changes

- Added `RIDE_CLOSED`
- Only legal close from `RIDE_COMPLETED`
- Aggregate terminals: `CANCELLED`, `EXPIRED`, `RIDE_CLOSED`
- `RIDE_COMPLETED` allows **only** close (not cancel/progress)

## 5. API contract

`POST /v1/rides/:rideId/close`  
Headers: auth + `Idempotency-Key`  
Body: `{}` \| `{ expectedVersion }`  
Success: 200, `state=RIDE_CLOSED`, `closedAt`, version+1  

## 6. Authorization

`uid === passengerId || uid === assignedDriverId` from token only.

## 7. Data model

Existing `rides/{id}`: set `state`, `closedAt`, `version`, `updatedAt`. No new collections. Fare/assignee unchanged.

## 8. Idempotency

Durable records; same-key replay; reuse → `IDEMPOTENCY_KEY_REUSED`; already CLOSED + new key → success snapshot, no second bump/event.

## 9. Versioning

Real close: +1 once. Replay: unchanged.

## 10. Transaction boundaries

Single `runTransaction`: idempotency → ride → auth → state → version → closedAt → idempotency SUCCEEDED → outbox.

## 11. Outbox event

`ride.closed` with `fromState`, `toState`, `actorId`, `actorType`, `aggregateVersion`, correlation/causation.

## 12. CLOSED immutability

Cancel / en-route / arrive / start / complete / second mutating close rejected (`STATE_CONFLICT` or already-CLOSED snapshot without mutation).

## 13. Flutter changes

Parse `closedAt` / `RIDE_CLOSED`; `CloseRideUseCase` + repository/datasource. No UI.

## 14. Test matrix (executed)

| Suite | Command | Result |
|-------|---------|--------|
| Vitest rides + offer_lifecycle | `npx vitest run … --testTimeout=120000` | **66/66 PASS** |
| Ride proof | `npm run test:ride-proof` | **17/17 PASS** |
| Live close Firestore | `FIRESTORE_EMULATOR_HOST=127.0.0.1:8181 npm run test:ride-close-firestore-concurrency` | **7/7 PASS** |
| Live progression (2G regression) | `npm run test:ride-progression-firestore-concurrency` | **8/8 PASS** |
| Flutter entity | `flutter test test/features/ride/ride_progression_entity_test.dart` | **PASS** |
| Flutter analyze | `flutter analyze lib/features/ride` | **No issues** |

## 15. Live Firestore proof

**STATE: LIVE FIRESTORE CLOSE CONCURRENCY PROVEN**

Harness: `scripts/run_ride_close_firestore_concurrency.ts`

Cases: happy path; 2/10/50-way close (mixed actors on 50); same-key concurrent; different keys no second mutation; reject close from STARTED.

## 16. Contention evidence

```
txnStarts=116 fnInvocations=175 contendedTxns=59
10-way contendedTxns+=9
50-way contendedTxns+=49
FIRESTORE_CONTENTION_OBSERVED=yes
```

## 17. Regression results

- 2E ride-proof 2/10/50 assignment: PASS  
- 2F embedded in vitest: PASS  
- 2G live progression: PASS  

Note: one Vitest run hit default 60s timeout on legacy 50-way select under suite load; re-run with `--testTimeout=120000` → **66/66 PASS** (no production defect).

## 18. Bugs found/fixed

| Issue | Fix |
|-------|-----|
| Short Idempotency-Key in foreign-actor test (`h-for-p`) → 400 | Lengthened keys |

## 19. Observability

`ride_close_failed` logs: requestId, operation=`RIDE_CLOSE`, rideId, errorType, code.

## 20. Known limitations

No payments, history list, ratings, Maps/GPS, RTDB, Redis, FCM, NO_SHOW sweepers, UI.

## 21. Explicit non-goals

As listed in HARD SCOPE — none implemented.

## 22. Definition of Done

Met: close transition, auth, idempotency, versioning, immutability, outbox, Flutter data, unit tests, **live Firestore concurrency**, 2E/2F/2G regression.

## 23. Final classification

# PASS — PHASE 2H CLOSED

Phase 2I was **not** started.
