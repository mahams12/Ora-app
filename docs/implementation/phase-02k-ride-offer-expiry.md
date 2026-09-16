# Phase 2K — Durable Offer EXPIRED Write-Path / Sweeper

**Status:** CLOSED  
**Date:** 2026-09-10  
**Architecture:** `docs/implementation/phase-02k-architecture-investigation.md`

---

## 1. Exact scope

Implemented **only** the approved Phase 2K boundary:

```text
rideOffers/{offerId}: PENDING → EXPIRED
when expiresAt <= server now
```

PLUS bounded cleanup of remaining PENDING offers when the parent ride becomes `EXPIRED`.

Every durable offer expiry atomically writes `ride.offer.expired`.

**Also included (tiny consistency fix):** pre-assign cancel path now emits `ride.offer.expired` with reason `parent_ride_cancelled` (same txn; reads-before-writes ordering fixed).

**Not in scope:** NO_SHOW, ratings, payments, Maps, Redis, RTDB, FCM, dispatch, Flutter UI, Phase 2L+.

---

## 2. Architecture

| Component | Role |
|-----------|------|
| `RideService.expireOffer` | Single-offer transactional expiry; state-idempotent |
| `RideService.sweepExpiredOffers` | Bounded query `PENDING + expiresAt<=now` + per-offer `expireOffer` |
| `RideService.expireRide` (extended) | Ride EXPIRED + bounded in-txn PENDING offer cleanup + post-commit multi-pass |
| `RideService.cleanupPendingOffersForExpiredRide` | Multi-pass parent cleanup (bound 50/pass, max 20 passes) |
| `POST /v1/internal/rides/offer-expire-sweep` | Worker-only entry (reuses `X-Ora-Worker-Token`) |
| Pre-assign `cancelRide` | PENDING→EXPIRED + `ride.offer.expired` (`parent_ride_cancelled`) |

### TTL invariant (offer sweeper / `offer_ttl_elapsed`)

```text
status == PENDING
AND expiresAt <= server now
```

Re-checked inside `runTransaction` after re-read.

### Parent invariant (`parent_ride_expired`)

```text
status == PENDING
AND parent ride.state == EXPIRED
```

Does **not** expire merely because a parent ride document exists.

---

## 3. Query and index

**Sweeper query:**

```text
rideOffers
  .where('status', '==', 'PENDING')
  .where('expiresAt', '<=', nowIso)
  .limit(batchSize)   // default 100, max 200
```

**Index added** (`firestore.indexes.json`):

```json
{ "fieldPath": "status", "order": "ASCENDING" },
{ "fieldPath": "expiresAt", "order": "ASCENDING" }
```

Live emulator proof: indexed query returns due offers (`PASS sweeper query index PENDING due offer live`).

Parent cleanup uses existing `rideId + status` index.

---

## 4. Transaction semantics

### `expireOffer` (TTL)

1. Re-read offer  
2. Already `EXPIRED` → `already_expired` (no outbox)  
3. Non-`PENDING` → `skipped`  
4. `expiresAt > now` / malformed → `skipped` (`not_due`)  
5. Else: `status=EXPIRED` + exactly one `ride.offer.expired`  
6. **Does not** bump `rides.version`

### `expireOffer` (parent)

Same as above, but gate is `ride.state === EXPIRED` instead of TTL.

### `expireRide` (extended)

1. All reads first (ride + bounded PENDING offers)  
2. Ride → `EXPIRED` + `ride.expired` + version+1  
3. Bounded PENDING offers → `EXPIRED` + per-offer `ride.offer.expired` (`parent_ride_expired`)  
4. Post-commit: `cleanupPendingOffersForExpiredRide` for overflow / already-expired leftovers  

Overflow beyond bound is **not** claimed atomic; subsequent cleanup / TTL sweeper processes remainder.

---

## 5. Race semantics

| Race | Proven outcome |
|------|----------------|
| Expire vs SELECT | One terminal: SELECTED (expire skipped) **or** EXPIRED (select `OFFER_EXPIRED`) |
| Expire vs WITHDRAW | One terminal: WITHDRAWN or EXPIRED |
| Expire vs parent ride EXPIRED | Offer EXPIRED; **exactly one** `ride.offer.expired` |
| Expire vs CANCEL | Offer EXPIRED; **exactly one** `ride.offer.expired` |
| N-way same offer (2/10/50) | Exactly one expiry event; contended txns observed |
| Retry after success | `already_expired`; no duplicate event |

Never `EXPIRED → SELECTED` or `EXPIRED → WITHDRAWN`.

---

## 6. Parent-ride cleanup

- In-txn bound: `MAX_OFFERS_SUPERSEDE_IN_TXN` (50)  
- Post-commit multi-pass until empty or 20 passes  
- Reason: `parent_ride_expired`  
- Ride version bumped **once** for the ride transition only; offer-only paths never bump ride version  

