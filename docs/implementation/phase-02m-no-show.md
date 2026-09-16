# Phase 2M — NO_SHOW Ride Handling

**Status:** CLOSED  
**Date:** 2026-09-11  
**Decision freeze:** `docs/implementation/phase-02m-decision-freeze.md`  
**Architecture:** `docs/implementation/phase-02m-architecture-investigation.md`

---

## 1. Scope

Implemented **only** the frozen Phase 2M contract:

```text
DRIVER_ARRIVED → NO_SHOW
when rides/{rideId}.arrivedAt <= serverNow - 5 minutes (inclusive)
```

Server/worker-controlled, transactional, with atomic `ride.no_show` outbox. No payment/fee/ledger. No `drivers.noShowCount`. No public passenger/driver NO_SHOW endpoint. No new history filter. No offer mutations on NO_SHOW. No legacy `arrivedAt` backfill. No `NO_SHOW → RIDE_CLOSED`.

---

## 2. Files changed

| Path | Change |
|------|--------|
| `backend/auth-service/src/rides/types.ts` | `NO_SHOW` in `RIDE_STATES`; `RIDE_NO_SHOW_WAIT_MS = 5 * 60 * 1000` |
| `backend/auth-service/src/rides/state_machine.ts` | `NO_SHOW` in `TERMINAL` + `TERMINAL_FOR_OFFERS` |
| `backend/auth-service/src/rides/ride_service.ts` | `markNoShow` + `sweepNoShowRides` (batch 100/200, multi-pass ≤20) |
| `backend/auth-service/src/routes/internal.ts` | `POST /v1/internal/rides/no-show-sweep` (worker token) |
| `firestore.indexes.json` | Composite `rides`: `state ASC` + `arrivedAt ASC` |
| `docs/database/firestore-schema.md` | Index note for NO_SHOW sweeper |
| `backend/auth-service/scripts/run_phase_2m_unit_proof.ts` | Focused MemoryDb unit proof |
| `backend/auth-service/scripts/run_ride_no_show_firestore_concurrency.ts` | Live Firestore + concurrency harness |
| `backend/auth-service/package.json` | `test:phase-2m-unit-proof`, `test:ride-no-show-firestore-concurrency` |
| `package.json` (root) | Emulator wrapper for live NO_SHOW harness |
| `mobile/test/features/ride/ride_progression_entity_test.dart` | `Ride holds NO_SHOW state for Phase 2M` |
| `docs/implementation/phase-02m-no-show.md` | This closure doc |

Flutter domain `Ride.state` is already `String`; no entity/parser schema change required beyond the entity test.

---

## 3. State-machine changes

| Item | Detail |
|------|--------|
| New state | `NO_SHOW` only |
| Legal transition | `DRIVER_ARRIVED → NO_SHOW` (server/worker only) |
| Terminal | `NO_SHOW` ∈ `TERMINAL` — no start/complete/cancel/close |
| Offers | `NO_SHOW` ∈ `TERMINAL_FOR_OFFERS` — marketplace cannot reopen |
| Close | Unchanged: only `RIDE_COMPLETED → RIDE_CLOSED` |

---

## 4. Sweeper design

**Query:**

```text
rides
  .where('state', '==', 'DRIVER_ARRIVED')
  .where('arrivedAt', '<=', cutoffIso)   // cutoff = serverNow - 5m
  .limit(batchSize)                      // default 100, max 200
```

**Multi-pass:** up to 20 passes per HTTP call while a full batch is returned (2J/2K pattern).

**Per candidate:** `markNoShow` inside a Firestore transaction (re-check state, non-null `arrivedAt`, due clock).

---

## 5. Worker authentication

| Item | Detail |
|------|--------|
| Route | `POST /v1/internal/rides/no-show-sweep` |
| Middleware | Existing `createInternalWorkerMiddleware` |
| Header | `X-Ora-Worker-Token` |
| Secret | `ORA_INTERNAL_WORKER_TOKEN` (≥16 chars) |
| Public API | **None** — no passenger/driver NO_SHOW endpoint |

---

## 6. Transaction boundary

Inside `markNoShow` transaction:

1. Re-read ride  
2. If `NO_SHOW` → `already_no_show` (no version bump, no event)  
3. If not `DRIVER_ARRIVED` → skip  
4. If `arrivedAt == null` → skip (`missing_arrivedAt`) — no backfill / no `updatedAt` inference  
5. If `arrivedAt > cutoff` → skip (`not_due`)  
6. Else atomically: `state=NO_SHOW`, `version+1`, `updatedAt=now`, **preserve `arrivedAt`**, one `ride.no_show` outbox  

