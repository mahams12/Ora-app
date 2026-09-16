# PHASE 2L ARCHITECTURE INVESTIGATION

**Date:** 2026-09-10  
**Status:** INVESTIGATION ONLY — no production code modified  
**Baseline:** Phases 2C–2K CLOSED (2E–2K live-proven per closure docs)

---

## 1. Current verified baseline

Verified against **source code** (not docs alone). Claims below are implementation facts.

### Closed capabilities present in code

| Phase | Verified in code |
|-------|------------------|
| 2C Auth | Auth routes / register / profile (prior closures) |
| 2E | `createRide`, get, offers create/list, select, pre-assign cancel; assignment txn; outbox |
| 2F | Offer uniqueness, withdraw, read-boundary `offer_lifecycle`; durable offer expiry completed in **2K** |
| 2G | `en-route` / `arrive` / `start` / `complete`; post-assign cancel; `ride.version` concurrency |
| 2H | `closeRide` → `RIDE_CLOSED` + `ride.closed` |
| 2I | `GET /v1/rides` list/cursor/status filters |
| 2J | `expireRide` / `sweepExpiredRides`; `POST /v1/internal/rides/expire-sweep`; `ride.expired` |
| 2K | `expireOffer` / `sweepExpiredOffers`; parent EXPIRED cleanup; `POST /v1/internal/rides/offer-expire-sweep`; `ride.offer.expired`; cancel emits offer expiry events |

### State machine (`types.ts` + `state_machine.ts`)

```text
SEARCHING → OFFERS_AVAILABLE → DRIVER_ASSIGNED
  → DRIVER_EN_ROUTE → DRIVER_ARRIVED → RIDE_STARTED
  → RIDE_COMPLETED → RIDE_CLOSED
  | CANCELLED | EXPIRED
```

- **`NO_SHOW`:** **missing** (not in `RIDE_STATES`, guards, routes, or outbox).
- Aggregate `TERMINAL`: `CANCELLED`, `EXPIRED`, `RIDE_CLOSED` only.
- Post-assign cancellable includes `DRIVER_ARRIVED`.

### RideDoc timestamps (code)

| Field | Present |
|-------|---------|
| `expiresAt`, `assignedAt`, `startedAt`, `completedAt`, `closedAt`, `updatedAt`, `createdAt` | Yes |
| **`arrivedAt`** | **No** — `markArrived` does not write it; schema `rides` also omits it |

### Worker / indexes / Flutter

- Worker auth: `X-Ora-Worker-Token` / `ORA_INTERNAL_WORKER_TOKEN` for ride + offer expire sweeps.
- Indexes include `rides (state, expiresAt)`, `rideOffers (status, expiresAt)`, list composites, `assignedDriverId + state`.
- Flutter ride: domain/data HTTP client through close/list; **no UI**. Driver/maps/payments stubs.

### Active-assignment guard (code)

`createOffer` blocks only:

```text
assignedDriverId == uid AND state == DRIVER_ASSIGNED
```

Does **not** block `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` / `RIDE_STARTED` / `RIDE_COMPLETED`.

### Outbox events written (code)

Includes `ride.*` through `ride.expired` / `ride.offer.expired`. **No** `ride.no_show`.

---

## 2. Candidate comparison

| ID | Candidate | Status | Contract frozen? | Infra | Unblocks SM hole? | Rework risk | 2L fit |
|----|-----------|--------|------------------|-------|-------------------|-------------|--------|
| **L1** | Persist `arrivedAt` on arrive (wait-clock) | Missing field | Pattern matches `startedAt`/`completedAt`; **field not in schema** | None | Enables NO_SHOW query | Low | **Recommended prerequisite** |
| **L2** | Full `NO_SHOW` sweeper | State absent | Partial (transition/TTL/actor frozen; fee/history/count/payload open) | Worker + index | Yes | Medium–high if open decisions invented | **Not yet** |
| **L3** | Active-assignment guard expansion | Partial | Behavior implied by matching docs; COMPLETED-as-busy slightly open | None (index exists) | No | Low | Thin correctness sibling |
| **L4** | Ratings aggregate | Schema only | **HTTP API not frozen** | New writes | No | High API churn | Reject |
| **L5** | Active-ride discovery API | Partial via `GET /v1/rides?status=all` | Dedicated API **not frozen** | None/thin | No | Low | Too product/thin |
| **L6** | Go-online / dispatch / Maps / payments / FCM | Absent | Platform ADRs | Redis/RTDB/Maps/PSP | No | High | Later phases |

