# Phase 2J — Architecture / Next-Slice Investigation

**Date:** 2026-09-09  
**Status:** INVESTIGATION ONLY — no production code modified  
**Verdict:** see §27

---

## 1. Executive summary

Phases **2C–2I** are closed. The modular monolith now owns:

- Auth / onboarding  
- Full ride marketplace + post-assignment progression through **`RIDE_CLOSED`**  
- Authenticated ride history reads (`GET /v1/rides`) against `rides/{rideId}`

The ride **happy-path write chain is complete**. Remaining MVP work splits into three classes:

| Class | Examples | Infra weight |
|-------|----------|--------------|
| **A. Ride SM timer terminals still reserved** | `EXPIRED` write-path sweeper; later `NO_SHOW` | Scheduler/worker only |
| **B. New aggregates** | Ratings; cash/ledger payments | Firestore + new APIs (payments = large) |
| **C. Infra-heavy product surfaces** | Driver go-online, dispatch, Maps/GPS, RTDB, Redis, FCM consumers | Multi-phase platforms |

**Recommended Phase 2J:** the smallest coherent dependency-safe slice is:

> **Ride EXPIRED terminal write-path (search / offers-available TTL sweeper)**  
> Persist `SEARCHING | OFFERS_AVAILABLE → EXPIRED`, emit contracted `ride.expired`, optionally durable-mark pending offers — **without** Maps, Redis, RTDB, FCM, payments, ratings, dispatch, UI, or `NO_SHOW`.

This closes the last **already-reserved** ride-aggregate terminal that product + SM already require, using fields and TTLs already written by 2E–2F.

---

## 2. Verified current state (2C–2I)

| Phase | Status | Closed capability |
|-------|--------|-------------------|
| 2C | CLOSED | Auth OTP → register → profile → home |
| 2D | CLOSED (contract) | Ride domain / SM / concurrency gates |
| 2E | CLOSED | Create/get; offers; select; pre-assign cancel; assignment txn |
| 2F | CLOSED — live proven | Offer uniqueness / withdraw / read-boundary offer expiry |
| 2G | CLOSED — live proven | EN_ROUTE → ARRIVED → STARTED → COMPLETED; post-assign cancel |
| 2H | CLOSED — live proven | COMPLETED → CLOSED |
| 2I | CLOSED — live proven | `GET /v1/rides` history |

### Implemented lifecycle (code)

```
SEARCHING → OFFERS_AVAILABLE → DRIVER_ASSIGNED
  → DRIVER_EN_ROUTE → DRIVER_ARRIVED → RIDE_STARTED
  → RIDE_COMPLETED → RIDE_CLOSED
  | CANCELLED | EXPIRED (state reserved; no sweeper writer)
```

Auth-service mounts only `/v1/auth` and `/v1/rides`. Flutter ride feature is domain/data only (no ride UI). Driver/maps/payments/safety Flutter features remain stubs.

---

## 3. What was inspected

| Area | Paths |
|------|-------|
| Phase docs | `docs/implementation/phase-02c*` … `phase-02i*` |
| Locked SM | `docs/ORA_STATE_MACHINE.md`, `docs/architecture-final/03-state-machines.md` |
| ADRs | `docs/architecture-final/ADRs/ADR-003` … `ADR-011`, esp. ADR-004/008/010/011 |
| Events | `docs/architecture-review/event-contracts.md` |
| Dispatch / payments | `dispatch-wave-design.md`, `payment-ledger-design.md`, `system-invariants.md` |
| APIs | `docs/api/ride-api.md`, `docs/architecture-final/04-api-contracts.md` |
| Inventory | `docs/architecture-final/02-feature-inventory.md`, `21-mvp-vs-post-mvp.md` |
| Schema / indexes | `docs/database/firestore-schema.md`, `indexes.md`, root `firestore.indexes.json` |
| Ride code | `backend/auth-service/src/rides/*` (types, SM, service, routes, eligibility, offer_lifecycle) |
| Flutter | `mobile/lib/features/{auth,ride,passenger,driver,maps,payments,safety}` |
| Later phase stubs | `docs/implementation/phase-04` … `phase-11` (NOT STARTED) |

No production code, Flutter, indexes, collections, states, or contracts were modified in this investigation.

---

## 4. Locked architecture constraints