---

## 7. Outbox

Event type: **`ride.offer.expired`** only.

Payload (minimum):

- `rideId`, `offerId`, `driverId`, `reason`, `expiresAt`

Reasons:

- `offer_ttl_elapsed`
- `parent_ride_expired`
- `parent_ride_cancelled`

Envelope matches existing outbox (`aggregateType: ride`, `publishState: PENDING`, schemaVersion 1). Consumers still not implemented.

---

## 8. Worker security

- Route: `POST /v1/internal/rides/offer-expire-sweep`  
- Auth: `X-Ora-Worker-Token` == `ORA_INTERNAL_WORKER_TOKEN`  
- Missing/short token → 503; bad token → 403  
- No passenger/driver JWT route for expiry  
- Firestore client writes remain denied for `rideOffers`  

---

## 9. Retry / failure behavior

- Worker has no client Idempotency-Key  
- State idempotent: already EXPIRED → no mutation, no second event  
- Sweeper crash mid-batch: per-offer txns; retry safe  
- Partial parent cleanup: next pass / TTL sweeper  

---

## 10. Observability

Sweep log `RIDE_OFFER_EXPIRE_SWEEP`: scanned / expired / alreadyExpired / skipped / failed / durationMs / requestId.

---

## 11. Tests

| Suite | Command | Result |
|-------|---------|--------|
| Unit (MemoryDb) | `npm run test:phase-2k-unit-proof` | **7/7 PASS** |
| Live Firestore | `test:ride-offer-expire-firestore-concurrency` via emulator | **14/14 PASS** |

---

## 12. Live Firestore evidence

Emulator host `127.0.0.1:8181` (project `ora-app-d8112`).

Contention notes captured:

```text
2-way: contendedTxns+=1
10-way: contendedTxns+=9
50-way: contendedTxns+=50
expire-vs-select: EXPIRE won
expire-vs-withdraw: EXPIRE won
expire-vs-parent: single offer event
expire-vs-cancel: single offer event
```

Index query proven live. Persisted offer status + single outbox event verified.

---

## 13. Regression evidence

| Suite | Result |
|-------|--------|
| Phase 2E ride proof | **17/17 PASS** |
| Phase 2E assignment concurrency live | **8/8 PASS** |
| Phase 2F offer-create live | **8/8 PASS** (clean emulator) |
| Phase 2G progression live | **8/8 PASS** |
| Phase 2H close live | **7/7 PASS** |
| Phase 2I list live | **7/7 PASS** |
| Phase 2J expire live | **10/10 PASS** (clean emulator) |
| Phase 2J unit proof | **4/4 PASS** |
| Flutter `dart analyze lib/features/ride` | **No issues found** |
| Flutter `test/features/ride` | **5/5 PASS** |

---

## 14. Self-audit

| Question | Answer |
|----------|--------|
| Can an expired offer become SELECTED? | No — select asserts PENDING + TTL; live race rejects with `OFFER_EXPIRED` |
| Can an expired offer become WITHDRAWN? | No — withdraw asserts; race rejects |
| Can a selected offer be expired? | No — non-PENDING skip |
| Can two workers generate two expiry events? | No — 2/10/50-way live: exactly one event |
| Can parent ride expiry duplicate offer events? | No — live race: one event |
| Can cancel + sweep duplicate events? | No — live race: one event; already_EXPIRED short-circuit |
| Can offer expiry modify ride.version incorrectly? | No — offer-only path leaves version unchanged (live proven) |
| Can an offer be expired before its TTL? | Only via parent EXPIRED / cancel reasons — not via TTL sweeper |
| Can a client invoke the worker? | No — worker token required |
| Is the sweeper query bounded? | Yes — default 100, max 200 |
| Is the Firestore index required? | Yes — `status + expiresAt`; live query proven |
| Is `rideOffers/{offerId}` sole SoT? | Yes — no duplicate collections |
| Scope leak? | No |

---

## 15. Known limitations

1. No Cloud Scheduler wiring in-repo (same as 2J) — ops configures token + schedule.  
2. If `expireRide` crashes after ride commit but before post-commit cleanup completes, PENDING offers with **future** TTL may linger until TTL sweeper; select is already blocked by ride `EXPIRED`.  
3. Parent in-txn cleanup bound 50; overflow via multi-pass (not single atomic fan-out).  
4. Outbox consumers still absent.  
5. Vitest full-file suite still unreliable locally; use dedicated proof scripts.

---

## 16. Explicit non-goals

NO_SHOW, ratings, payments, wallet, Maps, GPS, Redis, RTDB, FCM, dispatch, driver online/offline, Admin, Cargo, Delivery, ride UI, Phase 2L+.

---

## 17. Verdict

**PASS — PHASE 2K CLOSED**