### Why NO_SHOW is not automatically 2L

Frozen in docs (`ORA_STATE_MACHINE.md`, product lifecycle, event-contracts):

- Only transition: `DRIVER_ARRIVED → NO_SHOW`
- Actor: **server** (Cloud Scheduler / timer), not passenger/driver HTTP
- Wait TTL: **5 minutes**
- Terminal (not followed by `RIDE_CLOSED`)
- Durable event type name: `ride.no_show`
- GPS **not** required for the NO_SHOW write (proximity is about *entering* ARRIVED)

**Not frozen / blocking:**

| # | Open decision | Why it blocks full NO_SHOW now |
|---|---------------|--------------------------------|
| D1 | Authoritative wait-clock field | No `arrivedAt` in code or schema; `updatedAt` is unsafe (any update moves the clock) |
| D2 | Fee / payment consequence | Payment docs define cancel-after-arrived fees; **no NO_SHOW fee rule**; ADR-008 forbids inventing payment coupling |
| D3 | History `status=` mapping | 2I: `EXPIRED` only under `all`; NO_SHOW mapping unspecified |
| D4 | `drivers.noShowCount` side effect | Schema has field; **who increments on NO_SHOW** undefined (SM says passenger didn’t board) |
| D5 | Event payload shape | Type listed; fields not specified |
| D6 | Client declare-no-show API | Not in ride-api; must not invent driver/passenger endpoints |

GPS for NO_SHOW sweeper: **not required**. Ratings: **not required**. Grace period: **already frozen (5m)**.

Therefore: do **not** implement full NO_SHOW until D1 (at minimum) is frozen; D2–D4 must be explicit non-goals or product decisions—not invented in code.

---

## 3. Recommended slice

**Phase 2L — Arrive wait-clock field (`arrivedAt`) persistence**

Implement **only**:

```text
On successful durable transition DRIVER_EN_ROUTE → DRIVER_ARRIVED:
  set rides/{rideId}.arrivedAt = server now (ISO)
  exactly once (idempotent on already-arrived / already-set)
```

No new ride state. No sweeper. No `NO_SHOW`. No fees. No ratings. No public new endpoints required (existing `POST .../arrive`).

This is the **smallest prerequisite** that freezes the wait-clock contract required for a later NO_SHOW sweeper (candidate 2M), without inventing NO_SHOW policy.

---

## 4. Why this is the smallest correct slice

1. **Unblocks the last reserved SM timer class** without prematurely expanding terminals.  
2. **Mirrors existing lifecycle timestamps** already used in code (`startedAt` on start, `completedAt` on complete, `closedAt` on close).  
3. **Dependency-safe:** no Redis/Maps/payments/FCM; no new worker route required.  
4. **Avoids inventing** fee, history enum, `noShowCount`, or client no-show APIs.  
5. **Active-assignment guard (L3)** is valuable but does not freeze the NO_SHOW clock—orthogonal micro-gap.  
6. **Ratings (L4)** blocked on unfrozen HTTP API.  
7. Full **NO_SHOW (L2)** would force D1–D4 assumptions → violates investigation rules.

---

## 5. Exact domain contract

### Invariants

