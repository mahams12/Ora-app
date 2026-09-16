# Phase 2N — Ratings (Stars-Only)

**Status:** CLOSED  
**Date:** 2026-09-15  
**Decision freeze:** `docs/implementation/phase-02n-decision-freeze.md`  
**Architecture:** `docs/implementation/phase-02n-ratings-architecture-investigation.md`  
**Prerequisite:** Phase 2M CLOSED (untouched)

---

## 1. Scope

Implemented the frozen Phase 2N greenfield rating aggregate:

```text
POST /v1/rides/:rideId/ratings
GET  /v1/rides/:rideId/ratings
```

- Stars only (integer 1–5)
- Both directions (`passenger_rates_driver` / `driver_rates_passenger`)
- Eligible only when `state ∈ {RIDE_COMPLETED, RIDE_CLOSED}`
- Authoritative store: `ratings/{rideId}_{ratingType}`
- Ride document **read-only** during rating (no state/version/`updatedAt`/denorm)
- No user/driver aggregate updates
- Atomic `ride.rating.submitted` outbox
- Minimal Flutter domain/data (no UI)

---

## 2. Files changed

| Path | Change |
|------|--------|
| `backend/auth-service/src/rides/types.ts` | `RatingType`, `RatingDoc` |
| `backend/auth-service/src/rides/ride_service.ts` | `submitRating`, `getMyRating`; direction/eligibility helpers |
| `backend/auth-service/src/rides/routes.ts` | POST/GET `/:rideId/ratings` |
| `docs/architecture-review/event-contracts.md` | `ride.rating.submitted` |
| `docs/api/error-codes.md` | `ALREADY_RATED`, `RATING_NOT_FOUND` |
| `backend/auth-service/scripts/run_phase_2n_unit_proof.ts` | MemoryDb unit proof |
| `backend/auth-service/scripts/run_ride_rating_firestore_concurrency.ts` | Live Firestore proof |
| `backend/auth-service/package.json` | npm scripts |
| `package.json` (root) | Emulator wrapper |
| `mobile/lib/features/ride/domain/entities/ride.dart` | `RideRating` |
| `mobile/lib/features/ride/.../ride_repository.dart` (+ impl, DS, use cases) | submit/get |
| `mobile/test/features/ride/*` | Entity + fake repo stubs |
| `docs/implementation/phase-02n-ratings.md` | This closure |

**Unchanged:** `firestore.rules` (`ratings` remain deny-all), ride state machine, Phase 2M, indexes (none added).

---

## 3. API contract

### POST `/v1/rides/:rideId/ratings`

- Auth: Firebase JWT  
- Header: `Idempotency-Key` (required)  
- Body: `{ "stars": 1|2|3|4|5 }` only  
- Server derives: `raterId`, `ratedId`, `ratingType`  
- Success: `201` + rating DTO  

### GET `/v1/rides/:rideId/ratings`

- Auth: participant only  
- Returns **caller’s own** rating (`200`)  
- No own rating: `404 RATING_NOT_FOUND`  
- Counterpart never returned  

---

## 4. Firestore schema

```text
ratings/{rideId}_{ratingType}
```

Fields: `rideId`, `raterId`, `ratedId`, `ratingType`, `stars`, `createdAt` (ISO string).

Examples:

```text
ratings/{rideId}_passenger_rates_driver
ratings/{rideId}_driver_rates_passenger
```

---

## 5. Authorization

Participant check mirrors close/getRide: `uid ∈ {passengerId, assignedDriverId}`.

| Caller | `ratingType` | `ratedId` |
|--------|--------------|-----------|
| Passenger | `passenger_rates_driver` | `assignedDriverId` |
| Assigned driver | `driver_rates_passenger` | `passengerId` |

Missing `assignedDriverId` → `409 STATE_CONFLICT`. Non-participant → `403 FORBIDDEN`.

---

## 6. Idempotency

Existing `idempotencyRecords` machinery.

Hash input: `{ operation: 'RIDE_RATING_SUBMIT', rideId, ratingType, stars }` + actor binding.

| Case | Result |
|------|--------|
| Same key + same body | Replay `201` |
| Same key + different body | `IDEMPOTENCY_KEY_REUSED` |
| Different key after exists | `ALREADY_RATED` |

Natural doc ID is the uniqueness boundary (no overwrite).

---

## 7. Transaction boundary

Single Firestore transaction:

1. Idempotency record check/create  
2. Re-read ride (eligibility + direction)  
3. Assert rating doc absent  
4. Create rating  
5. Write outbox  
6. Persist idempotency success  

**Ride is never written.**

---

## 8. Concurrency behavior

| Scenario | Result |
|----------|--------|
| Same-user 2-way / 10-way | One rating doc; one outbox event; others `ALREADY_RATED` |
| Both participants concurrent | Two independent docs |
| Rating ∥ close | Both succeed when legal; no cross-corruption |

---

## 9. Outbox event

**Type:** `ride.rating.submitted`  
**Causation ID:** Idempotency-Key  

**Outbox aggregate choice (documented):** because ride `version` must not change:

```text
aggregateType: "rating"
aggregateId:   "{rideId}_{ratingType}"
aggregateVersion: 1
```

**Payload (exact):**