| Constraint | Source | Implication for 2J |
|------------|--------|---------------------|
| Server-authoritative ride SM | ADR-008, ORA_STATE_MACHINE | Timer terminals must be server-written, not client |
| Ride ≠ payment aggregate | ADR-008, Case 28 | Do not start payments to “finish” rides |
| Firestore assignment authority | ADR-003 | Dispatch/Redis never assigns |
| Redis GEO is optimization | ADR-004 | Go-online/dispatch blocked without Redis design |
| Location = RTDB + Redis | ADR-011 | Maps/GPS/live trip blocked |
| Durable outbox | ADR-005 | Sweeper should write `ride.expired` atomically |
| Durable idempotency | ADR-006 | Worker/API mutations need safe retry semantics |
| Immutable ledger | ADR-010 | Payments are a separate bounded context |

---

## 5. Remaining ride-capability gap analysis

| Capability | Contract | Code today |
|------------|----------|------------|
| Create → assign → progress → close | SM + ride-api | **Done (2E–2H)** |
| History list | ride-api | **Done (2I)** |
| Ride EXPIRED write-path | SM timeout table; `ride.expired` event; inventory #32 | State + TTL fields exist; **no sweeper** |
| Offer EXPIRED durable write | `ride.offer.expired`; inventory #31 | **Read/mutation boundary only** (`offer_lifecycle.ts`) |
| NO_SHOW | SM `DRIVER_ARRIVED` wait TTL; `ride.no_show` | **State absent** in `types.ts` |
| Proximity on arrive/start/complete | SM / ride-api `PROXIMITY_VIOLATION` | Stubbed; no GPS |
| Distinct DRIVER_/PASSENGER_CANCELLED | Full SM | Collapsed to `CANCELLED` + `cancelledBy` (conscious 2E/2G) |
| Active-trip discovery UX | Product | Partial via `GET /v1/rides?status=all` only |
| `en-route` / `close` in ride-api.md | Implemented | **Doc drift** (hygiene, not a phase) |

---

## 6. Driver system status

| Item | Status |
|------|--------|
| Approved-driver eligibility for offers | Stub: `role=driver` + `driverStatus=approved` |
| Go-online / offline APIs | Contracted (`04-api-contracts`); **not implemented** |
| Presence / availabilityState | Requires RTDB + Firestore driver docs |
| Flutter `features/driver` | Stub: “Phase 6+” |
| Nearby drivers | Requires Redis GEO |

**Prerequisite for dispatch:** go-online + location freshness. **Not dependency-safe for 2J.**

---

## 7. Dispatch / matching status

Wave design exists (`dispatch-wave-design.md`: 5/10/15). Inventory treats discovery/delivery as MVP.  
Code: **no wave worker, no Redis GEO query, no request fan-out.**  
Eligibility comment explicitly: “No Redis/GEO/dispatch membership yet.”

**Blocked on Phase 6/8-class infra. Reject as 2J.**

---

## 8. Location / realtime / RTDB / Redis status

| Surface | Status |
|---------|--------|
| RTDB schemas | Documented; no runtime wiring |
| Redis GEO | ADR-004; no code |
| `POST /location/update` | Contracted; missing |
| Flutter maps | Stub Phase 4+ |
| Live trip projection | Phase 9–10 docs; not started |

**Any slice needing live location or presence is not 2J-safe.**

---

## 9. Notifications / FCM status

Outbox is **write-only** through 2I. Event contracts assume future Pub/Sub → RTDB/FCM consumers.  
No FCM tokens API, no push worker.

**Outbox consumer / FCM is Phase 9-class. Reject as 2J primary.**

---

## 10. Payments / wallet / ledger / earnings / receipts status

| Item | Status |
|------|--------|
| `agreedFareMinor` on assigned rides | Present |
| `paymentIntentId` | Always null; must stay null under ADR-008 until payments |
| Payment APIs | Contracted; unimplemented |
| Ledger / wallet / payout / refund | Design docs only |
| Flutter payments | Stub Phase 11+ |
| Receipts | Product/support UX; not implemented |

Cash skeleton is product-critical eventually but is a **new bounded context**, not a ride-module continuation. High rework if rushed into 2J without ledger invariants.

**Reject as 2J primary.**

---

## 11. Ratings status

| Item | Status |
|------|--------|
| Inventory | Ratings = **MVP**; reviews POST-MVP |
| Schema | `ratings` collection documented |
| API | **Not frozen** in `04-api-contracts.md` / ride-api |
| Code / Flutter | None |
| Prerequisite | COMPLETED/CLOSED rides exist (**satisfied by 2H**) |

Ratings is a strong **alternate** small slice (new aggregate, low infra). It does **not** finish the reserved ride SM terminal hole.

---

## 12. Support status

Support / admin force-transition / suspend: contracted as admin surfaces; POST-MVP for support UI.  
**Out of scope for 2J.**

---

