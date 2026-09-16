# Phase 2M — Architecture Investigation: NO_SHOW Readiness

**Status:** INVESTIGATION ONLY (no production code modified)  
**Date:** 2026-09-10  
**Prior phase:** Phase 2L CLOSED — durable `rides.arrivedAt` wait-clock  
**Prerequisite docs:** `docs/ORA_STATE_MACHINE.md`, `docs/product/ride-lifecycle.md`, `docs/architecture-final/03-state-machines.md`, `docs/implementation/phase-02l-*`, Phase 2J/2K sweeper patterns

---

## 1. Current verified baseline

Inspected **source**, not closure docs alone.

### Ride states (code)

`backend/auth-service/src/rides/types.ts` — `RIDE_STATES`:

```text
SEARCHING | OFFERS_AVAILABLE | DRIVER_ASSIGNED | DRIVER_EN_ROUTE |
DRIVER_ARRIVED | RIDE_STARTED | RIDE_COMPLETED | RIDE_CLOSED |
CANCELLED | EXPIRED
```

**`NO_SHOW` is absent** from `RIDE_STATES`, `state_machine.ts`, routes, outbox writers, Flutter, and all of `backend/auth-service/src/**` / `mobile/**` (repo search: zero matches).

### State machine gates (code)

| Gate | Contents | File |
|------|----------|------|
| `EXPIRABLE` | `SEARCHING`, `OFFERS_AVAILABLE` | `state_machine.ts` |
| `CANCELLABLE_POST_ASSIGN` | `DRIVER_ASSIGNED` … `RIDE_STARTED` (**includes `DRIVER_ARRIVED`**) | same |
| Aggregate `TERMINAL` | `CANCELLED`, `EXPIRED`, `RIDE_CLOSED` only | same |
| Close | `RIDE_COMPLETED` → `RIDE_CLOSED` only | `assertCloseable` |
| Progression | Exact `from` match via `assertProgression` | same |

### Phase 2L `arrivedAt` — **verified present**

| Fact | Evidence |
|------|----------|
| `RideDoc.arrivedAt: string \| null` | `types.ts` |
| Create sets `arrivedAt: null` | `ride_service.ts` |
| `markArrived` → `setArrivedAt: true` | `ride_service.ts` |
| Set once in progression txn: `if (setArrivedAt && ride.arrivedAt == null)` | `ride_service.ts` |
| `publicRide` exposes `arrivedAt` | `ride_service.ts` |
| Flutter `Ride.arrivedAt` + parse | `domain/entities/ride.dart`, `ride_remote_data_source.dart` |
| Schema documented | `docs/database/firestore-schema.md` |
| Index `state + arrivedAt` | **Not** in `firestore.indexes.json` |

### Lifecycle ops today (relevant to NO_SHOW races)

| Op | From → To | Actor | Touches `arrivedAt`? |
|----|-----------|-------|----------------------|
| Arrive | `EN_ROUTE` → `ARRIVED` | Assigned driver | Sets once |
| Start | `ARRIVED` → `STARTED` | Assigned driver | Preserves |
| Complete | `STARTED` → `COMPLETED` | Assigned driver | Preserves |
| Close | `COMPLETED` → `CLOSED` | Passenger or assigned driver | Preserves |
| Cancel (post-assign) | `ASSIGNED`\|`EN_ROUTE`\|`ARRIVED`\|`STARTED` → `CANCELLED` | Passenger or assigned driver | Preserves if set; never invents |
| Ride expire | `SEARCHING`\|`OFFERS_AVAILABLE` → `EXPIRED` | Worker | N/A (pre-assign) |
| Offer expire | `PENDING` → `EXPIRED` | Worker | N/A |

### Existing sweeper pattern (2J/2K)