1. `arrivedAt` is set **if and only if** the ride has durably entered `DRIVER_ARRIVED` (or later states that progressed through arrive).  
2. `arrivedAt` is **immutable** once set (retry / re-arrive path must not overwrite).  
3. Server time is authoritative (`nowIso` in the same txn as the state transition).  
4. Clients cannot write `arrivedAt` (Firestore rules remain deny-client for rides).  
5. Absence of `arrivedAt` on pre-2L ARRIVED/in-progress rides is a **legacy gap**; backfill is **out of scope** unless separately approved (OPEN if NO_SHOW must cover legacy rows).

### Non-behavior

- Does not start NO_SHOW countdown enforcement.  
- Does not change cancel/start/complete legality.  
- Does not require proximity validation (arrive remains tap-authoritative as today).

---

## 6. State transitions

| From | To | Change |
|------|-----|--------|
| `DRIVER_EN_ROUTE` | `DRIVER_ARRIVED` | Existing transition; **additionally** set `arrivedAt` once |
| Other transitions | — | Unchanged |

No new states. `NO_SHOW` remains **not** introduced.

---

## 7. Actor / authorization model

| Actor | Behavior |
|-------|----------|
| Assigned driver | Existing `POST /v1/rides/:rideId/arrive` (unchanged authz) |
| Passenger | Still cannot arrive |
| Worker | Not involved in 2L |
| Client Firestore | Still cannot write ride docs |

IDOR / forged rideId: existing arrive gates (assigned driver + state machine) unchanged; field write is inside the same authorized txn.

---

## 8. Data model changes

| Collection | Change |
|------------|--------|
| `rides/{rideId}` | Add nullable `arrivedAt: string \| null` (ISO), set on arrive |
| Schema docs | Should document `arrivedAt` when implementing (investigation does not edit schema now) |
| New collections | **None** |
| Indexes | **None required for 2L** (no sweeper query yet) |

**OPEN DECISION D1 (recommended resolution for implementation approval):** adopt field name `arrivedAt` as the wait-clock start, parallel to `startedAt` / `completedAt` / `closedAt`.

---

## 9. API changes

| Surface | Change |
|---------|--------|
| `POST .../arrive` | Response `publicRide` should expose `arrivedAt` once set |
| Other ride DTOs | Include `arrivedAt` when present (null otherwise) |
| New endpoints | **None** |
| Flutter | Optional domain field on `Ride` entity + parse; **no UI** |

---

## 10. Transaction / idempotency boundary

Inside existing `progressAssignedRide` txn for arrive:

1. Re-read ride; assert `DRIVER_EN_ROUTE → DRIVER_ARRIVED` (existing).  
2. Set `state`, `version+1`, `updatedAt`, and **`arrivedAt = nowIso`** if `arrivedAt` is null.  
3. If already `DRIVER_ARRIVED` (idempotent success path): return current doc **without** changing `arrivedAt` or bumping version again (preserve existing progression idempotency semantics).  
4. Outbox `ride.driver.arrived` remains as today (no new event type for 2L).  
5. User `Idempotency-Key` behavior unchanged.

---

## 11. Outbox / events

| Event | 2L |
|-------|-----|
| `ride.driver.arrived` | Unchanged (already emitted on arrive) |
| `ride.no_show` | **Not written** (deferred) |

Optional future: include `arrivedAt` in arrive payload — **not required** for 2L DoD; avoid speculative payload churn.

---

## 12. Firestore / index requirements

| Item | 2L |
|------|-----|
| Extra reads/writes | Same arrive txn + one field |
| New composite indexes | **None** |
| Sweeper | **None** |
| Hot docs | Same ride doc contention as today on arrive |
| Fan-out | None |

**Future NO_SHOW (not 2L)** would need something like:

```text
state == DRIVER_ARRIVED AND arrivedAt <= now - 5m
```

→ composite index `state + arrivedAt` — **do not add in 2L**.

---

## 13. Concurrency matrix (recommended slice)