```json
{
  "rideId": "<string>",
  "ratingId": "<string>",
  "ratingType": "passenger_rates_driver | driver_rates_passenger",
  "raterId": "<uid>",
  "ratedId": "<uid>",
  "stars": 1
}
```

---

## 10. GET behavior

Participant-scoped; own rating only; `RATING_NOT_FOUND` when absent; no list/history filter changes.

---

## 11. Unit test results

**Command:** esbuild bundle of `run_phase_2n_unit_proof.ts` via `/tmp` copy workaround → `node .tmp/phase_2n_unit_proof.cjs`

**Result:** `Phase 2N unit proof: 8 passed, 0 failed` (`UNIT_EXIT:0`)

Covered: both directions on COMPLETED/CLOSED; state rejections; non-participant; missing driver; invalid/forged body; idempotency; GET visibility; ride/aggregates unchanged; exact event payload.

---

## 12. Live Firestore results

**Emulator:** `127.0.0.1:8181`  
**Command:** `firebase-tools@13 emulators:exec … node …/ride_rating_firestore_concurrency.cjs`

**Result:** `Phase 2N live proof: 10 passed, 0 failed` (`LIVE_EXIT:0`)

Persisted Admin SDK verification: exact doc IDs/fields, exact outbox payload, ride state/version/`updatedAt` unchanged, no aggregate mutation, 2-way (`contendedTxns+=1`) and 10-way (`contendedTxns+=9`), both participants, rating vs close, NO_SHOW/CANCELLED/EXPIRED rejection, GET visibility.

---

## 13. Regression results 2E–2M

| Phase | Result |
|-------|--------|
| 2E `ride_proof` | **17 passed, 0 failed** |
| 2F offer create | **8 passed, 0 failed** |
| 2G progression | **8 passed, 0 failed** |
| 2H close | **7 passed, 0 failed** |
| 2I list | **7 passed, 0 failed** |
| 2J expire | **10 passed, 0 failed** |
| 2K offer expire | **14 passed, 0 failed** |
| 2L arrivedAt | **6 passed, 0 failed** |
| 2M NO_SHOW | **10 passed, 0 failed** |

All via fresh `emulators:exec` sessions (`ALL_REG_DONE:0`).

---

## 14. Flutter results

| Check | Result |
|-------|--------|
| `dart analyze lib/features/ride` | **No issues found** (`ANALYZE:0`) |
| `flutter test test/features/ride` | **All tests passed!** **8/8** including `RideRating holds Phase 2N stars-only fields` (`FLUTTER:0`) |

No UI.

---

## 15. Static check results

| Check | Result |
|-------|--------|
| esbuild of `src/rides/ride_service.ts` | **ESBUILD_RIDE:0** |
| Unit + live proofs (esbuild CJS) | Compile + execute successfully |
| `./node_modules/.bin/tsc --noEmit -p tsconfig.json` | **Did not complete cleanly** within 90s wall (`TSC_EXIT:142` / SIGALRM hang, empty diagnostics). Same workspace ambient `@types … 2` failure mode documented in Phases 2L/2M when tsc finishes. **Not claimed clean.** Ride sources independently compiled/executed by focused proofs. |

---

## 16. Security verification

| Check | Result |
|-------|--------|
| `firestore.rules` `ratings` deny-all | **Unchanged** |
| Client cannot supply rater/rated/type | `rejectUnknownKeys` + server derive |
| Non-participant rejected | Unit + live |
| NO_SHOW / CANCELLED / EXPIRED rejected | Unit + live |
| Backend Admin SDK only | Yes |

---

## 17. Self-audit

| Check | Result |
|-------|--------|
| Payment / fees / ledger / wallet / tips | **Absent** |
| Aggregates / ranking / reputation | **Absent** |
| Tags / comments / edit / delete API | **Absent** |
| Counterpart / public exposure | **Absent** |
| Maps / GPS / Redis / RTDB / FCM / dispatch | **Absent** |
| Ride SM / close / NO_SHOW / history filters | **Unchanged** |
| Ride write in rating txn | **None** (only rating + idem + outbox) |
| Speculative indexes | **None** |
| Phase 2M | **Untouched** |

---

## 18. Limitations

1. No user/driver running averages yet (deferred by freeze).  
2. No ride denorm fields.  
3. GET does not show counterpart rating.  
4. `tsc --noEmit` workspace hang/ambient issue remains; evidence relies on esbuild-executed proofs.  
5. Full harness esbuild remains slow on path-with-space workspace.

---

## 19. Explicit non-goals (confirmed not implemented)

Payments, fees, tips, wallet, ledger, earnings, payout, `noShowCount`, averages, `ratingCount`, reputation, matching/ranking, moderation, reporting, comments, tags, editable ratings, public history, counterpart visibility, Maps, GPS, dispatch, FCM, Redis, RTDB, ride state changes, UI.

---

## 20. Final verdict

All required Phase 2N gates have **executed** evidence:

- Unit **8/8**  
- Live Firestore **10/10** (persisted docs + outbox + concurrency)  
- Regressions **2E–2M** green  
- Flutter analyze + ride tests green  
- Rules deny-all preserved  
- Self-audit clean  

### PASS — PHASE 2N CLOSED