| Concern | Ride expire (2J) | Offer expire (2K) |
|---------|------------------|-------------------|
| Auth | `X-Ora-Worker-Token` on `/v1/internal/*` | same |
| Routes | `POST /rides/expire-sweep` | `POST /rides/offer-expire-sweep` |
| Batch | default **100**, max **200** | same |
| Per-doc txn | re-read; state + due check; version +1; outbox | state-idempotent |
| Idempotency | `already_expired` short-circuit (no Idempotency-Key) | same |
| Causation | `expire:{rideId}` | `expire-offer:{offerId}` |

### Doc vs code contradictions (do not “fix” in 2M)

| Topic | Authoritative docs | Implemented code |
|-------|--------------------|------------------|
| Cancel taxonomy | SM: `DRIVER_CANCELLED` / `PASSENGER_CANCELLED` | Single **`CANCELLED`** + `cancelledBy` |
| Arrive auth | Geofence / proximity in SM / arch-final | Tap-authoritative arrive (no GPS gate) |
| Cancel fee after ARRIVED | Product: fee if policy | Always `cancellationFeeMinor: 0` today |
| Terminal set | SM includes `NO_SHOW` | Code `TERMINAL` lacks `NO_SHOW` |
| Event naming | Product table: `driver.arrived` | Code: `ride.driver.arrived` |

**Implication:** Phase 2M must follow **implemented** cancel/progression taxonomy (`CANCELLED`, tap arrive) while adding **documented** `NO_SHOW` as a new terminal — not reopening split-cancel or GPS.

---

## 2. Authoritative NO_SHOW contract

### Frozen in product / SM docs

From `docs/ORA_STATE_MACHINE.md`:

| Element | Quote / rule |
|---------|----------------|
| State meaning | *“NO_SHOW \| Passenger did not board within wait time”* |
| Transition | `DRIVER_ARRIVED → NO_SHOW` *(server; wait timer exceeded)* |
| Actor | *“Any → NO_SHOW \| Server (Cloud Scheduler) \| Timer after DRIVER_ARRIVED”* |
| Terminal | *“NO_SHOW → ANY (terminal; except admin correction)”* |
| TTL table | *“DRIVER_ARRIVED (waiting for passenger) \| 5 minutes \| → NO_SHOW”* |

From `docs/product/ride-lifecycle.md`:

| Element | Rule |
|---------|------|
| Server path | *“Server \| DRIVER_ARRIVED wait TTL \| NO_SHOW”* |
| Wait start | *“`driver.arrived` … Wait timer starts”* (product naming; code event is `ride.driver.arrived`) |

From `docs/architecture-review/event-contracts.md`:

- Required durable type list includes **`ride.no_show`**
- **No payload schema** for `ride.no_show` (name only)

From `docs/architecture-final/03-state-machines.md`:

- Terminals include `NO_SHOW`
- *“DRIVER_ARRIVED wait TTL → NO_SHOW”*

### Not present in code

No state, gate, route, sweeper, event writer, Flutter handling, or constant `NO_SHOW_WAIT_TTL_MS`.

---

## 3. Wait-clock contract

### Authoritative clock field

**`rides.arrivedAt`** (Phase 2L) is the only safe wait-clock start.

- Set once on `DRIVER_EN_ROUTE → DRIVER_ARRIVED`
- Immutable thereafter
- Server ISO string (same convention as `startedAt` / `completedAt`)
- **Must not** use `updatedAt` (any later mutation would move the clock)

### Duration

**Frozen:** **5 minutes** (`docs/ORA_STATE_MACHINE.md` §8).

Do **not** invent another duration. Code already has `RIDE_SEARCH_TTL_MS = 5 * 60 * 1000` for search TTL; NO_SHOW wait is the same **duration value** by SM, but is a **separate policy** keyed off `arrivedAt`, not `expiresAt`.

### Eligibility boundary (recommended alignment with 2J)

Mirror ride expiry’s `expiresAt <= now` semantics:

```text
eligible iff:
  state == DRIVER_ARRIVED
  AND arrivedAt != null
  AND arrivedAt <= (now - 5 minutes)
```

