# Phase 2J — Ride EXPIRED Sweeper / Terminal Write-Path

**Status:** CLOSED  
**Date:** 2026-09-10  
**Architecture:** `docs/implementation/phase-02j-architecture-investigation.md`

---

## 1. Scope

Implemented **only** the approved Phase 2J boundary:

```text
SEARCHING | OFFERS_AVAILABLE → EXPIRED
when rides/{rideId}.expiresAt <= server now
```

Server-authoritative, transactional, with atomic `ride.expired` outbox. Internal worker invocation only.

**Not in scope:** durable offer TTL subsystem, `ride.offer.expired`, NO_SHOW, ratings, payments, Maps, Redis, RTDB, FCM, dispatch, Flutter UI.

---

## 2. Architecture

| Component | Role |
|-----------|------|
| `RideService.expireRide` | Single-ride transactional expiry; idempotent when already `EXPIRED` |
| `RideService.sweepExpiredRides` | Bounded query + per-candidate `expireRide` |
| `POST /v1/internal/rides/expire-sweep` | Service-authenticated worker entry (not passenger/driver JWT) |
| `createInternalWorkerMiddleware` | Validates `X-Ora-Worker-Token` against `ORA_INTERNAL_WORKER_TOKEN` |
| `assertExpirable` / `EXPIRABLE` | State gate: `SEARCHING`, `OFFERS_AVAILABLE` only |

### Invariant

A ride transitions to `EXPIRED` only when:

```text
current state ∈ {SEARCHING, OFFERS_AVAILABLE}
AND expiresAt <= server now
```

Inside `runTransaction`, the ride is re-read and both predicates are re-checked before mutation.

---

## 3. Query and index

**Sweeper query:**

```text
rides
  .where('state', 'in', ['SEARCHING', 'OFFERS_AVAILABLE'])
  .where('expiresAt', '<=', nowIso)
  .limit(batchSize)   // default 100, max 200
```

**Index added** (`firestore.indexes.json`):

```json
{ "fieldPath": "state", "order": "ASCENDING" },
{ "fieldPath": "expiresAt", "order": "ASCENDING" }
```

Live emulator proof: sweeper query returns due rides and completes expiry (`PASS sweeper query index SEARCHING due ride live`).

---

## 4. Transaction semantics

Per candidate, `expireRide`:

1. Re-read ride in transaction
2. If `state === 'EXPIRED'` → return `already_expired` (no version bump, no outbox)
3. If state ∉ expirable → return `skipped` (no mutation)
4. If `expiresAt > now` → return `skipped` (`not_due`)
5. Else atomically:
   - `state: EXPIRED`
   - `version: version + 1` (exactly once)
   - `updatedAt: nowIso`
   - outbox `ride.expired` with payload `{ rideId, fromState, toState, reason: search_ttl_elapsed, expiresAt }`

No idempotency record for worker path — transaction idempotency via already-`EXPIRED` short-circuit mirrors Phase 2H `RIDE_CLOSED` handling.

---

## 5. Race semantics

| Race | Outcome |
|------|---------|
| Expire vs select | One wins: `DRIVER_ASSIGNED` or `EXPIRED`; loser gets `STATE_CONFLICT` / skip |
| Expire vs cancel | One terminal: `CANCELLED` or `EXPIRED` |
| Expire vs offer create (after expiry) | `STATE_CONFLICT` on offer create |
| Multiple sweepers / retries | Exactly one transition, one version bump, one `ride.expired` event |
| Assigned / terminal ride in query stale set | Skipped in transaction — never overwritten |

Assigned rides are excluded from the sweeper query (`state` filter). Stale query rows in pre-assignment states are guarded again inside the transaction.

---

## 6. Outbox

Event: **`ride.expired`** (contracted name, ADR-005 pattern).

Envelope fields match existing outbox conventions: `eventId`, `eventType`, `aggregateType`, `aggregateId`, `aggregateVersion`, `schemaVersion`, `occurredAt`, `correlationId`, `causationId`, `publishState`, `attemptCount`, `nextAttemptAt`.

---

## 7. Worker invocation

```
POST /v1/internal/rides/expire-sweep
X-Ora-Worker-Token: <ORA_INTERNAL_WORKER_TOKEN>
Query: limit? (1–200)
```

Response:

```json
{
  "data": {
    "scanned": 0,
    "expired": 0,
    "alreadyExpired": 0,
    "skipped": 0,
    "failed": 0
  }
}
```

- Not mounted on Firebase JWT auth path
- No user-controlled `rideId` expiry endpoint
- Safe for repeated scheduled invocation
- One failed ride increments `failed` only; others continue

Production wiring: Cloud Scheduler → internal Cloud Run job hitting this route with service token.

---

## 8. Security

- `403` without valid `X-Ora-Worker-Token`
- `503` if `ORA_INTERNAL_WORKER_TOKEN` not configured (< 16 chars)
- Passenger/driver tokens cannot invoke `/v1/internal/*`

---

## 9. Failure / retry behavior

| Case | Behavior |
|------|----------|
| Transaction contention | Firestore retries; already-committed state observed on retry |
| Stale query candidate | Re-check in txn → skip or succeed once |
| Already `EXPIRED` | `already_expired`, no duplicate event |
| Assigned / cancelled / terminal | `skipped`, no overwrite |
| Malformed / missing expiry | `skipped` (`not_due`) |
| Per-ride exception in sweep | `failed++`, batch continues |