State + version + outbox = **one** Firestore transaction.

---

## 7. Version / idempotency

| Case | Result |
|------|--------|
| First successful NO_SHOW | version +1 exactly once |
| Already `NO_SHOW` | no-op; no second event |
| Duplicate worker / retry | converges to one transition + one event |
| No worker Idempotency-Key | state-based idempotency (2J/2K style) |

---

## 8. Event contract

**Type:** `ride.no_show`  
**Causation ID:** `no-show:{rideId}`  

**Payload (exact):**

```json
{
  "rideId": "<string>",
  "fromState": "DRIVER_ARRIVED",
  "toState": "NO_SHOW",
  "reason": "arrived_wait_ttl_elapsed",
  "arrivedAt": "<ISO string from ride.arrivedAt>"
}
```

Envelope fields (`eventId`, `occurredAt`, `aggregateVersion`, etc.) remain on the outbox document only — not duplicated in payload. No fee/payment/GPS/`noShowCount`/passengerId/assignedDriverId in payload.

---

## 9. History behavior

| Filter | NO_SHOW visible? |
|--------|------------------|
| `status=all` | **Yes** |
| `status=completed` (`RIDE_COMPLETED`, `RIDE_CLOSED`) | **No** |
| `status=cancelled` | **No** |

No new history collection or filter. `rides/{rideId}` remains source of truth.

---

## 10. Security

| Check | Result |
|-------|--------|
| Missing worker token | Rejected (`403` / unit proof) |
| Wrong worker token | Rejected |
| Normal user JWT cannot invoke sweeper | Rejected |
| Client cannot write ride state | Existing rules (Admin SDK only) |
| Passenger/driver cannot declare NO_SHOW | No public endpoint |
| Forged ride IDs | Transaction re-validates state/clock |

---

## 11. Unit test evidence

**Command (established esbuild workaround via `/tmp` copy — path-with-space):**

```text
esbuild scripts/run_phase_2m_unit_proof.ts --bundle --platform=node --format=cjs
node .tmp/phase_2m_unit_proof.cjs
```

**Result:** `Phase 2M unit proof: 10 passed, 0 failed` (`exit 0`)

Covered (aggregated cases): not-due &lt;5m; exact 5m boundary; older-than-5m + exact payload; legacy null `arrivedAt` skip; wrong state skip; already NO_SHOW no-op; cannot start/cancel; `noShowCount`/drivers unchanged; worker auth (missing/wrong/user); history under `all` only.

---

## 12. Live Firestore evidence

**Emulator:** `127.0.0.1:8181`  
**Command:**

```text
npx firebase-tools@13 emulators:exec --only firestore --project ora-app-d8112 \
  "node backend/auth-service/.tmp/ride_no_show_firestore_concurrency.cjs"
```

**Result:** `Phase 2M live proof: 10 passed, 0 failed` (`exit 0`)

| # | Case | Result |
|---|------|--------|
| 1 | Normal NO_SHOW | state=`NO_SHOW`; version +1; `arrivedAt` unchanged; exact payload from Admin SDK outbox read |
| 2 | Exact 5m boundary | Eligible → `NO_SHOW` |
| 3 | Not due (inside window) | Remains `DRIVER_ARRIVED`; zero events |
| 4 | Legacy null `arrivedAt` | Untouched; zero events |
| 5 | 2-way concurrency | One transition; one event; `contendedTxns+=2` |
| 6 | 10-way concurrency | Same invariant; `contendedTxns+=10` |
| 7 | NO_SHOW vs cancel | Exactly one legal winner + matching events |
| 8 | NO_SHOW vs start | No invalid coexistence |
| 9 | Duplicate worker retry | No second version bump; one event; `arrivedAt` unchanged |
| 10 | History | Under `all` only; not completed/cancelled |

Persisted documents inspected via Admin SDK (`rides` + `outbox`), not HTTP-body-only.

---

## 13. Concurrency evidence

From live harness contention notes:

```text
2-way: contendedTxns+=2
10-way: contendedTxns+=10
NO_SHOW vs cancel: NO_SHOW won (legal exclusive outcome)
NO_SHOW vs start: NO_SHOW won (legal exclusive outcome)
```

Firestore transaction is the correctness boundary; losers do not overwrite winners.

---

## 14. Regression evidence