Equivalently: `now >= arrivedAt + 5m`, **inclusive at the exact boundary**.

**OPEN only if product rejects inclusive-at-boundary**; otherwise this matches existing sweeper due semantics and is the consistent choice.

---

## 4. State transition contract

### Allowed

```text
DRIVER_ARRIVED → NO_SHOW   (server worker only; wait elapsed)
```

### Forbidden (once `NO_SHOW` exists)

| Transition | Reason |
|------------|--------|
| `NO_SHOW` → anything (except future admin-only) | SM terminal |
| `NO_SHOW` → `RIDE_CLOSED` | Not in SM; close only from `RIDE_COMPLETED` |
| `NO_SHOW` → `CANCELLED` / `COMPLETED` / `STARTED` | Terminal + progression gates |
| Client/public API → `NO_SHOW` | Actor is server scheduler |
| Pre-`ARRIVED` → `NO_SHOW` | Wrong from-state |
| `ARRIVED` with null/`missing` `arrivedAt` → `NO_SHOW` | No authoritative clock (see §11) |

### Concurrent legal siblings while still `DRIVER_ARRIVED`

Still legal **before** NO_SHOW wins:

- Passenger/driver **cancel** → `CANCELLED` (code today)
- Driver **start** → `RIDE_STARTED`

NO_SHOW must lose cleanly to those (see concurrency matrix).

---

## 5. Actor / authorization

| Actor | May trigger NO_SHOW? |
|-------|----------------------|
| Passenger | **No** public endpoint |
| Driver | **No** public endpoint |
| User Firebase token | **No** |
| Internal worker (`X-Ora-Worker-Token`) | **Yes** — only path |

**Preserve:** server/timer-controlled (Cloud Scheduler → internal sweep), same auth middleware as 2J/2K (`middleware/internal_worker.ts` + `ORA_INTERNAL_WORKER_TOKEN`).

**Do not invent** passenger/driver “mark no-show” APIs.

---

## 6. Terminal semantics

| Question | Answer from SM + code patterns | Confidence |
|----------|--------------------------------|------------|
| Is NO_SHOW terminal? | **Yes** — SM: `NO_SHOW → ANY` forbidden | Frozen |
| Transition to `RIDE_CLOSED`? | **No** | Frozen |
| Transition to `CANCELLED`? | **No** (after NO_SHOW commits) | Frozen |
| Transition to `COMPLETED` / `STARTED`? | **No** | Frozen |
| Start after NO_SHOW? | Reject `STATE_CONFLICT` | Required gate |
| Close after NO_SHOW? | Reject (close expects `RIDE_COMPLETED`) | Required gate |
| Cancel after NO_SHOW? | Reject (must not be in `CANCELLABLE_POST_ASSIGN`) | Required gate |
| `closedAt`? | Remains **null** (never closed) | Consistent with `EXPIRED`/`CANCELLED` |
| History representation? | **Not frozen** — see §10 |

**Contradiction note:** Product cancel table discusses fees for passenger cancel after arrived; that is **cancel**, not NO_SHOW. NO_SHOW is a **separate** server terminal.

---

## 7. Payment / fee decision

### What is frozen?

- Payment docs (`docs/product/payment-flow.md`) define **cancellation** fee *examples* (“Cancel after arrived \| Higher fee if policy enabled”).
- **No NO_SHOW fee row** exists.
- ADR-010: ledger is financial truth — **do not invent** ledger writes.
- ADR-008: server enforces locked SM — do not invent payment coupling into ride SM.
- Today’s cancel path sets `cancellationFeeMinor: 0` without a FeePolicy engine.

### Safe architecture posture (does not invent a fee)

Phase 2M **can** ship with:

- **Zero payment mutation**
- **No ledger write**
- **No fee calculation**
- Leave `cancellationFeeMinor` untouched / unused for NO_SHOW
- No payment-intent / wallet side effects

This is an **explicit non-goal**, not a product claim that “NO_SHOW is free forever.”

### Gate

