# Phase 2L — Durable `arrivedAt` Wait-Clock Persistence

**Status:** CLOSED  
**Date:** 2026-09-10  
**Architecture:** `docs/implementation/phase-02l-architecture-investigation.md`

---

## 1. Scope

Implemented **only** the approved Phase 2L boundary:

```text
On authorized DRIVER_EN_ROUTE → DRIVER_ARRIVED (existing arrive path):
  atomically persist rides/{rideId}.arrivedAt = server ISO timestamp
  set exactly once; never overwrite thereafter
```

No new ride state. No NO_SHOW. No sweeper. No `ride.no_show`. No fees/payments/ledger. No ratings. No history status mapping changes. No GPS/proximity. No Redis/RTDB/FCM/dispatch. No active-assignment guard expansion. No Flutter UI. No historical ARRIVED backfill. No `state + arrivedAt` index.

---

## 2. Files changed

| Path | Change |
|------|--------|
| `backend/auth-service/src/rides/types.ts` | `RideDoc.arrivedAt: string \| null` |
| `backend/auth-service/src/rides/ride_service.ts` | Create `arrivedAt: null`; `publicRide` exposes field; `markArrived` → `setArrivedAt: true`; `progressAssignedRide` sets once in same txn |
| `docs/database/firestore-schema.md` | Document `arrivedAt` on rides |
| `mobile/lib/features/ride/domain/entities/ride.dart` | Optional `arrivedAt` for DTO/domain parity |
| `mobile/lib/features/ride/data/data_sources/ride_remote_data_source.dart` | Parse `arrivedAt` |
| `mobile/test/features/ride/ride_progression_entity_test.dart` | Phase 2L entity test |
| `backend/auth-service/scripts/run_phase_2l_unit_proof.ts` | Focused MemoryDb unit proof |
| `backend/auth-service/scripts/run_ride_arrived_at_firestore_concurrency.ts` | Live Firestore persistence + concurrency proof |
| `backend/auth-service/package.json` | `test:phase-2l-unit-proof`, `test:ride-arrived-at-firestore-concurrency` |
| `package.json` (root) | Wrapper for live arrivedAt harness |
| `docs/implementation/phase-02l-arrived-at-wait-clock.md` | This closure doc |

---

## 3. Exact behavior

On first legal arrive transition inside the existing progression transaction:

1. Re-read ride  
2. Verify assigned-driver authorization (unchanged)  
3. Verify `DRIVER_EN_ROUTE → DRIVER_ARRIVED`  
4. Bump `version` by 1  
5. Set `state = DRIVER_ARRIVED`, `updatedAt = nowIso`  
6. If `arrivedAt == null`, set `arrivedAt = nowIso` (server clock; not client; not `updatedAt`)  
7. Emit existing outbox `ride.driver.arrived` once  
8. Commit atomically  

Idempotent already-`DRIVER_ARRIVED` / Idempotency-Key replay: return current snapshot **without** changing `arrivedAt` or bumping version again.

Later lifecycle ops (`start`, `complete`, `close`, `cancel`) do **not** write `arrivedAt`.

Representation: ISO-8601 string, consistent with `startedAt` / `completedAt` / `closedAt`. Pre-arrive: `null` (written at create).

---

## 4. Transaction boundary

`arrivedAt` is set **only** inside existing `progressAssignedRide` Firestore transaction used by `markArrived`. No separate transaction for the wait-clock field.

---

## 5. Idempotency behavior

| Case | Result |
|------|--------|
| First arrive | `DRIVER_ARRIVED`, version +1, `arrivedAt` set |
| Same Idempotency-Key replay | Same snapshot / same `arrivedAt`; no second version bump; one outbox event |
| Already-arrived retry (new key) | Success path; `arrivedAt` unchanged; no version bump |
| Same key + different body | `IDEMPOTENCY_KEY_REUSED` (unchanged) |
| Same key + different actor | Actor protection unchanged (`IDEMPOTENCY_KEY_REUSED` / forbidden) |

---

## 6. Security

- Assigned driver can arrive; passenger / unrelated driver rejected (`FORBIDDEN`)  
- Token UID remains authoritative  
- No new public endpoint  
- Clients cannot write `arrivedAt`: `firestore.rules` `match /rides/{id} { allow read, write: if false; }`  
- No client-supplied timestamp accepted on arrive body for the wait clock  

---

## 7. Unit test evidence

**Command:**

```bash
cd backend/auth-service && node --import tsx scripts/run_phase_2l_unit_proof.ts
```

**Result:** `Phase 2L unit proof: 12 passed, 0 failed`

| # | Case covered |
|---|--------------|
| 1–3 | EN_ROUTE null clock; EN_ROUTE→ARRIVED sets ISO `arrivedAt` + version +1 |
| 4–5 | Idempotent replay + already-arrived retry do not overwrite / re-bump |
| 6 | Cancel from EN_ROUTE leaves `arrivedAt` null |
| 7 | Cancel after ARRIVED preserves `arrivedAt` |
| 8 | Start/complete/close preserve `arrivedAt` |
| 9–10 | Passenger / unrelated driver arrive forbidden |
| 11 | Stale `expectedVersion` → `VERSION_CONFLICT` |
| 12–13 | Same key/different body; same key/different actor rejected |

---

## 8. Live Firestore evidence

**Emulator:** `127.0.0.1:8181`  
**Command:**

```bash
cd "/Users/jazimsaeed/Desktop/Ora App"
npx --yes firebase-tools@13 emulators:exec --only firestore --project ora-app-d8112 \
  "node backend/auth-service/.tmp/ride_arrived_at_firestore_concurrency.cjs"
```