| Phase | Harness | Result |
|-------|---------|--------|
| 2G progression | `ride_progression_firestore_concurrency.cjs` (rebuilt with `NO_SHOW`) | **8 passed, 0 failed** |
| 2H close | `ride_close_firestore_concurrency.cjs` | **7 passed, 0 failed** |
| 2I list | `ride_list_firestore_queries.cjs` | **7 passed, 0 failed** |
| 2J expire | `ride_expire_firestore_concurrency.cjs` | **10 passed, 0 failed** |
| 2K offer expire | `ride_offer_expire_firestore_concurrency.cjs` | **14 passed, 0 failed** |
| 2L arrivedAt | `ride_arrived_at_firestore_concurrency.cjs` | **6 passed, 0 failed** |

All via fresh `firebase-tools@13 emulators:exec --only firestore` sessions where required. Full CJS esbuild rebuilds used (one-at-a-time; concurrent esbuild can deadlock on this workspace path).

---

## 15. Flutter / static evidence

| Check | Command | Result |
|-------|---------|--------|
| Analyze | `cd mobile && dart analyze lib/features/ride` | **No issues found** (`ANALYZE:0`) |
| Ride tests | `cd mobile && flutter test test/features/ride` | **All tests passed!** **7/7** including `Ride holds NO_SHOW state for Phase 2M` (`FLUTTER:0`) |
| TypeScript `tsc --noEmit` | `./node_modules/.bin/tsc --noEmit -p tsconfig.json` | **Exit 2**. Failures are ambient `@types` resolution errors (`Cannot find type definition file for '… 2'`, e.g. `body-parser 2`, `express 2`) — same documented workspace/`typeRoots` issue as Phase 2L. **No ride-source diagnostics** in the error set. Modified ride sources were compiled/executed by esbuild unit + live proofs. |

---

## 16. Self-audit

| Check | Result |
|-------|--------|
| Production feature is NO_SHOW only | **Yes** |
| Payment / fee / ledger / PSP mutation on NO_SHOW | **Absent** |
| `drivers.noShowCount` write | **Absent** |
| GPS / Maps / Redis / RTDB / FCM / dispatch / go-online | **Absent** |
| Flutter UI | **Absent** |
| Historical backfill | **Absent** |
| Unrelated refactor | **Not introduced for 2M** |
| Transition `DRIVER_ARRIVED → NO_SHOW` only | **Yes** |
| Worker authenticated | **Yes** |
| Query bounded (100/200) | **Yes** |
| Index `state` + `arrivedAt` | **Yes** |
| Atomic state+version+outbox | **Yes** |
| Version +1 once; duplicate-safe | **Yes** (unit + live) |
| `arrivedAt` immutable on NO_SHOW | **Yes** |
| Legacy null clock skipped | **Yes** |

`markNoShow` update patch writes only `state`, `version`, `updatedAt` (+ outbox). Close path remains `RIDE_COMPLETED → RIDE_CLOSED` only.

---

## 17. Limitations

1. Pre-2L / null-clock `DRIVER_ARRIVED` rides are never auto-NO_SHOW’d (intentional; no backfill).  
2. `tsc --noEmit` exits 2 due to broken ambient `@types` names with trailing ` 2`; proof evidence relies on esbuild-executed harnesses.  
3. Full esbuild of large harnesses is slow; concurrent esbuilds can deadlock — rebuild serially.  
4. NO_SHOW does not auto-close; no financial / fee phase follows in 2M.

---

## 18. Explicit non-goals (confirmed not implemented)

- Payment / fee / ledger / PSP  
- `drivers.noShowCount` mutation  
- New history filter (`status=no_show`)  
- Public passenger/driver NO_SHOW API  
- Offer cleanup on NO_SHOW  
- `NO_SHOW → RIDE_CLOSED`  
- GPS / proximity / Maps  
- Redis / RTDB / FCM / dispatch / go-online  
- Ratings  
- Flutter UI  
- Historical `arrivedAt` backfill  

---

## 19. Final verdict

All required Phase 2M closure gates have **executed** evidence:

- Unit proof **10/10**  
- Live normal / boundary / not-due / legacy skip  
- Live 2-way + 10-way concurrency  
- Live NO_SHOW vs cancel + vs start  
- Duplicate worker/retry  
- Exact event payload + version from persisted Firestore  
- History under `all` only  
- Worker security unit coverage  
- Regressions **2G–2L** green  
- Flutter analyze + ride tests green  
- Self-audit: no scope leakage  

### PASS — PHASE 2M CLOSED