| If… | Then… |
|-----|-------|
| Product accepts “no fee/ledger in first NO_SHOW slice” | D2 closable as **non-goal** |
| Product requires a NO_SHOW fee now | **NOT READY** until FeePolicy rule is frozen |

**Investigation recommendation:** treat D2 as **non-goal (zero payment mutation)** for Phase 2M — mirrors how 2J EXPIRED and current cancel avoid inventing fees.

**Status:** **OPEN until product/architecture explicitly accepts the non-goal** (cannot silently assume).

---

## 8. `noShowCount` / metrics decision

| Fact | Source |
|------|--------|
| Field on drivers schema | `docs/database/firestore-schema.md` |
| Used in matching scoring formula | `docs/algorithms/matching-engine.md` (`noshow_rate = noShowCount / totalRides`) |
| Written or read in backend/Flutter code | **Never** |
| Who increments on passenger no-board | **Undefined** (SM blames passenger non-boarding; metric lives on **driver** doc — ownership ambiguous) |

**Recommendation:** **Defer entirely** from Phase 2M. Do not increment `drivers.noShowCount` in the NO_SHOW transaction.

**Status:** **OPEN** if someone insists metrics ship with 2M; otherwise closable as **explicit non-goal**.

---

## 9. Event contract

### Frozen

- Event type name: **`ride.no_show`** (event-contracts required list)
- Must be written **atomically** with the state transition in the same Firestore transaction (ADR-005 outbox pattern; same as `ride.expired`)

### Not frozen

No payload schema in `event-contracts.md` (empty `payload: {}` example only; type listed without fields).

### Smallest safe shape (proposal — requires approval, not invented as product law)

Align with `ride.expired` payload style already in code:

```text
ride.expired payload (implemented):
  { rideId, fromState, toState, reason, expiresAt }
```

**Proposed `ride.no_show` payload (candidate freeze):**

```text
{
  rideId,
  fromState: "DRIVER_ARRIVED",
  toState: "NO_SHOW",
  reason: "arrived_wait_ttl_elapsed",
  arrivedAt   // authoritative wait-clock value from the ride doc
}
```

Envelope fields (`eventId`, `aggregateVersion`, `occurredAt`, `correlationId`, `causationId`, …) follow existing outbox conventions.

Optional fields (`passengerId`, `assignedDriverId`) appear on some events via aggregate lookup; they are **not** required by a written contract today — prefer **not** adding them unless approved (avoid speculative payload churn). Consumers can load the ride aggregate.

**Status:** **OPEN DECISION D5** — name frozen; payload shape needs explicit approval (recommendation above).

---

## 10. History contract

Phase 2I (`list_query.ts`):

```text
status ∈ { all, completed, cancelled }
completed → state in [RIDE_COMPLETED, RIDE_CLOSED]
cancelled → state == CANCELLED
all → no state filter
```

Documented: **`EXPIRED` appears only under `all`** (`phase-02i-ride-history-query.md`).

**NO_SHOW mapping:** unspecified in 2I / product.

### Safe posture (no new public filter)

| Filter | NO_SHOW visible? |
|--------|------------------|
| `status=all` | **Yes** (raw state on DTO) |
| `status=completed` | **No** |
| `status=cancelled` | **No** |

Do **not** invent `status=no_show` in Phase 2M.

**Status:** **OPEN DECISION D3** — recommendation: mirror `EXPIRED` (all-only). Closable as non-goal if accepted.

---

## 11. Legacy ride handling

Rides that reached `DRIVER_ARRIVED` **before** Phase 2L may have:

```text
state = DRIVER_ARRIVED
arrivedAt = null
```

Using `updatedAt` or `assignedAt` as a substitute clock would **invent** a wait start and is unsafe.

| Option | Pros | Cons |
|--------|------|------|
| **Skip** (do not NO_SHOW) | Safe; no invented clock | Legacy stuck ARRIVED until human cancel/start |
| Backfill `arrivedAt` | Enables coverage | Needs separate approved migration; invents historical times if inferred |
| Infer from another timestamp | Convenient | **Forbidden** without product freeze |