| Race | Expected single outcome | Why |
|------|-------------------------|-----|
| Arrive vs arrive (same driver, 2-way) | One version bump; one `arrivedAt`; second idempotent success | Existing progression idempotency + state gate |
| Arrive vs cancel | Cancel → `CANCELLED` **or** arrive → `DRIVER_ARRIVED`+`arrivedAt`; never both | Single ride doc txn; loser `STATE_CONFLICT` |
| Arrive vs start (illegal without arrive) | Start requires `DRIVER_ARRIVED`; cannot skip | `assertProgression` |
| Stale `expectedVersion` | `VERSION_CONFLICT` | Existing |
| Idempotency key replay | Same response snapshot | Existing idempotency records |
| Same key / different body | `IDEMPOTENCY_KEY_REUSED` | Existing |
| Different actor same key | Rejected | Existing |
| Worker expire sweeps | Irrelevant to arrive field | N/A |
| Offline retry after success | Replay or already-arrived path; `arrivedAt` stable | Idempotency + immutability |

Invalid outcomes prevented: overwriting `arrivedAt`; setting `arrivedAt` without durable ARRIVED; passenger writing field.

---

## 14. Failure / retry / offline behavior

| Scenario | Protection |
|----------|------------|
| Timeout after commit | Idempotency replay or already-`DRIVER_ARRIVED` returns same `arrivedAt` |
| Client retry | Same |
| Process crash mid-txn | Firestore atomicity — all or nothing |
| Outbox failure after commit | Same as 2G: outbox in txn; consumers still absent |
| Stale client | Version / state conflict |
| Emulator restart | N/A for field semantics |
| Legacy ARRIVED rides without `arrivedAt` | Remain null until backfill decision (OPEN for later NO_SHOW) |

No new worker retry mechanism required for 2L.

---

## 15. Security analysis

| Threat | Assessment |
|--------|------------|
| Unauthorized arrive | Existing assigned-driver check |
| IDOR | Existing ride ownership / assignment checks |
| Forged user id | Token uid only |
| Client sets `arrivedAt` | Denied by rules; only Admin SDK path |
| Worker abuse | No new worker route |
| Cross-user exposure | `arrivedAt` is ride lifecycle metadata already visible to parties who can `getRide` |
| Replay | Idempotency ownership unchanged |

---

## 16. Test plan

### Unit / MemoryDb

1. Arrive sets `arrivedAt` ISO string.  
2. Arrive does not set `arrivedAt` on en-route (null until arrive).  
3. Idempotent re-arrive / replay: `arrivedAt` unchanged.  
4. Cancel from EN_ROUTE: no `arrivedAt`.  
5. Start after arrive: `arrivedAt` preserved.  
6. Authz: passenger arrive still forbidden.  
7. Version bump once on first arrive.

### Live Firestore

1. Persist `arrivedAt` on real arrive txn.  
2. Concurrent 2-way arrive: single `arrivedAt` + version+1.  
3. Arrive vs cancel race: one terminal outcome; if arrived wins, `arrivedAt` set; if cancel wins, state `CANCELLED` and `arrivedAt` null.  
4. Idempotency replay returns same `arrivedAt`.

### Regression

2E–2K live/unit harnesses affected by progression/arrive; Flutter ride parse if field added.

**Evidence required for CLOSED:** unit green + live arrive persistence/concurrency green + 2G/2J/2K regressions green. Do not claim production-ready.

---

## 17. Live Firestore proof plan

- Emulator Admin SDK `runTransaction`  
- Assert stored `arrivedAt` equals txn server time within bound  
- 2-way / 10-way arrive contention on same ride  
- Document evidence in closure doc  

No 50-way required unless contention harness already standardized for progression (optional).

---

## 18. Regression plan

| Suite | Why |
|-------|-----|
| Progression live (2G) | Arrive path changed |
| Close / complete paths | Ensure `arrivedAt` preserved |
| Cancel races | Arrive vs cancel |
| 2J/2K sweepers | Must ignore ARRIVED rides (unchanged query) |
| Flutter ride entity tests | If DTO updated |

---

## 19. Explicit non-goals (Phase 2L)

