# Phase 2G — Architecture / Invariant Investigation

**Date:** 2026-09-09  
**Status:** INVESTIGATION ONLY — no production code modified  
**Verdict:** see §21

---

## 1. Executive summary

Phases 2E/2F closed the marketplace path through **driver assignment**:

`SEARCHING → OFFERS_AVAILABLE → DRIVER_ASSIGNED` (+ offers, cancel pre-assign, durable idempotency, outbox, live Firestore concurrency).

After assignment, the implemented system is a **domain dead-end**: `RideService` has no post-assignment transitions; `cancelRide` explicitly rejects post-assignment cancel; `RideState` in code ends at `DRIVER_ASSIGNED | CANCELLED | EXPIRED`; Flutter stops at create/offer/select/cancel.

Canonical product/architecture docs already define the next domain path:

`DRIVER_ASSIGNED → DRIVER_EN_ROUTE → DRIVER_ARRIVED → RIDE_STARTED → RIDE_COMPLETED (→ RIDE_CLOSED)`

**Phase 2G should be the smallest coherent vertical slice that unblocks that path without Phase 10’s Maps/GPS/RTDB/FCM surface:**

> **Post-assignment ride progression + post-assignment cancel**  
> Server-authoritative state transitions on the existing `rides/{rideId}` aggregate, reusing Phase 2E/2F idempotency, versioning, transactions, and outbox patterns.

Phase 2G is **not** Phase 10 (live navigation), **not** payments, **not** dispatch/matching, **not** ride UI, and **not** offer redesign.

There is **no prior `phase-02g*` doc** in the repo. This investigation defines Phase 2G from the closed 2E/2F code boundary + locked contracts (`docs/ORA_STATE_MACHINE.md`, `docs/product/ride-lifecycle.md`, `docs/architecture-final/04-api-contracts.md`, `docs/api/ride-api.md`, `docs/implementation/phase-10-trip.md`).

---

## 2. Current Phase 2E/2F contract (as implemented)

### 2.1 Inspected surfaces

| Area | Path |
|------|------|
| Ride domain | `backend/auth-service/src/rides/*` |
| State gates | `state_machine.ts`, `types.ts` |
| Service | `ride_service.ts` |
| Offer lifecycle | `offer_lifecycle.ts` |
| Routes | `routes.ts` |
| Idempotency | durable `idempotencyRecords` in txn |
| Outbox | `outboxEvents` write-only |
| Tests | `rides.test.ts`, `offer_lifecycle.test.ts`, live harnesses |
| Indexes | `firestore.indexes.json` |
| Flutter | `mobile/lib/features/ride/**` |
| Closure docs | `docs/implementation/phase-02e-*.md`, `phase-02f-ride-offers.md` |
| Locked SM / API | `docs/ORA_STATE_MACHINE.md`, `docs/api/ride-api.md`, `docs/architecture-final/04-api-contracts.md` |
| Full trip phase | `docs/implementation/phase-10-trip.md` (NOT STARTED; depends on Phase 9) |

### 2.2 Implemented states (code)

```ts
// types.ts — authoritative for running code today
SEARCHING | OFFERS_AVAILABLE | DRIVER_ASSIGNED | CANCELLED | EXPIRED
```

### 2.3 Implemented APIs

| Method | Endpoint | Notes |
|--------|----------|-------|
| POST | `/v1/rides` | Passenger create |
| GET | `/v1/rides/:rideId` | Passenger **or** assigned driver |
| POST | `/v1/rides/:id/offers` | Driver create |
| GET | `/v1/rides/:id/offers` | Passenger only |
| POST | `/v1/rides/:id/offers/:oid/withdraw` | Offering driver |
| POST | `/v1/rides/:id/offers/:oid/select` | Passenger assignment txn |
| POST | `/v1/rides/:id/cancel` | Passenger **pre-assign only** |

Missing vs contracts: `/en-route`, `/arrive`, `/start`, `/complete`, post-assignment cancel, `GET /v1/rides` history.

### 2.4 Implemented outbox events

`ride.created`, `ride.offer.received`, `ride.offer.withdrawn`, `ride.offer.selected`, `ride.assigned`, `ride.cancelled`.

Not emitted: `ride.driver.en_route`, `ride.driver.arrived`, `ride.started`, `ride.completed` (listed in `docs/architecture-review/event-contracts.md`).