**Recommendation:** **Skip** rows with `arrivedAt == null` (or missing). Log/count as `skipped` reason `missing_arrivedAt`. No backfill in 2M.

**Does this block NO_SHOW?** Only if product requires covering legacy ARRIVED rows in the first slice. Otherwise skip is a safe non-goal.

**Status:** **OPEN DECISION D6**.

---

## 12. Sweeper design (if/when READY)

Reuse Phase 2J/2K architecture; do **not** invent a new collection.

### Single-ride operation `markNoShow` / `expireArrivedWait`

In one Firestore transaction:

1. Re-read `rides/{rideId}`
2. If `state == NO_SHOW` → `already_no_show` (no version bump, no second event)
3. If `state != DRIVER_ARRIVED` → `skipped` (`state_*`)
4. If `arrivedAt == null` → `skipped` (`missing_arrivedAt`)
5. If `arrivedAt > now - 5m` → `skipped` (`not_due`)
6. Else: `state = NO_SHOW`, `version = version + 1`, `updatedAt = now`
7. Outbox `ride.no_show` with approved payload; `causationId` e.g. `no-show:{rideId}`
8. Commit

**No offer fan-out required** (see §17): at `DRIVER_ARRIVED`, marketplace PENDING offers are already closed by assignment.

### Sweep `sweepNoShowRides`

```text
Query:
  collection rides
  where state == 'DRIVER_ARRIVED'
  where arrivedAt <= (now - 5m)
  limit N   // default 100, max 200 (match 2J/2K)
```

For each doc id → `markNoShow` in its own transaction (same as expire sweep).

Multi-pass: optional outer loop for large backlogs (2K-style), not required for correctness of a single due ride.

### Worker route (design only — do not add now)

```text
POST /v1/internal/rides/no-show-sweep?limit=
```

Worker token only; no user auth.

---

## 13. Firestore / index design

### Required composite index (not present today)

```text
Collection: rides
Fields: state ASC, arrivedAt ASC
```

Needed for:

```text
state == DRIVER_ARRIVED AND arrivedAt <= cutoff
```

**Do not add during investigation.** Adding the index is part of implementation scope when READY.

Existing related indexes: `state + expiresAt` (2J); history composites; **no** `state + arrivedAt`.

### Performance notes

- Bound every sweep (`limit ≤ 200`)
- One hot document per ride; contention only with concurrent start/cancel/NO_SHOW on same ride
- No unbounded collection scans
- `rides/{rideId}` remains source of truth

---

## 14. Transaction boundary

| Write | Same txn as state? |
|-------|--------------------|
| `state → NO_SHOW` | Yes |
| `version + 1` | Yes |
| `updatedAt` | Yes |
| `ride.no_show` outbox | Yes |
| Payment / ledger | **No** (non-goal) |
| `drivers.noShowCount` | **No** (non-goal) |
| Offer docs | **No** (none applicable) |
| `closedAt` | **No** (stays null) |
| `arrivedAt` | **Never rewritten** |

Separate transaction solely for the event is **forbidden**.

---

## 15. Idempotency

| Mechanism | Role |
|-----------|------|
| **State-based** | Primary — already `NO_SHOW` ⇒ success/no-op without bump/event |
| **Idempotency-Key** | **Not required** for worker path (same as 2J/2K expire) |
| Worker retry / duplicate sweep | Re-read → `already_no_show` |
| Timeout after commit | Next sweep sees `NO_SHOW` |
| Process restart | Safe; due query re-picks only still-`ARRIVED` rows |

**Invariants:** at most one `ride.no_show` outbox event; at most one version increment for the transition.

---

## 16. Versioning

NO_SHOW **must** increment `ride.version` by exactly **1** on the first successful transition — consistent with:

- 2G progression
- 2H close
- 2J EXPIRED