---

## 10. Observability

Structured logs:

- Sweep: `RIDE_EXPIRE_SWEEP` with `scanned`, `expired`, `alreadyExpired`, `skipped`, `failed`, `durationMs`, `requestId`
- Existing ride mutation failure logs unchanged for select/cancel/offer paths

---

## 11. Files changed

| File | Change |
|------|--------|
| `backend/auth-service/src/rides/state_machine.ts` | `EXPIRABLE`, `assertExpirable`, `isExpirable` |
| `backend/auth-service/src/rides/ride_service.ts` | `expireRide`, `sweepExpiredRides` |
| `backend/auth-service/src/middleware/internal_worker.ts` | **New** worker auth |
| `backend/auth-service/src/routes/internal.ts` | **New** expire-sweep route |
| `backend/auth-service/src/app.ts` | Mount `/v1/internal` with worker middleware |
| `backend/auth-service/src/__tests__/helpers/memory_db.ts` | `<=` / `>=` query filters |
| `backend/auth-service/src/__tests__/rides.test.ts` | Phase 2J Vitest matrix |
| `backend/auth-service/scripts/run_phase_2j_unit_proof.ts` | **New** standalone unit proof |
| `backend/auth-service/scripts/run_ride_expire_firestore_concurrency.ts` | **New** live emulator harness |
| `backend/auth-service/package.json` | `test:phase-2j-unit-proof`, `test:ride-expire-firestore-concurrency` |
| `firestore.indexes.json` | `state + expiresAt` composite |

---

## 12. Tests

### Vitest (`rides.test.ts` — Phase 2J describe)

Positive: SEARCHING/OFFERS_AVAILABLE expiry, future TTL unchanged  
Negative: assigned, cancelled, offer-after-expire  
Concurrency: expire vs select, expire vs cancel  
Retry: duplicate worker / already EXPIRED  
Batch: mixed due + assigned (assigned excluded by query; due still expires)  
Worker auth gate

**Result:** **12/12 passed** (`vitest -t "Phase 2J"`, single-thread pool).

> Assigned rides are not sweeper query candidates (`state` filter), so `skipped` stays 0 for those cases — tests assert document immutability instead of a skip counter.

### Standalone unit proof

`npm run test:phase-2j-unit-proof` → **4/4 passed**

### Live Firestore harness

`npm run test:ride-expire-firestore-concurrency` (via `firebase emulators:exec`) → **10/10 passed**

Evidence:

- Normal SEARCHING expiry + document fields + one outbox event
- OFFERS_AVAILABLE expiry
- Non-expired unchanged
- 2-way and 10-way concurrent expiry → one version bump, one event
- Expire vs select, expire vs cancel
- Offer create after expire rejected
- Retry after success idempotent
- Assigned ride not overwritten
- `FIRESTORE_CONTENTION_OBSERVED=yes` (multi-attempt transactions recorded)

---

## 13. Regression evidence

| Suite | Result |
|-------|--------|
| Phase 2E `ride-proof` | **17/17** |
| Phase 2F offer live | **8/8** |
| Phase 2G progression live | **8/8** |
| Phase 2H close live | **7/7** |
| Phase 2I list live | **7/7** |
| Flutter analyze `lib/features/ride` | clean |
| Flutter ride tests | **5/5** |

All re-run 2026-09-10 in single `firebase emulators:exec` session after Phase 2J merge.

---

## 14. Self-audit

| Question | Answer |
|----------|--------|
| Closed-phase contract changed? | No — only added internal worker + expiry write path |
| Expired ride resurrected? | No — terminal immutability preserved |
| Assigned/terminal overwritten? | No — txn skip + query excludes post-assign states |
| Concurrent sweepers double version bump? | No — live 2/10-way proof |
| Duplicate `ride.expired` events? | No — already-EXPIRED short-circuit |
| New offer after expiry? | Rejected (`STATE_CONFLICT`) |
| Sweeper publicly abusable? | No — worker token required |
| Query bounded? | Yes — default 100, max 200 |
| Index required? | Yes — `state + expiresAt`; emulator-proven |
| Second source of truth? | No — `rides/{rideId}` only |
| Scope leak? | No |

---

## 15. Known limitations

1. **No Cloud Scheduler wiring** in-repo — invocation contract documented; ops must configure `ORA_INTERNAL_WORKER_TOKEN` and scheduler.
2. **Offer documents not durably expired** in this phase — read-boundary expiry (`offer_lifecycle.ts`) unchanged; cancel path may still mark offers `EXPIRED` in txn as before.
3. **Vitest full-file execution** unreliable in local workspace; use `test:phase-2j-unit-proof` + live harness for CI-style proof.
4. **No FCM/RTDB projection** of expiry — outbox only; consumers not implemented.

---

## 16. Explicit non-goals

NO_SHOW, ratings, payments, wallet, Maps, GPS, Redis, RTDB, FCM consumers, dispatch, driver online/offline, admin, Cargo, Delivery, ride UI, Phase 2K+.

---

## 17. Verdict

**PASS — PHASE 2J CLOSED**