### 2.5 Assignment invariants (must not be redesigned)

From code + `docs/architecture-review/system-invariants.md`:

1. Exactly one `assignedDriverId` after successful select.
2. `agreedFareMinor` / `agreedOfferId` / `agreedFareCurrency` set only in select txn; immutable thereafter.
3. Assignment is the **only** path to `DRIVER_ASSIGNED`.
4. Durable idempotency (key + requestHash + actorId) in Firestore.
5. Outbox rows written atomically with mutations; no consumers yet.
6. Client never writes authoritative ride/offer docs.
7. Offer uniqueness: `{rideId}_{driverId}_v{requestVersion}`.

### 2.6 Explicit post-assignment gap in code

```ts
// cancelRide — Phase 2E message still present
'Post-assignment cancellation is not implemented in Phase 2E.'
```

`RideDoc` already reserves `startedAt`, `completedAt`, `closedAt` (always null today). `publicRide()` does **not** yet expose `startedAt` / `completedAt`.

---

## 3. Proposed Phase 2G boundary

### 3.1 Business capability

**Assigned-driver ride progression through operational completion, plus post-assignment cancellation**, so an assigned ride is no longer stuck at `DRIVER_ASSIGNED`.

This is the next domain transition after:

create → offer → select → assign.

### 3.2 In scope