Already-`NO_SHOW` path: **no** second bump (mirror `already_expired`).

---

## 17. Offer interaction

At `DRIVER_ASSIGNED` / later, offer marketplace is closed (`TERMINAL_FOR_OFFERS` includes `DRIVER_ARRIVED`).

Selected offer is `SELECTED`; siblings `SUPERSEDED`/`EXPIRED`/`WITHDRAWN`.

**NO_SHOW must not introduce unnecessary offer writes.**

When adding `NO_SHOW` to code, update:

- `TERMINAL` (aggregate terminal)
- `TERMINAL_FOR_OFFERS` (include `NO_SHOW` so offers cannot reopen)
- Ensure cancel/progression/expire gates reject `NO_SHOW`

No PENDING cleanup pass analogous to 2J parent-EXPIRED is required for the happy path.

---

## 18. Concurrency matrix

All races share one ride document + Firestore transactions (re-read, conditional write). Loser observes new state and returns skip / `STATE_CONFLICT`.

| # | Race | Legal persisted outcome |
|---|------|-------------------------|
| 1 | NO_SHOW vs NO_SHOW | One transition; one version +1; one `ride.no_show`; other `already_no_show` |
| 2 | NO_SHOW vs cancel | **Either** `NO_SHOW` **or** `CANCELLED` — never both; never mixed clocks cleared |
| 3 | NO_SHOW vs start | **Either** `NO_SHOW` **or** `RIDE_STARTED` (+ `startedAt`); loser conflicts/skips |
| 4 | NO_SHOW vs complete | Complete illegal from `ARRIVED`; only relevant if start already won — NO_SHOW must skip non-ARRIVED |
| 5 | NO_SHOW vs close | Close only from `COMPLETED`; NO_SHOW never closes; if somehow raced, close loses on state |
| 6 | NO_SHOW vs ride expiry | Expiry only from `SEARCHING`/`OFFERS_AVAILABLE` — **disjoint**; both skip each other’s states |
| 7 | NO_SHOW vs worker retry | Second pass `already_no_show` |
| 8 | NO_SHOW vs stale client arrive/start | Client gets `STATE_CONFLICT` / wrong-from after NO_SHOW |
| 9 | NO_SHOW after timeout (due) | Eligible → transition |
| 10 | Multiple workers | Same as (1); contention may retry txn; still one winner |
| 11 | Process crash mid-txn | Atomic commit or rollback; no partial state+event |
| 12 | Firestore txn retry | Re-validate state/`arrivedAt`/due on each attempt |

**Cancel vs NO_SHOW detail:** Cancel is still legal while `state == DRIVER_ARRIVED`. Whichever txn commits first wins. If cancel wins, `arrivedAt` may remain set (immutability) under `CANCELLED` — that is **valid** (clock set, then cancelled), not a mixed illegal NO_SHOW state.

---

## 19. Failure / retry / offline

| Scenario | Protection |
|----------|------------|
| Worker timeout after commit | Next sweep: already NO_SHOW |
| Duplicate sweep | State idempotency |
| Server crash | Firestore txn atomicity |
| Txn retry | Re-check predicates |
| Emulator restart | Re-seed / re-sweep; no client clock |
| Stale mobile start after NO_SHOW | `STATE_CONFLICT` |
| Stale mobile cancel after NO_SHOW | Cancel gate rejects terminal |
| Outbox write failure | Same txn → whole NO_SHOW rolls back |
| Client cannot patch state | Rules: `rides` read/write false |

Offline client does not drive NO_SHOW; server remains authority.

---

## 20. Security

| Control | Status / requirement |
|---------|----------------------|
| No public NO_SHOW endpoint | Required |
| Worker token (`X-Ora-Worker-Token`) | Reuse 2J/2K |
| Token not via user auth | Existing middleware |
| Forged ride IDs | Per-doc re-read; missing → not found / skip |
| Cross-user | Worker is not user-scoped; must still only mutate due `DRIVER_ARRIVED` |
| Client cannot set `state` / `arrivedAt` | Rules deny |
| Worker cannot NO_SHOW wrong state / not-due | Txn predicates |
| Replay | State idempotency |
| IDOR on user APIs | Unchanged; no new user API |