- `NO_SHOW` state, sweeper, `ride.no_show`  
- Fees / payments / ledger / `cancellationFeeMinor` policy for no-show  
- `drivers.noShowCount` updates  
- Ratings / reviews  
- History `status` enum expansion  
- GPS / proximity / Maps  
- Redis / RTDB / FCM / Pub/Sub consumers  
- Dispatch / go-online  
- Active-assignment guard expansion (optional later sibling; not required for wait-clock)  
- Admin force_transition  
- Flutter UI  
- Backfill of historical ARRIVED rides  
- Adding `state + arrivedAt` index (belongs with future NO_SHOW)

---

## 20. Open decisions

| # | Decision | Recommendation (not invented as product law) | Blocks |
|---|----------|-----------------------------------------------|--------|
| **D1** | Wait-clock field name & set point | **`arrivedAt` set once on `markArrived`** | Full NO_SHOW sweeper |
| D2 | NO_SHOW fee | Defer; when NO_SHOW ships, default **no payment writes** / fee null unless product freezes policy | Full NO_SHOW fee behavior |
| D3 | History mapping for `NO_SHOW` | Defer; likely `status=all` only (like `EXPIRED`) | List filters for NO_SHOW |
| D4 | `noShowCount` increment party | Defer entirely from first NO_SHOW slice | Matching metrics |
| D5 | `ride.no_show` payload fields | Defer to NO_SHOW phase; minimal ids + from/to + arrivedAt + reason | Event consumers |
| D6 | Legacy rides without `arrivedAt` | Defer backfill; NO_SHOW sweeper must define skip-vs-backfill later | Covering old ARRIVED rows |
| D7 | Expand active-assignment `in` states | Optional sibling; include through `RIDE_COMPLETED`? | Not blocking 2L |

**Phase 2L implementation may proceed only if D1 is accepted.** D2–D7 remain open for later NO_SHOW / guard work and must not be silently coded in 2L.

---

## 21. Risks

| Risk | Mitigation |
|------|------------|
| Treating 2L as “almost NO_SHOW” and sneaking state/sweeper | Hard non-goals + DoD |
| Using `updatedAt` as wait clock later | Explicitly reject; require `arrivedAt` |
| Overwriting `arrivedAt` on retries | Immutability invariant + tests |
| Schema/doc drift | Update schema in implementation phase, not here |
| Assuming proximity now required | Out of scope; keep tap arrive |

---

## 22. Implementation prerequisites

1. Approve **D1** (`arrivedAt` on arrive).  
2. No new infra.  
3. No index deploy for 2L.  
4. Flutter field optional but recommended for DTO parity.  
5. Closure doc after live proof.

**Not prerequisites:** payments, GPS, Redis, FCM, ratings API freeze, NO_SHOW product fee freeze.

---

## 23. FINAL VERDICT

# READY FOR PHASE 2L IMPLEMENTATION

### Exact implementation boundary

**Phase 2L — Arrive wait-clock (`arrivedAt`) persistence**

Implement **only**:

- Durable `rides.arrivedAt` set once on `DRIVER_EN_ROUTE → DRIVER_ARRIVED`  
- Immutability + existing arrive authz/idempotency/version semantics  
- DTO exposure of `arrivedAt`  
- Tests + live Firestore proof + regressions  

**Do not implement:** `NO_SHOW`, no-show sweeper, `ride.no_show`, fees, ratings, history enum changes, GPS, Redis/RTDB/FCM, dispatch, active-assignment expansion (unless separately approved as tiny sibling), Flutter UI, Phase 2M+.

### Explicit posture on NO_SHOW

NO_SHOW remains the **correct subsequent ride-domain timer terminal** after 2L (mirrors 2J/2K pattern), but is **not** Phase 2L because wait-clock field, fee, history, and metric side effects are not fully frozen. Phase 2L exists specifically to freeze D1 without inventing the rest.

---

### Hard stop

- Production code **not** modified  
- No migrations / indexes / endpoints / states added by this investigation  
- Phase 2L **not** implemented  
- ADRs **not** modified  