## 13. Pricing status

Create-ride uses fixture `pricingSnapshots`. Live `POST /pricing/estimate` needs routes/distance (Maps).  
**Blocked on Phase 4/5. Reject as 2J.**

---

## 14. Remaining state-machine terminals

From `ORA_STATE_MACHINE.md` timeout table vs code:

| Transition | Contract | Code |
|------------|----------|------|
| SEARCHING → EXPIRED (5 min) | Required | **Missing writer** |
| OFFERS_AVAILABLE → EXPIRED (3 min / no select) | Required | **Missing writer** (ride `expiresAt` set at create; offer TTLs separate) |
| DRIVER_ARRIVED → NO_SHOW (5 min) | Required | **NO_SHOW state missing** |
| DRIVER_ASSIGNED no-movement → DRIVER_CANCELLED | Required in full SM | Not implemented; cancel path only |
| COMPLETED → CLOSED | Required | **Done (2H)** |

`EXPIRED` is already in `RIDE_STATES` and `TERMINAL`. Select/offer paths already reject past `expiresAt` in places, but rides can remain forever in SEARCHING/OFFERS_AVAILABLE without a durable EXPIRED transition or `ride.expired` outbox event.

Schema already anticipates sweeper index: `state + expiresAt` (`firestore-schema.md`). **Not present** in deployed `firestore.indexes.json` (explicitly deferred by 2I).

---

## 15. Remaining MVP capability inventory (post-2I)

Open MVP (selected):

1. Ride expiration sweeper  
2. Offer expiration durable write (partially covered by read-boundary)  
3. Driver online/offline + location  
4. Dispatch / request delivery  
5. Maps / geocoding / routes / ETA  
6. Live pricing estimate  
7. Proximity checks  
8. Active trip RTDB  
9. Payments / ledger / earnings / refunds  
10. Ratings  
11. FCM / realtime consumers  
12. Safety/SOS (later UX)  
13. Backend jobs beyond expiry  

POST-MVP: broad search, support UI, trip sharing, review depth, etc.

---

## 16. Dependency map

```text
[Auth 2C] ─┬─► [Ride core 2E–2H] ─┬─► [History 2I] ──► (done)
           │                      ├─► [EXPIRED sweeper] ──► recommended 2J
           │                      ├─► [NO_SHOW] ── needs new state + arrived wait policy
           │                      └─► [Ratings] ── needs API freeze; no infra
           │
           ├─► [Maps/GPS Ph4] ─┬─► [Live pricing Ph5]
           │                   └─► [Proximity / trip UX Ph10]
           │
           ├─► [Driver go-online Ph6] ─► needs Redis+RTDB
           │         └─► [Dispatch waves Ph8] ─► needs FCM/RTDB
           │
           ├─► [Outbox consumers Ph9] ─► Pub/Sub + FCM
           │
           └─► [Payments Ph11] ─► ledger; ADR-008 separate from ride SM
```

**Safe edges from current tip:** EXPIRED sweeper; Ratings (after API lock); doc hygiene for en-route/close.  
**Unsafe edges:** anything requiring Redis, RTDB, Maps SDKs, PSP, or FCM as a hard prerequisite.

---

## 17. Candidate slice comparison

| ID | Slice | Prereqs met? | New infra | Closes SM hole? | Rework risk | 2J fit |
|----|-------|--------------|-----------|-----------------|-------------|--------|
| **J1** | Ride EXPIRED sweeper + `ride.expired` | Yes (TTL fields, state exists) | Scheduler/worker + `state+expiresAt` index | **Yes** | Low–medium | **Recommended** |
| **J1b** | + durable offer EXPIRED writes / `ride.offer.expired` | Yes (read-boundary today) | Same worker | Partial | Low | Optional sibling |
| **J2** | NO_SHOW sweeper | Arrived exists; **state missing** | Scheduler + new enum/gates | Yes (different hole) | Medium (SM expansion) | After J1 |
| **J3** | Ratings aggregate | CLOSED/COMPLETED exist | Firestore collection + API | No | Medium (API not frozen) | Strong alternate |
| **J4** | Cash payment skeleton | Fare exists | Payment module + ledger | No | High | Phase 11 start |
| **J5** | Active-ride filter UX/API | 2I list | None | No | Low | Too thin / product-only |
| **J6** | Outbox → FCM | Events exist | Pub/Sub/FCM | No | High | Phase 9 |
| **J7** | Driver go-online | Auth | Redis+RTDB | No | High | Phase 6 |
| **J8** | Dispatch waves | J7 + location | Redis/RTDB/FCM | No | High | Phase 8 |
| **J9** | Maps/GPS + proximity | — | Maps SDKs | No | High | Phase 4/10 |
| **J10** | Live pricing | Maps/routes | Pricing service | No | High | Phase 5 |
| **J11** | First ride/history UI | 2I data | Flutter UI | No | Product | Not backend SM |
| **J12** | Doc sync en-route/close | — | Docs only | No | None | Hygiene, not a phase |