---

## 21. Test plan (pre-implementation)

### Unit (MemoryDb)

1. Not yet eligible (`arrivedAt` within 5m) → skip / unchanged  
2. Exactly at boundary (`arrivedAt == now - 5m`) → eligible (if inclusive freeze accepted)  
3. Overdue → `NO_SHOW` + version +1 + one event  
4. Wrong state (e.g. `EN_ROUTE`, `STARTED`) → skip/reject  
5. Missing `arrivedAt` → skip  
6. Successful NO_SHOW payload/envelope  
7. Already NO_SHOW → no second bump/event  
8. Duplicate invocation  
9. Invalid actor (non-worker) if exposed via HTTP harness  
10. Version behavior  

### Live Firestore (emulator `127.0.0.1:8181`, inspect persisted docs)

1. Normal NO_SHOW persistence  
2. Exact 5-minute boundary  
3. Not-yet-due unchanged  
4. 2-way concurrent NO_SHOW (contention evidence)  
5. 10-way concurrent NO_SHOW (and 50-way **only if** same pattern as 2J/2K material benefit)  
6. NO_SHOW vs cancel  
7. NO_SHOW vs start  
8. NO_SHOW vs ride expiry (disjoint smoke)  
9. Worker retry / already NO_SHOW  
10. Duplicate event prevention  
11. Persisted state / version / outbox verification  

### Regression (must actually run — do not claim pass from inspection)

2G progression, 2H close, 2I list, 2J expire, 2K offer expire, **2L arrivedAt**.

---

## 22. Live Firestore proof plan

Harness pattern: clone 2J/2L concurrency scripts.

- Seed ride to `DRIVER_ARRIVED` with controlled `arrivedAt` (Admin write of clock for boundary tests **only in harness**, not production API)
- Invoke internal sweep with worker token
- Assert Firestore document + outbox
- Record `contendedTransactions` for multi-worker races

---

## 23. Regression plan

| Suite | Why |
|-------|-----|
| 2G | Start/cancel from ARRIVED still work; NO_SHOW must not break progression |
| 2H | Close path untouched |
| 2I | `all` still returns new terminal; filters unchanged |
| 2J | Expire sweeper unaffected |
| 2K | Offer expire unaffected |
| 2L | `arrivedAt` immutability under NO_SHOW (field preserved, not overwritten) |

---

## 24. Explicit non-goals (Phase 2M candidate)

Even if NO_SHOW implementation is later approved, the following remain **out of scope** unless separately frozen:

- Payment / fees / ledger / wallet  
- `drivers.noShowCount` increments  
- Ratings  
- GPS / proximity / Maps  
- Redis / RTDB / FCM / dispatch / go-online  
- Active-assignment guard expansion  
- Flutter UI redesign / admin / support tools  
- Historical `arrivedAt` backfill  
- New history `status=` values  
- Public passenger/driver NO_SHOW APIs  
- Split cancel taxonomy (`DRIVER_CANCELLED` / `PASSENGER_CANCELLED`)  
- Unrelated refactoring  
- Future states beyond `NO_SHOW`

---

## 25. Open decisions