**Result:** `Phase 2L live proof: 6 passed, 0 failed`  
Persisted documents inspected via Admin SDK `rides/{id}.get()` (not HTTP-only).

| Test | Verified |
|------|----------|
| Normal arrive | `DRIVER_ARRIVED`; ISO `arrivedAt`; version +1; DTO matches store |
| Concurrency 2-way | One version increment; one durable `arrivedAt`; one outbox event; **`contendedTxns+=1`** |
| Concurrency 10-way | Same single transition/clock; **`contendedTxns+=10`** |
| Arrive vs cancel | Legal outcome observed: **CANCEL from EN_ROUTE (no clock)**; arrive got `STATE_CONFLICT`. Harness also accepts ARRIVED-exclusive and ARRIVED-then-CANCEL (clock preserved) because cancel remains legal post-ARRIVED |
| Idempotency replay | Same stored `arrivedAt`; version +1 once; one outbox event |
| Lifecycle | ARRIVED→STARTED→COMPLETED→CLOSED preserves identical `arrivedAt` |

**Contention evidence:** present (`FIRESTORE` txn updateFunction re-invocations counted).

---

## 9. Regression evidence

Each suite run under a fresh `firebase emulators:exec --only firestore` against **rebuilt full bundles that include `setArrivedAt` / `arrivedAt`**.

| Phase | Command (script body) | Result |
|-------|----------------------|--------|
| 2G progression | `node …/ride_progression_firestore_concurrency.cjs` | **passed=8 failed=0** |
| 2H close | `node …/ride_close_firestore_concurrency.cjs` | **passed=7 failed=0** |
| 2I list/query | `node …/ride_list_firestore_queries.cjs` | **7 passed, 0 failed** |
| 2J ride expire | `node …/ride_expire_firestore_concurrency.cjs` | **passed=10 failed=0** |
| 2K offer expire | `node …/ride_offer_expire_firestore_concurrency.cjs` | **14 passed, 0 failed** |

---

## 10. Flutter / static evidence

| Check | Command | Result |
|-------|---------|--------|
| Analyze | `cd mobile && dart analyze lib/features/ride` | **No issues found** (`ANALYZE_EXIT:0`) |
| Ride tests | `cd mobile && flutter test test/features/ride` | **All tests passed!** (+6) including `Ride holds arrivedAt for Phase 2L` (`FLUTTER_TEST_EXIT:0`) |
| TypeScript `tsc --noEmit` | `./node_modules/.bin/tsc --noEmit -p tsconfig.json` | **Completed with `TSC_EXIT:2`**. Errors are ambient `@types` resolution failures (`Cannot find type definition file for '… 2'`, e.g. `body-parser 2`, `express 2`) — workspace/path/`typeRoots` environment issue, not Phase 2L ride-source diagnostics. Unit + live harnesses compile/run against the modified sources. |

---

## 11. Self-audit

| Check | Result |
|-------|--------|
| Diff limited to wait-clock + proofs/docs/parity | Yes |
| `NO_SHOW` in `RIDE_STATES` / state_machine | **Absent** |
| `ride.no_show` outbox | **Absent** |
| Payment / ledger / ratings / GPS added | **No** |
| New worker / sweeper / public endpoint | **No** |
| `state + arrivedAt` index | **Not added** |
| Client write path for `arrivedAt` | **Denied by rules**; only Admin SDK server path |
| Overwrite protection | `if (setArrivedAt && ride.arrivedAt == null)` only |
| Arrive still inside existing progression txn | **Yes** (`markArrived` → `progressAssignedRide`) |

Repo search under `backend/auth-service/src/rides`: no `NO_SHOW` / `no_show`.

---

## 12. Limitations

1. Pre-2L rides that reached ARRIVED without `arrivedAt` remain null (no backfill — intentional).  
2. `tsc --noEmit` exits 2 due to broken ambient `@types` names with a trailing ` 2` (path/workspace tooling issue); not Phase 2L source errors. Evidence relies on esbuild/tsx execution of proofs.  
3. Full esbuild bundles of large harnesses are slow / can deadlock when multiple esbuild processes run; `/tmp` copy path used for some rebuilds.  
4. Arrive-vs-cancel exclusive `DRIVER_ARRIVED` final state is rare because passenger cancel remains legal after ARRIVED; observed legal outcome was cancel-from-EN_ROUTE with null clock.  

---

## 13. Explicit non-goals (confirmed not implemented)

- `NO_SHOW` state  
- NO_SHOW sweeper / worker  
- `ride.no_show`  
- Fees / payments / ledger  
- Ratings / `noShowCount`  
- History status mapping changes  
- GPS / proximity  
- Redis / RTDB / FCM / dispatch / go-online  
- Active-assignment guard expansion  
- Flutter UI  
- Historical backfill  
- `state + arrivedAt` composite index  

---

## 14. Final verdict

All required Phase 2L closure gates have **executed** evidence:

- Scope-matched implementation  
- Focused unit proof **12/12**  
- Live Firestore persistence proof **6/6** (documents inspected)  
- Live concurrency proof with contention counters  
- Arrive-vs-cancel race proof (legal outcome)  
- Idempotency replay + lifecycle preservation live  
- 2G / 2H / 2I / 2J / 2K regressions all green  
- Flutter analyze + focused ride tests green  
- Self-audit: no scope leakage  

### PASS — PHASE 2L CLOSED