1. Extend `RideState` with: `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, `RIDE_STARTED`, `RIDE_COMPLETED`.
2. Driver mutations (assigned driver only):
   - `POST /v1/rides/:rideId/en-route`
   - `POST /v1/rides/:rideId/arrive`
   - `POST /v1/rides/:rideId/start`
   - `POST /v1/rides/:rideId/complete`
3. Expand cancel to post-assignment for **passenger (owner)** and **assigned driver**, still using existing `CANCELLED` + `cancelledBy` (see open questions).
4. State-machine enforcement for legal forward transitions only.
5. Durable idempotency + Firestore transactions + outbox events for each authoritative mutation.
6. Expose `startedAt` / `completedAt` on public ride projection when set.
7. Flutter domain/data use cases only (no UI).
8. Unit + live Firestore concurrency proofs for critical races.

### 3.3 Explicitly deferred (not Phase 2G)

| Defer | Why |
|-------|-----|
| Maps / GPS / geofence / proximity enforcement | Phase 4 / Phase 10; contracts require proximity later — **stub boundary** in 2G (same pattern as 2E dispatch eligibility stub) |
| RTDB live tracking | Phase 9 |
| Redis | Not introduced by 2E/2F |
| FCM / push | Phase 9 / notifications |
| Payment aggregate / cash-collected | Phase 11; ADR-008 separation |
| `RIDE_CLOSED` closure workflow | Post-completion operational drain; depends on payment/outbox consumers |
| `NO_SHOW` sweeper / Cloud Scheduler | Like offer/search TTL sweeper — read-boundary/timer later |
| Separate durable states `DRIVER_CANCELLED` / `PASSENGER_CANCELLED` | Full SM lists them; 2E uses `CANCELLED` + `cancelledBy` — prefer not redesigning unless blockers force it |
| `GET /v1/rides` history list | Useful but not required to progress one assigned ride |
| Ratings, SOS, receipts UI | Later |
| Cargo / Delivery / Admin / ML matching | Out of ride core |
| Ride UI / navigation | Explicit non-goal |

### 3.4 Answers to the 17 boundary questions

1. **Capability:** Post-assignment progression + cancel after assign.  
2. **New transitions:** `DRIVER_ASSIGNED→EN_ROUTE→ARRIVED→STARTED→COMPLETED`; assigned ride → `CANCELLED` (pre-complete).  
3. **Untouched states/paths:** Offer create/list/withdraw; select assignment atomicity; pre-assign SEARCHING/OFFERS_AVAILABLE semantics; agreed fare immutability.  
4. **New entities:** None required — mutate existing `rides/{rideId}`; reuse `idempotencyRecords` + `outboxEvents`. Optional: no new collections.  
5. **Do not modify:** Historical assignment fields after set; selected offer amount; Phase 2C auth; offer uniqueness scheme.  
6. **APIs:** `/en-route`, `/arrive`, `/start`, `/complete`; expand `/cancel`.  
7. **Auth:** Assigned driver for progression; passenger or assigned driver for post-assign cancel; foreign actors → `FORBIDDEN`.  
8. **Idempotency:** Required `Idempotency-Key` on all mutations; durable replay; key reuse with different body/actor → `IDEMPOTENCY_KEY_REUSED`.  
9. **Concurrency boundaries:** Per-ride document version; one forward transition at a time; cancel vs progression races.  
10. **Atomic:** Each transition = one Firestore txn (ride update + idempotency + outbox). Never split.  
11. **Eventual:** Outbox publish/projectors (still write-only in 2G); client UI refresh later.  
12. **Retries:** Same key → replay; different key same legal transition after success → `STATE_CONFLICT` / `INVALID_STATE_TRANSITION`.  
13. **Out of order:** Stale `expectedVersion` → `VERSION_CONFLICT`; illegal from-state → conflict; never rewind.  
14. **Crash:** Before commit → no mutation (client retries); after commit → idempotent replay returns success snapshot.  
15. **Expire/cancel:** Search `expiresAt` irrelevant post-assign; cancel terminal before `RIDE_COMPLETED`; completed rides not cancellable.  
16. **Driver disappears:** No presence/RTDB in 2G; passenger/driver cancel is the escape hatch; auto `DRIVER_CANCELLED` timeouts deferred.  
17. **Never violate:** Single assignee; immutable agreed fare; no backward SM; no client-authored state; no double completion; no assignment bypass.

---

## 4. State-machine impact

### 4.1 Add to code `RideState`

```
DRIVER_EN_ROUTE
DRIVER_ARRIVED
RIDE_STARTED
RIDE_COMPLETED
```

Keep existing: `SEARCHING`, `OFFERS_AVAILABLE`, `DRIVER_ASSIGNED`, `CANCELLED`, `EXPIRED`.

### 4.2 Legal Phase 2G transitions

| From | To | Actor | Endpoint |
|------|----|-------|----------|
| DRIVER_ASSIGNED | DRIVER_EN_ROUTE | Assigned driver | POST …/en-route |
| DRIVER_EN_ROUTE | DRIVER_ARRIVED | Assigned driver | POST …/arrive |
| DRIVER_ARRIVED | RIDE_STARTED | Assigned driver | POST …/start |
| RIDE_STARTED | RIDE_COMPLETED | Assigned driver | POST …/complete |
| DRIVER_ASSIGNED \| DRIVER_EN_ROUTE \| DRIVER_ARRIVED | CANCELLED | Passenger or assigned driver | POST …/cancel |
| (optional policy) RIDE_STARTED → CANCELLED | **Defer** unless product requires mid-trip cancel in 2G — recommend **in scope** for passenger+driver with fee fields null/0 (fee policy later) |

**Recommendation:** Allow cancel through `RIDE_STARTED` (not after `RIDE_COMPLETED`), matching product “during trip” cancel paths without implementing fee engines.

### 4.3 Forbidden

- Any backward transition  
- Skipping states (e.g. ASSIGNED → STARTED)  
- Non-assigned driver progression  
- Passenger calling en-route/arrive/start/complete  
- Mutating `agreedFare*`  
- Re-entering offerable states after assign  
- Completing a cancelled/expired ride  

### 4.4 Gate updates in `state_machine.ts`

Add helpers analogous to existing `assertOfferable` / `assertAssignable`:

- `assertCanGoEnRoute`, `assertCanArrive`, `assertCanStart`, `assertCanComplete`
- `assertCancellablePostAssign` (states before completed)

Do **not** weaken pre-assign offer/assign gates.

### 4.5 Timestamps

| Transition | Set fields |
|------------|------------|
| EN_ROUTE | `updatedAt`, `version++` (optional `enRouteAt` — **not in RideDoc today**; either add or omit — see open questions) |
| ARRIVED | `updatedAt`, `version++` |
| START | `startedAt`, `updatedAt`, `version++` |
| COMPLETE | `completedAt`, `updatedAt`, `version++` |
| CANCEL | existing cancel fields |

`closedAt` / `RIDE_CLOSED` remain null / unused in 2G.

---

## 5. Data model impact

### 5.1 Documents

| Collection | Change |
|------------|--------|
| `rides/{rideId}` | New states; set `startedAt`/`completedAt`; cancel post-assign |
| `rideOffers/*` | **No structural change**; offers already terminal after assign |
| `idempotencyRecords` | New operation names |
| `outboxEvents` | New event types |
| New collections | **None** |

### 5.2 Server-authoritative fields (clients must not supply)

`state`, `version`, `assignedDriverId`, `agreedFare*`, `startedAt`, `completedAt`, `closedAt`, `cancelledBy`, `cancellationFeeMinor`, timestamps, passengerId/driver identity.

Client may send: optional `expectedVersion`, optional `reason` on cancel, optional lat/lng **ignored or validated later** (if accepted in 2G body, must not trust for authorization).

### 5.3 What must not be rewritten

Assignment snapshot fields after select; selected offer document amounts; other rides’ documents.

---

## 6. API contract

Align with `docs/architecture-final/04-api-contracts.md` + `docs/api/ride-api.md` + `ORA_STATE_MACHINE` en-route:

### 6.1 New endpoints

All require auth + `Idempotency-Key`.

**POST `/v1/rides/:rideId/en-route`**  
- Actor: assigned driver  
- Body: `{}` or `{ "expectedVersion": n }` (reject unknown keys)  
- Success: 200 + public ride (`DRIVER_EN_ROUTE`, version+1)  
- Errors: `FORBIDDEN`, `RIDE_NOT_FOUND`, `STATE_CONFLICT` / `INVALID_STATE_TRANSITION`, `VERSION_CONFLICT`, idempotency errors  

**POST `/v1/rides/:rideId/arrive`**  
- Same pattern; from `DRIVER_EN_ROUTE` only  
- Proximity: **deferred** — do not invent GPS checks; document limitation; reserve error code `PROXIMITY_VIOLATION` for later without emitting it in 2G unless a stub flag is explicitly added (prefer omit until Maps phase)

**POST `/v1/rides/:rideId/start`**  
- From `DRIVER_ARRIVED`; sets `startedAt`

**POST `/v1/rides/:rideId/complete`**  
- From `RIDE_STARTED`; sets `completedAt`  
- Must **not** create payment intents in 2G (ADR-008) even if sample response in `ride-api.md` shows `paymentIntentId`

### 6.2 Expand cancel

**POST `/v1/rides/:rideId/cancel`**  
- Pre-assign: unchanged (passenger only)  
- Post-assign: passenger **or** `assignedDriverId`  
- Reject if `RIDE_COMPLETED` / `CANCELLED` / `EXPIRED`  
- Idempotent cancel-already-cancelled replay (already partially present)

### 6.3 Projection

Extend `publicRide` with `startedAt`, `completedAt` (and keep omitting internal fee snapshots unless already public).

---

## 7. Authorization / security model

| Operation | Allowed | Denied |
|-----------|---------|--------|
| en-route / arrive / start / complete | `caller.uid === ride.assignedDriverId` | Passenger, other drivers, unassigned |
| cancel pre-assign | passenger owner | drivers |
| cancel post-assign | passenger owner **or** assigned driver | foreign users |
| getRide | passenger or assigned (already) | IDOR others |

### Adversarial cases (must reject)

- Forged `driverId` / `passengerId` / `role` / `state` in body  
- Foreign driver progressing another driver’s ride  
- Passenger forging progression  
- Completing without assignment  
- Tampering `agreedFareMinor` / currency  
- Using offerId to re-assign mid-trip  
- Cross-ride cancel  

Server derives actor exclusively from verified token (Phase 2C pattern already used).

---

## 8. Idempotency model

Reuse Phase 2E/2F durable records:

| Field | Behavior |
|-------|----------|
| Key | Client `Idempotency-Key` header (required) |
| requestHash | Hash of rideId + operation + accepted body fields |
| actorId | Token uid |
| operation | e.g. `RIDE_EN_ROUTE`, `RIDE_ARRIVE`, `RIDE_START`, `RIDE_COMPLETE`, `RIDE_CANCEL` |
| Same key + same hash + same actor | Replay stored response |
| Same key + different hash/actor | `409 IDEMPOTENCY_KEY_REUSED` |
| Different key after success | Business conflict if state already advanced |

Do **not** replace with in-memory maps.

Suggested client nonce keys (Flutter): `ride:{rideId}:en-route`, `:arrive`, `:start`, `:complete`, `:cancel` via existing `IdempotencyNonceStore`.

---

## 9. Concurrency model

### Meaningful races and legal outcomes

| Race | Legal outcome(s) |
|------|------------------|
| Same driver double en-route, different keys | One 200 advance; other `STATE_CONFLICT` |
| Same key concurrent en-route | Both 200 replay; version +1 once |
| en-route vs arrive (wrong order) | Only en-route may succeed first; arrive fails until EN_ROUTE |
| arrive vs start vs complete out of order | Only forward edge from current state succeeds |
| Driver progression vs passenger cancel | Exactly one terminal/progression winner via txn; other conflict |
| Driver cancel vs passenger cancel | One cancel wins; other replay or conflict; single `CANCELLED` |
| Progression vs complete already done | Conflict |
| Stale `expectedVersion` | `VERSION_CONFLICT` |
| Unassigned driver after somehow cleared assignee | Forbidden / conflict (assignee immutable in 2G — do not clear on cancel? **Open:** keep `assignedDriverId` for audit after cancel, matching current pre-assign null-only pattern — post-assign cancel today never runs; recommend **retain** assignedDriverId on cancel for audit) |
| Process crash mid-txn | Firestore all-or-nothing |
| Client timeout after commit | Idempotent replay |

`requestVersion` is **not** the concurrency token for post-assign progression; **`ride.version`** is (optional `expectedVersion` body, same as select).

---

## 10. Transaction boundaries

Each progression/cancel mutation **must** use `db.runTransaction`:

1. Read/validate idempotency record  
2. Read ride  
3. Assert actor + legal from-state (+ optional expectedVersion)  
4. Write ride state/version/timestamps  
5. Write idempotency SUCCEEDED snapshot  
6. Write outbox event  

**No multi-ride fanout required** for progression (unlike assignment’s offer supersede).

Firestore transactions required for all concurrency-sensitive cases in §9. MemoryDb allowed for fast unit tests only — **not** final proof.

---

## 11. Outbox / event implications

Emit atomically (durable record only; no consumers):

| Transition | eventType |
|------------|-----------|
| EN_ROUTE | `ride.driver.en_route` |
| ARRIVED | `ride.driver.arrived` |
| START | `ride.started` |
| COMPLETE | `ride.completed` |
| CANCEL | `ride.cancelled` (existing) |

Payload minimum: `{ rideId, fromState, toState, actorId }` + version.  
Do **not** introduce Pub/Sub, RTDB mirrors, or FCM in 2G.

---

## 12. Failure / retry semantics

For each mutation (`en-route` | `arrive` | `start` | `complete` | post-assign `cancel`):

| Case | Expected |
|------|----------|
| Success | 200 + public ride |
| Validation | 400 `VALIDATION_ERROR` |
| Authz | 403 `FORBIDDEN` |
| Missing ride | 404 `RIDE_NOT_FOUND` |
| Wrong state | 409 `STATE_CONFLICT` or 422 `INVALID_STATE_TRANSITION` (pick one code and use consistently with existing ride errors — **prefer existing `STATE_CONFLICT`** used today) |
| Stale version | 409 `VERSION_CONFLICT` |
| Idempotent replay | Original success status/body |
| Idempotency reuse | 409 `IDEMPOTENCY_KEY_REUSED` |
| Txn contention | SDK retries updateFunction; eventually one winner |
| Client timeout after commit | Replay succeeds |
| Crash before commit | No write; retry safe |
| Duplicate delivery | Idempotency or state conflict — never double version bump |

Do not invent payment failures inside ride complete.

---

## 13. Offline / lifecycle implications

| Scenario | 2G behavior |
|----------|-------------|
| App crash after assign | GET ride shows `DRIVER_ASSIGNED`; driver retries en-route with durable nonce |
| Offline during EN_ROUTE | Server state unchanged until next successful mutation; no RTDB presence |
| Driver “disappears” | No auto-timeout in 2G; passenger cancel available |
| Reconnect | Client re-GETs ride; discard stale local optimistic state via `version` |
| Ride search expiry | Irrelevant after assign; do not expire assigned rides via `expiresAt` search window |
| Offer TTL | Irrelevant post-assign |

---

## 14. Complete test matrix

### Positive

- Happy path: assign → en-route → arrive → start → complete  
- Each step sets correct state, version+1, timestamps  
- Outbox event per step  
- Idempotent replay each step  
- Post-assign passenger cancel from ASSIGNED/EN_ROUTE/ARRIVED/STARTED  
- Post-assign driver cancel from same  
- getRide as passenger and assigned driver after each state  

### Negative

- Unauthenticated  
- Passenger calls en-route/arrive/start/complete  
- Foreign driver progression  
- Wrong state (skip ahead / go backward)  
- Cancel after COMPLETED  
- Pre-assign driver cancel still forbidden  
- Malformed body / unknown keys  
- Forged identity fields  
- Stale expectedVersion  
- Complete without start  

### Concurrency (memoryDb fast + **live Firestore required**)

- 2/10/50 concurrent identical transition (e.g. complete) → one advance  
- Same idempotency key concurrent → replay  
- Different keys concurrent → one win / rest conflict  
- en-route vs cancel  
- start vs cancel  
- complete vs cancel  
- arrive vs start (ordering)  
- Two actors cancel concurrently  

### Failure

- Replay after success  
- Contention observed in live harness  
- Duplicate request after timeout (simulated by replay)  

### Persistence

After each critical mutation, read Firestore: state, version, assignee, agreedFare unchanged, timestamps, outbox count, idempotency record.

### Regression

- Existing 2E/2F suites: ride-proof, offer-create live concurrency, rides vitest, offer_lifecycle  
- Assignment still sole path to DRIVER_ASSIGNED  
- Offers unchanged  

---

## 15. Firestore live-proof plan

Mirror Phase 2E/2F harness pattern:

**New script (implementation phase):**  
`backend/auth-service/scripts/run_ride_progression_firestore_concurrency.ts`  
**npm:** `test:ride-progression-firestore-concurrency` (+ root `emulators:exec` wrapper)

Must use:

- `FIRESTORE_EMULATOR_HOST`
- firebase-admin
- real `runTransaction`
- instrumented contention counters
- persisted document asserts

Minimum live cases:

1. 2/10/50 concurrent `complete` (or `en-route`) from valid prior state → exactly one version bump  
2. Same idempotency key concurrent progression  
3. Different keys uniqueness/conflict  
4. Progression vs cancel → one legal outcome  
5. Skip-state attempt under concurrency still illegal  
6. Agreed fare immutable across all winners  

MemoryDb ≠ final proof.

Run from no-space copy if spaced-path firebase-admin hang persists.

---

## 16. Risks

| Risk | Mitigation |
|------|------------|
| Full SM uses `DRIVER_CANCELLED` / `PASSENGER_CANCELLED` but code uses `CANCELLED` | Keep `CANCELLED` + `cancelledBy` in 2G; document mapping |
| Contracts require proximity | Explicit deferral; Phase 10 owns geofence |
| Completing without payment surprises product | ADR-008; no payment writes in 2G |
| Mid-trip cancel fee policy undefined | Store `cancellationFeeMinor: 0` / null; policy later |
| `enRouteAt` / `arrivedAt` absent from RideDoc | Use state + `updatedAt` only, or add fields deliberately |
| publicRide omits started/completed today | Must extend projection in 2G |
| Expanding cancel could regress pre-assign tests | Keep pre-assign path; additive post-assign branch |
| Phase 10 doc depends on Phase 9 | 2G deliberately decouples domain SM from realtime UX |

### Bugs found during investigation (blocking?)

**None that block architecture.** Noted gaps are intentional Phase 2E/2F stop lines, not defects:

- Post-assign cancel throws by design  
- Trip endpoints absent by design  
- Proximity not implemented by design  

---

## 17. Explicit non-goals

Do **not** implement in Phase 2G:

Maps, GPS, geolocation validation, geofencing, RTDB, Redis, FCM, push, production dispatch, proximity/ML matching, payments/wallet/ledger, `RIDE_CLOSED` workflow, NO_SHOW sweeper, Cloud Scheduler workers, ratings, SOS, receipts UI, ride UI, navigation, Cargo, Delivery, Admin, offer redesign, assignment redesign, Auth/OTP changes.

---

## 18. Implementation plan (for the next implementation prompt only)

Ordered, small cohesive steps — **do not execute in this investigation**:

1. Extend `RideState` + `state_machine` transition asserts.  
2. Add shared `assertAssignedDriver(caller, ride)` helper.  
3. Implement `enRoute` / `arrive` / `start` / `complete` in `RideService` with txn + idempotency + outbox.  
4. Expand `cancelRide` post-assign branch without breaking pre-assign.  
5. Wire routes; reject unknown body keys; optional `expectedVersion`.  
6. Extend `publicRide` timestamps.  
7. Flutter: parse new states/timestamps; add use cases + repository/datasource methods; nonce keys.  
8. Vitest matrix (§14).  
9. Live Firestore progression concurrency harness (§15).  
10. Regression: `test:ride-proof`, offer-create live suite, Phase 2F vitest.  
11. Write `docs/implementation/phase-02g-*.md` closure report after green proofs.  

---

## 19. Definition of Done

Phase 2G implementation is done when:

1. Assigned driver can advance ASSIGNED → … → `RIDE_COMPLETED` via APIs.  
2. Illegal transitions/actors rejected.  
3. Post-assign cancel works for passenger and assigned driver before completion.  
4. Agreed fare and assignee immutable across progression.  
5. Durable idempotency + outbox for each mutation.  
6. Flutter domain/data supports the mutations (no UI).  
7. Unit/integration tests green.  
8. **Live Firestore progression concurrency PROVEN** (not memoryDb-only).  
9. Phase 2E/2F regression green.  
10. Non-goals remain unimplemented.  
11. Closure doc states limitations (no proximity, no payment, no RTDB).  

---

## 20. Open questions / unknowns

| # | Question | Recommendation for implementation prompt |
|---|----------|------------------------------------------|
| 1 | Split cancel states vs `CANCELLED`+`cancelledBy`? | Keep `CANCELLED`+`cancelledBy` |
| 2 | Allow cancel during `RIDE_STARTED`? | Yes; fee=0 |
| 3 | Clear `assignedDriverId` on cancel? | Retain for audit |
| 4 | Require `expectedVersion` or optional? | Optional (match select) |
| 5 | Add `enRouteAt` / `arrivedAt` fields? | Optional; not required if state+updatedAt sufficient |
| 6 | Accept client lat/lng on arrive/start/complete? | Reject unknown keys in 2G (no GPS theater) |
| 7 | `INVALID_STATE_TRANSITION` vs `STATE_CONFLICT`? | Prefer existing `STATE_CONFLICT` |
| 8 | Is `/en-route` mandatory vs arrive-from-ASSIGNED? | **Mandatory** per ORA_STATE_MACHINE |
| 9 | Should 2G include `GET /v1/rides` history? | No — separate slice |
| 10 | When does proximity become mandatory? | Maps/Phase 10 — not 2G DoD |

---

## 21. Final verdict

# READY FOR PHASE 2G IMPLEMENTATION

### Exact implementation scope for the next prompt

**Phase 2G — Post-assignment ride progression vertical slice**

Implement server-authoritative transitions on the existing ride aggregate:

`DRIVER_ASSIGNED → DRIVER_EN_ROUTE → DRIVER_ARRIVED → RIDE_STARTED → RIDE_COMPLETED`

plus **post-assignment cancel** to `CANCELLED` for passenger owner or assigned driver (before completion).

Reuse Phase 2E/2F: Firestore transactions, durable idempotency, outbox-only events, token-derived auth, modular monolith in `backend/auth-service`, Flutter domain/data only.

**Defer:** proximity/GPS/Maps, RTDB, Redis, FCM, payments, `RIDE_CLOSED`, NO_SHOW sweepers, ride UI, offer/assignment redesign.

**Prove:** live Firestore emulator concurrency for progression/cancel races (2/10/50 where meaningful), plus 2E/2F regression.

---

### Hard stop

This document is the investigation deliverable only.

- Phase 2G **not** implemented here  
- Production code **not** modified  
- Phase 2H+ / Phase 10 / Maps / payments **not** started  

### Inspected vs unknown

**Inspected:** ride module, state machine, service/routes, idempotency/outbox, tests/harnesses, Flutter ride domain, phase 2E/2F docs, ORA state machine, ride API/contracts, event contracts, system invariants, phase-10 trip plan, MVP contract notes.

**Unknown / deferred decisions:** listed in §20 (cancel state naming, mid-trip cancel fees, timestamp field additions) — none block starting implementation under the recommendations above.