| ID | Decision | Frozen? | Blocking? | Recommended resolution for 2M |
|----|----------|---------|-----------|-------------------------------|
| **D1** | Wait-clock field = `arrivedAt` | **Yes (2L)** | No | Done |
| **D2** | NO_SHOW fee / payment | **No** | **Yes** until accepted as non-goal | Zero payment/ledger mutation |
| **D3** | History `status=` mapping | **No** | **Yes** until accepted | Appear under `all` only (like `EXPIRED`); no new filter |
| **D4** | `noShowCount` increment | **No** | **Yes** if required in-txn; else non-goal | Defer; do not write |
| **D5** | `ride.no_show` payload | Name only | **Yes** | Minimal: `rideId, fromState, toState, reason, arrivedAt` |
| **D6** | Legacy `ARRIVED` + null `arrivedAt` | **No** | **Yes** for sweeper semantics | Skip (`missing_arrivedAt`); no backfill |
| **D7** | Exact inclusive boundary `arrivedAt <= now-5m` | Implied by 2J pattern | Soft | Affirm inclusive due semantics |
| **D8** | Worker route path name | Convention only | Soft | `POST /v1/internal/rides/no-show-sweep` |

**D1 is closed. D2–D6 remain required freezes (as product rules or explicit non-goals) before implementation may start.**

---

## 26. Risks

| Risk | Mitigation |
|------|------------|
| Inventing a NO_SHOW fee | Hard non-goal until FeePolicy exists |
| Using `updatedAt` as clock | Forbidden; use `arrivedAt` only |
| NO_SHOW without index | Query fails / full scan — index required at implement time |
| Cancel vs NO_SHOW confusion in UX | Distinct states; history all-only |
| Incrementing `noShowCount` wrongly | Defer metrics |
| Treating SM split-cancels as required | Stay on implemented `CANCELLED` |
| Covering legacy null clocks incorrectly | Skip until backfill approved |
| Shipping GPS “for arrive authenticity” | Out of scope; NO_SHOW write does not need GPS |

---

## 27. Exact implementation boundary (when READY)

**In scope for a future Phase 2M implementation (after decisions freeze):**

1. Add `NO_SHOW` to `RIDE_STATES` + terminal / offer-terminal / cancel-illegality gates  
2. `markNoShow` transactional write + `ride.no_show` outbox  
3. Bounded sweeper + worker route + auth reuse  
4. Composite index `state + arrivedAt`  
5. DTO exposure of new state via existing `publicRide`  
6. Flutter domain parse tolerance for state string (no UI)  
7. Unit + live + regression proofs per §§21–23  

**Out of scope:** everything in §24; ADRs unchanged; no production schema invention beyond documenting `NO_SHOW` state + index already implied by SM.

---

## 28. FINAL VERDICT

### What 2L unlocked

Phase 2L **did** freeze the missing wait-clock (**D1 / `arrivedAt`**). That was the primary technical blocker called out in the 2L investigation.

### What is still not frozen

NO_SHOW is **not** automatically ready:

- Fee/payment behavior (**D2**) — no authoritative NO_SHOW fee rule  
- History mapping (**D3**) — unspecified beyond “probably like EXPIRED”  
- `noShowCount` (**D4**) — schema/scoring only; ownership undefined  
- Event payload (**D5**) — type name only  
- Legacy null `arrivedAt` (**D6**) — skip vs backfill undecided  

These are **domain decisions**, not coding difficulties. Implementation is pattern-ready (2J/2K), but inventing any of D2–D6 would violate ADR-010 / investigation rules.

### Verdict

```text
NOT READY — ARCHITECTURE DECISIONS REQUIRED
```

**To reach `READY FOR PHASE 2M IMPLEMENTATION`, explicitly approve (as product rules or signed non-goals):**

1. **D2** — zero payment/ledger/fee mutation in 2M  
2. **D3** — `NO_SHOW` visible under `status=all` only; no new filter  
3. **D4** — do not increment `noShowCount` in 2M  
4. **D5** — freeze `ride.no_show` payload (recommended minimal shape in §9)  
5. **D6** — skip `DRIVER_ARRIVED` rows with null/missing `arrivedAt`  
6. **D7** — affirm inclusive due boundary `arrivedAt <= now - 5m`  

Until those are recorded as accepted freezes, **do not implement** `NO_SHOW`, sweeper, index, or production schema/state-machine changes.

---

**HARD STOP.** No production code, state machine, sweeper, index, ADR, or schema was modified in this investigation.