---

## 18. Prerequisites analysis (recommended J1)

Already present:

- `EXPIRED` in `RideState` and `TERMINAL`  
- `rides.expiresAt` set on create (`RIDE_SEARCH_TTL_MS = 5m`)  
- Select rejects expired search window in assignment path  
- Outbox pattern + idempotency patterns from 2E–2H  
- Contracted event `ride.expired`  
- Documented index shape `state + expiresAt`

Must add in implementation phase (not now):

- Worker or scheduled invoker (Cloud Scheduler → Cloud Run job/endpoint)  
- Composite index `state ASC + expiresAt ASC` (and possibly offer expiry index)  
- Transactional transition rules: only from `SEARCHING` / `OFFERS_AVAILABLE`  
- Concurrency: sweeper vs select/cancel races  
- Auth for sweeper endpoint (service identity), not end-user  

Optional sibling:

- Persist offer `EXPIRED` + `ride.offer.expired` when ride expires or offer TTL elapses  

---

## 19. Future rework risk analysis

| If we choose… | Future rework |
|---------------|---------------|
| **J1 EXPIRED now** | Low. Unblocks truthful history/`status=all`, marketplace cleanup, later notification consumers |
| Ratings before API freeze | Medium. May churn DTO/authz once contracts land |
| NO_SHOW before EXPIRED | Medium. Introduces new terminal while marketplace expiry still false |
| Payments now | High. Forces ledger/PSP decisions; risks violating ADR-008 boundaries |
| Dispatch/Maps now | High. Pulls Redis/RTDB/Maps; stalls ride-domain completion |
| Fold EXPIRED into client cancel only | High. Violates SM timeout semantics |

**Potential future rework explicitly called out:** if product later demands distinct `PASSENGER_CANCELLED` / `DRIVER_CANCELLED` / `NO_SHOW` terminals, cancel taxonomy may widen — **do not invent that in 2J**. Keep single `CANCELLED` + add only EXPIRED write-path.

---

## 20. Recommended Phase 2J boundary

### In scope

1. Server-side expiry of rides in `SEARCHING` or `OFFERS_AVAILABLE` whose `expiresAt <= now` → durable `EXPIRED`.  
2. Single version bump + `updatedAt`; terminal immutability via existing gates.  
3. Atomic outbox `ride.expired` (payload: fromState, toState, reason/timeout).  
4. Safe concurrency vs passenger select / cancel / offer create.  
5. Required Firestore composite index(es) for sweeper queries.  
6. Invocation model: scheduled worker hitting an **internal** expire API or job entrypoint (not a public passenger/driver feature).  
7. Tests + emulator verification of query + transactional expire.  
8. Flutter: **none required** unless a tiny domain constant for `EXPIRED` already exists (no UI).  
9. Optional narrow sibling: durable offer expiry writes when ride expires (supersede/expire PENDING offers).

### Out of scope

- `NO_SHOW` / `DRIVER_CANCELLED` timers  
- Ratings, payments, wallet, ledger, earnings, receipts  
- Maps, GPS, proximity  
- RTDB, Redis, FCM, Pub/Sub consumers  
- Driver go-online, dispatch waves  
- Live pricing  
- Admin/support  
- Ride UI / navigation  
- Changing closed-phase assignment/offer/progression/close/history behavior except where expire races require correct conflict codes  

### Exact implementation boundary for the next prompt

**Phase 2J — Ride EXPIRED Sweeper / Terminal Write-Path**

Implement only durable `SEARCHING|OFFERS_AVAILABLE → EXPIRED` for timed-out rides on `rides/{rideId}`, with transactional safety, outbox `ride.expired`, sweeper indexes, and verification — no new product domains.

---

## 21. Why this recommendation

1. **SM honesty:** `EXPIRED` is reserved and terminal in code but never written by a sweeper — marketplace rides can leak forever.  
2. **Dependency-safe:** uses existing TTL fields; needs scheduler + index, not Redis/Maps/payments.  
3. **Contract-backed:** timeout table + `ride.expired` already locked.  
4. **Smallest coherent ride continuation:** finishes ride-aggregate timer semantics before opening new aggregates (ratings) or platforms (dispatch/payments).  
5. **Unblocks later work:** history filters, cleanup, and future FCM “search expired” notifications have a real state to key off.  
6. **Avoids ADR violations:** does not merge payment into ride lifecycle.

Ratings (J3) is the best **alternate** if product prioritizes post-trip loop over marketplace hygiene — but it leaves the EXPIRED hole open.

---

## 22. Explicit non-goals for Phase 2J

Maps, GPS, geofencing, proximity, RTDB, Redis, FCM, Pub/Sub consumers, driver go-online, dispatch/matching, live pricing, payments/wallet/ledger/earnings/receipts, ratings, support/admin, Cargo/Delivery, Flutter UI, `NO_SHOW` state introduction, redesign of 2E–2I APIs.

---

## 23. Risks

| Risk | Mitigation |
|------|------------|
| Sweeper vs select race | Firestore transaction; loser gets STATE_CONFLICT / already assigned semantics |
| Sweeper vs cancel race | Idempotent expire if already CANCELLED; don’t overwrite terminals |
| Wrong TTL semantics (search vs offer) | Expire **ride** on `rides.expiresAt`; treat offer TTLs separately or as sibling |
| Missing index in prod | Ship `state+expiresAt` with implementation; prove on emulator |
| Public expire endpoint abuse | Service auth only; never trust client “expire this ride” without actor rules |
| Over-scoping into NO_SHOW | Explicit non-goal |
| Doc drift (`ride-api.md` missing en-route/close) | Track as hygiene; not 2J DoD |

---

## 24. Implementation plan (next prompt only — do not execute here)

1. Add sweeper query + composite index `state + expiresAt`.  
2. Implement transactional `expireRide` (batch/page of due rides).  
3. Emit `ride.expired` outbox; bump version once.  
4. Wire Cloud Scheduler → internal job/route with service identity.  
5. Race tests: expire vs select, expire vs cancel, double-expire idempotency.  
6. Emulator verification of index + transitions.  
7. Optional: expire PENDING offers when ride expires.  
8. Closure doc `phase-02j-ride-expired-sweeper.md`.  
9. Regression 2E–2I.

---

## 25. Definition of Done (for recommended slice)

1. Due SEARCHING/OFFERS_AVAILABLE rides become durable `EXPIRED`.  
2. `ride.expired` outbox written atomically with the transition.  
3. Select/cancel races defined and tested.  
4. Indexes present and emulator-proven.  
5. No payments/Maps/Redis/RTDB/FCM/ratings/UI.  
6. 2E–2I regressions green.  
7. Terminal immutability preserved for EXPIRED.

---

## 26. Open questions

| # | Question | Recommendation |
|---|----------|----------------|
| 1 | Expire ride on `rides.expiresAt` only, or also force-expire when all offers past TTL while ride still OFFERS_AVAILABLE? | Prefer ride `expiresAt` as sole ride-terminal clock (already 5m from create); document offer TTL as offer-local |
| 2 | Include durable offer EXPIRED writes in 2J? | **Yes as optional sibling** if small; else immediate 2K micro-slice |
| 3 | Scheduler invoke internal HTTP vs Cloud Run job? | Prefer job/private route with service account; not end-user JWT |
| 4 | Should ratings be 2J instead? | Only if product explicitly prioritizes post-trip over marketplace expiry |
| 5 | Sync ride-api.md for en-route/close during 2J? | Allowed as docs hygiene; not required for sweeper DoD |
| 6 | Batch size / page limit for sweeper? | Cap (e.g. 100/run) — decide in implementation |

---

## 27. Final verdict

# READY FOR PHASE 2J IMPLEMENTATION

### Exact implementation boundary for the next prompt

**Phase 2J — Ride EXPIRED Sweeper / Terminal Write-Path**

Implement **only**:

- Durable transition `SEARCHING | OFFERS_AVAILABLE → EXPIRED` when `expiresAt <= now`  
- Transactional safety vs select/cancel  
- Outbox event `ride.expired`  
- Required sweeper composite index(es)  
- Scheduled/internal invocation  
- Tests + emulator verification  

**Optionally (same phase if kept tiny):** durable PENDING offer expiry when the parent ride expires.

**Do not implement:** NO_SHOW, ratings, payments, Maps/GPS, RTDB, Redis, FCM, dispatch, go-online, live pricing, Admin, UI, or Phase 2K+.

---

### Hard stop

- Production code **not** modified  
- Flutter **not** modified  
- No endpoints / indexes / collections / states added by this investigation  
- Phase 2J **not** implemented  
- Phase 2K+ **not** started  
- ADRs / contracts **not** changed  
