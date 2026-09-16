# Phase 2K — Architecture / Next-Slice Investigation

**Date:** 2026-09-10  
**Status:** INVESTIGATION ONLY — no production code modified  
**Verdict:** see §27

---

## 1. Executive summary

Phases **2C–2J** are closed and verified. The modular monolith now owns:

- Auth / onboarding (2C)
- Full ride marketplace + post-assignment progression through **`RIDE_CLOSED`** (2E–2H)
- Authenticated ride history reads (`GET /v1/rides`) (2I)
- Ride search-window **EXPIRED** terminal write-path + internal sweeper (2J)

The ride **happy-path write chain and search TTL terminal** are complete. Phase 2J explicitly deferred durable offer expiry:

> *“Include durable offer EXPIRED writes in 2J? **Yes as optional sibling** if small; else **immediate 2K micro-slice**.”*  
> — `phase-02j-architecture-investigation.md` §26 Q2  
> Closure confirms: *“Offer documents not durably expired in this phase — read-boundary expiry unchanged.”*  
> — `phase-02j-ride-expired-sweeper.md` §15

**Recommended Phase 2K:** the smallest coherent dependency-safe slice is:

> **Durable Offer EXPIRED write-path / sweeper**  
> Persist `rideOffers.status: PENDING → EXPIRED` when (a) offer `expiresAt <= now`, and/or (b) parent ride is/becomes `EXPIRED` (and align cancel/ride-expire sibling cleanup with contracted `ride.offer.expired` outbox) — reusing the Phase 2J worker auth + transactional patterns — **without** Maps, Redis, RTDB, FCM, payments, ratings, dispatch, UI, or `NO_SHOW`.

This closes inventory **#31 Offer expiration** and the contracted event `ride.offer.expired`, using statuses/TTLs/indexes shapes already present in the offer model, and finishes the marketplace timer hygiene hole left open by 2J.

---

## 2. Current verified architecture

### Inspected (repository, post-2J)

| Area | Paths / finding |
|------|-----------------|
| Closed phases | `phase-02c` … `phase-02j` implementation + investigation docs — all CLOSED through expire-sweep |
| Ride code | `backend/auth-service/src/rides/*` — create→close, history, expireRide/sweep |
| Internal worker | `middleware/internal_worker.ts`, `routes/internal.ts` — `POST /v1/internal/rides/expire-sweep` |
| State machine | `state_machine.ts`, `types.ts` — no `NO_SHOW`; `EXPIRED` terminal + expirable gates |
| Offer lifecycle | `offer_lifecycle.ts` — **read/mutation-boundary only** |
| APIs | `docs/api/ride-api.md`, `error-codes.md`, `04-api-contracts.md` |
| SM / product | `ORA_STATE_MACHINE.md`, `03-state-machines.md`, `ride-lifecycle.md` |
| Schema / indexes / rules | `firestore-schema.md`, `firestore.indexes.json`, `firestore.rules` |
| Idempotency / outbox | ADR-006, ADR-005, `idempotency.md`, `event-contracts.md`, `06-realtime-events.md` |
| ADRs | ADR-001…016 (esp. 003, 004, 005, 006, 007, 008, 010, 011, 014) |
| Dispatch / location / payment / notifications | `12-matching-and-dispatch.md`, `10-location-architecture.md`, `13-payment-architecture.md`, `14-notification-architecture.md`, review designs |
| MVP inventory | `02-feature-inventory.md`, `21-mvp-vs-post-mvp.md`, `22-final-gap-analysis.md` |
| Flutter | `mobile/lib/features/{ride,driver,maps,payments,safety}` + location/maps stubs |
| Later plans | `phase-03`…`phase-15`, `ORA_MASTER_PLAN.md` (sequencing ≠ dependency order) |

### Implemented ride lifecycle (code)

```text
SEARCHING → OFFERS_AVAILABLE → DRIVER_ASSIGNED
  → DRIVER_EN_ROUTE → DRIVER_ARRIVED → RIDE_STARTED
  → RIDE_COMPLETED → RIDE_CLOSED
  | CANCELLED
  | EXPIRED   ← durable writer exists (2J); does NOT durably expire PENDING offers
```

### Auth-service mounts

`/v1/auth`, `/v1/rides`, `/v1/internal/rides/expire-sweep` (worker token).

### Flutter

Ride **domain/data** HTTP client (create→close + list) — **no ride UI**. Driver / maps / payments / safety barrels are stubs. Ratings / FCM / RTDB clients **absent**.

---

## 3. Closed-phase invariants

| Invariant | Source | Must preserve in 2K |
|-----------|--------|---------------------|
| Server-authoritative ride/offer docs | ADR-008, Firestore rules deny client writes | Offer EXPIRED only via Admin SDK / service |
| Assignment uniqueness | 2E select txn | Offer expiry must not invent assignment |
| Agreed fare immutable after assign | 2E | No fare mutation |
| Durable idempotency on user mutations | ADR-006, 2E–2H | Worker paths may be state-idempotent like expireRide |
| Outbox atomic with mutation | ADR-005 | `ride.offer.expired` in same txn as status write |
| Terminal immutability | SM; 2H/2J | Do not resurrect EXPIRED/CANCELLED/CLOSED rides |
| EXPIRED ride gate | 2J | Only `SEARCHING\|OFFERS_AVAILABLE` + `expiresAt<=now` |
| List ownership from token | 2I | Unchanged |
| Worker ≠ end-user JWT | 2J | Reuse `X-Ora-Worker-Token` |
| Ride ≠ payment aggregate | ADR-008 / Case 28 | No payment writes |
| Collapsed cancel taxonomy | 2E/2G conscious | Keep single `CANCELLED` + `cancelledBy` |
| Read-boundary offer expiry remains correct | 2F | Durable write must agree with `effectiveOfferStatus` |

---

## 4. Remaining capability map

| # | Capability | Contract | Code today | Class |
|---|------------|----------|------------|-------|
| 31 | **Offer expiration (durable)** | SM / offer-model / `ride.offer.expired` / schema sweeper | Read-boundary only; cancel marks PENDING→EXPIRED **without** outbox; ride expire leaves PENDING | **A — ride-module tip** |
| 32 | Ride expiration | Done (2J) | Durable EXPIRED + `ride.expired` | Closed |
| — | **NO_SHOW** | `DRIVER_ARRIVED` wait 5m → `NO_SHOW`; `ride.no_show` | State **absent**; no `arrivedAt` on `RideDoc` | A — SM expansion |
| 49 | Ratings | Schema `ratings/{rideId}_{type}`; inventory MVP | Collection rules only; **no HTTP API in `docs/api/` or `04-api-contracts`** | B — new aggregate |
| 13–14 | Driver online/offline + location | ADR-011, go-online APIs | Eligibility stub only | C — infra |
| 23–25 | Dispatch / discovery / delivery | Waves + Redis GEO + RTDB + FCM | Absent | C |
| 16–19 | Maps / geocode / route / ETA | Phase 4 plans | Flutter placeholders | C |
| 20 | Live pricing | Fare engine | Fixture `pricingSnapshots` only | C |
| 34–37 | Proximity / live trip | Location arch | Tap progression only | C |
| 40–48 | Payments / ledger / earnings | ADR-010 | `paymentIntentId: null` | B/C large |
| 51–53 | Notifications / FCM / RTDB projectors | ADR-005/009/014 | Outbox write-only `PENDING` | C |
| — | Active-ride discovery UX | Product | Partial via `GET /v1/rides?status=all` | Thin / product |
| — | Distinct DRIVER_/PASSENGER_CANCELLED | Full SM | Collapsed | Conscious defer |
| — | Doc drift: en-route/close in ride-api.md | Implemented | Hygiene | Not a phase |
| — | Active-assignment guard gap | Matching expects no active trip | Offer create blocks only `state==DRIVER_ASSIGNED`, not EN_ROUTE/ARRIVED/STARTED | Correctness micro-gap |

**Post-2J concrete offer gap (verified in code):**

1. `expireRide` updates ride → `EXPIRED` + `ride.expired` only — **does not** update PENDING offers.  
2. `offer_lifecycle.effectiveOfferStatus` treats past-TTL PENDING as EXPIRED in memory — **does not persist**.  
3. Pre-assign `cancelRide` sets PENDING offers → `EXPIRED` but emits **no** `ride.offer.expired`.  
4. `docs/algorithms/offer-model.md` §7: *“Offer expired → Sweeper sets EXPIRED”*; *“Ride cancelled/expired → … offers set EXPIRED”*.  
5. Schema documents offer sweeper index on `expiresAt`; **`firestore.indexes.json` has no `rideOffers` `status+expiresAt` (or lone `expiresAt`) composite** — only `rideId+status` and `rideId+createdAt`.

---

## 5. Dependency graph

```text
[Auth 2C]
  ├─► [Ride core 2E–2H] ─┬─► [History 2I] ──────────── done
  │                      ├─► [Ride EXPIRED sweeper 2J] ── done
  │                      │         └─► [Offer EXPIRED durable write] ← recommended 2K
  │                      ├─► [NO_SHOW] ── needs new state + arrived wait clock (`arrivedAt` missing)
  │                      └─► [Ratings] ── needs API freeze; no infra; optional after terminals exist
  │
  ├─► [Maps/GPS Ph4] ─┬─► [Live pricing Ph5]
  │                   └─► [Proximity / trip UX]
  │
  ├─► [Driver go-online Ph6] ─► Redis + RTDB (ADR-004/011)
  │         └─► [Dispatch waves Ph8] ─► FCM/RTDB
  │
  ├─► [Outbox consumers Ph9] ─► Pub/Sub + FCM/RTDB projectors
  │
  └─► [Payments Ph11] ─► ledger (ADR-008/010 separate BC)
```

**Safe edges from current tip (no Redis/Maps/PSP/FCM required):**

1. Durable offer EXPIRED write-path / sweeper  
2. NO_SHOW (new SM terminal + wait policy; medium expansion)  
3. Ratings (after HTTP contract freeze)  
4. Doc hygiene / thin active-list filter  

**Unsafe edges:** go-online, dispatch, Maps/GPS, RTDB, Redis, FCM consumers, payments.

**Roadmap caution:** `phase-03`…`phase-15` / master plan still describe Auth/Ride/Assignment as “NOT STARTED” in places. That **conflicts** with closed 2C–2J. Do **not** pick 2K from roadmap numbering.

---

## 6. Candidate slices

| ID | Slice | Prereqs met? |
|----|-------|--------------|
| **K1** | Durable offer EXPIRED write-path + sweeper + `ride.offer.expired` | **Yes** — statuses, TTLs, 2J worker, cancel sibling pattern |
| **K2** | NO_SHOW sweeper (`DRIVER_ARRIVED` → `NO_SHOW`) | Partial — arrive API exists; **state + `arrivedAt` missing** |
| **K3** | Ratings aggregate (stars/tags) | Partial — COMPLETED/CLOSED exist; **API not frozen** |
| **K4** | Expand active-assignment guard to all in-progress states | Yes — thin correctness fix |
| **K5** | Active-ride query/filter UX | Partial — 2I list exists; product-thin |
| **K6** | Outbox → FCM/RTDB consumers | Events exist; **infra missing** |
| **K7** | Driver go-online/offline | Auth only; **Redis+RTDB required** |
| **K8** | Dispatch / matching waves | Needs K7 + location freshness |
| **K9** | Maps/GPS + proximity | Flutter stubs only |
| **K10** | Live pricing estimate | Needs routes/Maps |
| **K11** | Cash/ledger payment skeleton | Fare exists; **large BC** |
| **K12** | First ride UI | Data layer ready; product not SM |
| **K13** | Doc sync en-route/close | Hygiene only |

---

## 7. Candidate comparison

| ID | Scope | New infra | Closes contract hole? | Reuse of 2J | Future rework | 2K fit |
|----|-------|-----------|----------------------|-------------|---------------|--------|
| **K1 Offer EXPIRED** | Small | Worker + offer expiry index | **Yes (#31 + event + offer-model sweeper)** | **Maximum** | Low | **Recommended** |
| K2 NO_SHOW | Medium | Worker + new enum/gates + clock field | Yes (different SM hole) | High pattern | Medium (taxonomy / fee policy) | Strong alternate **after** K1 |
| K3 Ratings | Medium | New collection writes + APIs | Inventory #49; API unlocked | Low | Medium (API churn) | Alternate if product prioritizes post-trip |
| K4 Active-guard | Tiny | None | Matching eligibility honesty | N/A | Low | Too thin alone; optional sibling |
| K5 Active discovery | Tiny | None | UX only | N/A | Low | Not coherent backend phase |
| K6–K11 | Large | Redis/RTDB/FCM/Maps/PSP | Platform | Low | High | Later phases |
| K12–K13 | Product/docs | — | No SM hole | — | — | Not 2K backend tip |

**Selection rule applied:** minimum scope + maximum architectural reuse + minimum future rework — **not** “next on roadmap.”

---

## 8. Recommended Phase 2K boundary

### In scope

1. **Durable** transition of `rideOffers` with `status == PENDING` and `expiresAt <= now` → `EXPIRED`.  
2. **Parent-coupled cleanup:** when a ride is expired (extend `expireRide` and/or a bounded follow-up), set remaining PENDING offers → `EXPIRED` (bounded, same `MAX_OFFERS_SUPERSEDE_IN_TXN` class of limits). Aligns with offer-model: *ride expired → offers set EXPIRED*.  
3. Atomic outbox **`ride.offer.expired`** per durable offer expiry (schemaVersion 1; payload at minimum: `rideId`, `offerId`, `driverId`, `reason`, `expiresAt`).  
4. Internal worker invocation reusing `createInternalWorkerMiddleware` / `X-Ora-Worker-Token` (sibling route e.g. `POST /v1/internal/rides/offer-expire-sweep` **or** combined sweep entry — decide in implementation without public JWT).  
5. Required Firestore composite index for sweeper query (expected shape: `rideOffers` `status ASC + expiresAt ASC`, matching schema intent).  
6. Concurrency vs select / withdraw / ride expire / cancel — transactional re-read; no double outbox; no overwrite of SELECTED/WITHDRAWN/SUPERSEDED.  
7. Tests + emulator live proof of index + durable writes + races.  
8. Flutter: **none required** (optional domain/status constant only if already shared; **no UI**).

### Out of scope

- `NO_SHOW` / `DRIVER_CANCELLED` timers or new ride states  
- Ratings, payments, wallet, ledger, earnings, receipts  
- Maps, GPS, proximity  
- RTDB, Redis, FCM, Pub/Sub consumers  
- Driver go-online, dispatch waves, live pricing  
- Admin/support, Cargo/Delivery  
- Ride UI / navigation  
- Redesign of 2E–2J assignment/progression/history/ride-expire contracts beyond offer durability races  
- Changing collapsed `CANCELLED` taxonomy  

### Exact implementation boundary (for next prompt)

**Phase 2K — Durable Offer EXPIRED Write-Path / Sweeper**

Implement only durable `PENDING → EXPIRED` on `rideOffers/{offerId}` for TTL-elapsed and parent-ride-expired cleanup, with transactional safety, outbox `ride.offer.expired`, sweeper index(es), internal worker invocation, and verification.

---

## 9. Why it is the smallest coherent slice

1. **Explicitly named by prior investigation** as the deferred 2J sibling / “immediate 2K micro-slice.”  
2. **Closes a live inconsistency:** rides can be durably `EXPIRED` while offers remain stored `PENDING` — contradicts offer-model and confuses any future query/projection that trusts stored status.  
3. **No new ride state** — unlike NO_SHOW — minimizing SM rework.  
4. **Maximum reuse:** 2J worker auth, txn+outbox pattern, cancel’s PENDING→EXPIRED sibling updates, `effectiveOfferStatus` predicates, existing `EXPIRED` offer status enum.  
5. **Contract-backed:** inventory #31, `ride.offer.expired` in event-contracts + realtime-events, offer-model sweeper language, schema sweeper index note.  
6. **Dependency-safe:** Firestore + internal worker only; no ADR-004/011/010 platforms.  
7. **Unblocks later consumers:** FCM/RTDB projectors for offer expiry need durable status + outbox events.  
8. Ratings/NO_SHOW leave this marketplace hygiene hole open and either expand SM or invent APIs.

---

## 10. State-machine impact

| Machine | Impact |
|---------|--------|
| Ride SM | **None required** for K1. Do not add states. Ride EXPIRED writer already exists. |
| Offer status machine | Persist transition already implied by 2F read-boundary: `PENDING → EXPIRED` (TTL or parent terminal). |
| Terminals | Offer `EXPIRED` remains terminal for select/withdraw (existing asserts). |
| NO_SHOW / split cancels | **Out of scope** — do not invent. |

---

## 11. Data-model impact

| Collection | Change |
|------------|--------|
| `rideOffers/{offerId}` | Durable `status: EXPIRED` writes (field already exists). Optional `expiredAt` **only if** needed for audit — prefer minimal: status + existing `expiresAt` + outbox `occurredAt`. |
| `rides/{rideId}` | No new fields for K1. |
| `outboxEvents` | New `eventType: ride.offer.expired` rows (collection exists). |
| `idempotencyRecords` | Not required for worker state-idempotent expire (mirror 2J). |
| Indexes | Add `rideOffers` composite suitable for `status == PENDING AND expiresAt <= now` (schema anticipates sweeper; **missing today** in `firestore.indexes.json`). |
| New collections | **None.** |

---

## 12. API impact

| Surface | Change |
|---------|--------|
| Public passenger/driver ride APIs | **No new product endpoints required.** List/select/withdraw already treat effective expiry. |
| Internal | Add/extend worker route for offer expiry sweep (service token). |
| `GET` offers | May begin returning stored `EXPIRED` more often (already overlays effective status). |
| Doc hygiene | Optional sync of `ride-api.md` en-route/close — **not** DoD for 2K. |

---

## 13. Security

| Concern | Rule |
|---------|------|
| Who may expire offers | Server/worker only — never client Firestore write (rules already deny). |
| Public “expire offer” | **Do not** expose end-user expire-by-id without actor rules; prefer sweeper. |
| Worker auth | Reuse `ORA_INTERNAL_WORKER_TOKEN` / `X-Ora-Worker-Token`; reject if unset/short. |
| Authorization unchanged | Select/withdraw/list authz gates stay passenger/driver as today. |
| No privilege escalation | Expiring offers must not assign rides or alter fares. |
| PII in outbox | Keep payload to ids + reason + timestamps (match existing outbox style). |

---

## 14. Idempotency

| Path | Requirement |
|------|-------------|
| Offer TTL expire (worker) | State-idempotent: already `EXPIRED` → no versioned ride bump, **no second** `ride.offer.expired`. |
| Parent ride expire + offer cleanup | Same txn or strictly ordered follow-up; duplicate sweep safe. |
| User mutations | Unchanged Idempotency-Key behavior on create/select/withdraw/cancel. |
| Race: expire vs select | Transaction: select wins → offer SELECTED; expire skips non-PENDING. |
| Race: expire vs withdraw | Withdraw wins → WITHDRAWN; expire skips. |

Do **not** require client Idempotency-Key on internal sweep (mirror 2J `expireRide`).

---

## 15. Concurrency

| Race | Expected outcome |
|------|------------------|
| Offer expire vs passenger select | One winner; select requires PENDING+not past TTL; durable expire prevents stale select if commit order loses on PENDING check |
| Offer expire vs driver withdraw | Non-PENDING short-circuit |
| Offer expire vs ride expire | Both may try to mark offers; second sees EXPIRED → no-op |
| Offer expire vs ride cancel (pre-assign) | Cancel already marks EXPIRED; expire no-op; **event emission gap on cancel** noted in §27 |
| Concurrent sweep workers | Per-offer txn idempotent |
| Ride version | Offer expiry **should not** bump `rides.version` unless implementation couples into ride expire txn that already bumps once |

---

## 16. Transaction boundaries

**Preferred patterns (implementation chooses one coherent design):**

### A. Offer-local TTL expire (per offer)

```text
runTransaction:
  re-read offer
  if status != PENDING → skip
  if expiresAt > now → skip
  update status=EXPIRED
  write outbox ride.offer.expired
```

### B. Parent ride expire coupling (extend `expireRide`)

```text
runTransaction (existing ride expire):
  … ride → EXPIRED + ride.expired …
  query PENDING offers for rideId (bounded)
  for each: status=EXPIRED + ride.offer.expired outbox
```

**Constraint:** Firestore txn limits — keep sibling offer updates bounded (`MAX_OFFERS_SUPERSEDE_IN_TXN = 50`). If a ride has more PENDING offers than the bound, document overflow strategy (second pass / next sweep) — same class of MVP limit as assignment supersede.

**Do not** cross into payment, Redis, or RTDB writes.

---

## 17. Outbox / event implications

| Event | Today | 2K |
|-------|-------|-----|
| `ride.offer.expired` | Documented; **never written** | **Write on durable offer expiry** |
| `ride.expired` | Written (2J) | Unchanged; may share txn with offer cleanup |
| `ride.offer.withdrawn` / `.selected` / `.received` | Written | Unchanged |
| Consumers | None | Still none — write-only `publishState: PENDING` |

**Cancel-path gap:** cancel already sets offers EXPIRED without `ride.offer.expired`. 2K should either (a) add outbox on that path as a **narrow consistency fix** inside the same phase, or (b) explicitly defer and document. Recommendation: **include emit-on-cancel durable expire** if it stays a few lines inside existing cancel txn; otherwise list as open question — do not expand into notification delivery.

---

## 18. Failure / retry semantics

| Failure | Behavior |
|---------|----------|
| Sweeper crash mid-batch | Per-offer txns; retry safe |
| Partial parent-coupled cleanup (bound hit) | Next sweep pass expires remaining PENDING under expired rides |
| Index missing | Query fails — ship index + emulator proof before claiming Done |
| Worker token misconfig | 503/403 as 2J |
| Clock skew | Use server now; same as 2J |
| Offer already SELECTED | Skip — never expire selected |

---

## 19. Observability

| Signal | Notes |
|--------|-------|
| Sweep metrics | scanned / expired / skipped / failed (mirror 2J sweep result shape) |
| Correlation id | Propagate on internal route |
| Outbox backlog | Still PENDING until Phase 9 consumers — do not treat as 2K failure |
| Logs | rideId, offerId, reason (`offer_ttl_elapsed` \| `parent_ride_expired` \| `parent_ride_cancelled`) |

---

## 20. Performance / scaling

| Topic | Guidance |
|-------|----------|
| Batch size | Cap like 2J (e.g. 100/run, hard max 200) |
| Query | Equality on `status==PENDING` + range on `expiresAt` — needs composite index |
| Hot rides | Bound sibling updates; avoid unbounded txn |
| Polling interval | Ops/scheduler concern; not in-repo Cloud Scheduler wiring required for DoD (document contract like 2J) |
| Cost | Extra writes proportional to expired offers; expected small vs ride docs |

---

## 21. Live Firestore proof plan

Emulator (or designated live harness), parallel to 2J proofs:

1. **Index proof:** query `PENDING + expiresAt <= now` returns due offers.  
2. **TTL expire:** PENDING past TTL → durable EXPIRED + exactly one `ride.offer.expired`.  
3. **Idempotent re-sweep:** second run → already expired / no duplicate outbox.  
4. **Parent ride expire:** expire ride → PENDING offers become EXPIRED + events.  
5. **Race expire vs select:** concurrent; exactly one assignment or expire; no corrupt dual state.  
6. **Race expire vs withdraw.**  
7. **Non-PENDING immunity:** SELECTED/WITHDRAWN/SUPERSEDED untouched.  
8. Regression: 2E–2J unit/live harnesses still PASS.

---

## 22. Test matrix

| Case | Expected |
|------|----------|
| Offer TTL elapsed, ride still SEARCHING/OFFERS_AVAILABLE | Offer EXPIRED; ride unchanged |
| Offer TTL elapsed, ride already EXPIRED | Offer EXPIRED (cleanup) |
| Ride expire with N PENDING offers (N≤bound) | All EXPIRED + events |
| Ride expire with N>bound | First page expired; remainder on later sweep |
| Select of durably expired offer | `422 OFFER_EXPIRED` |
| Withdraw of durably expired offer | `422 OFFER_EXPIRED` (existing assert) |
| Double worker sweep | Idempotent |
| Worker without token | 403/503 |
| Cancel pre-assign | Offers EXPIRED; events per §17 decision |
| Regression assignment concurrency | Unchanged winners |

---

## 23. Risks

| Risk | Mitigation |
|------|------------|
| Over-scope into NO_SHOW / ratings | Explicit non-goals |
| Unbounded offer fan-out in ride expire txn | Hard limit + multi-pass |
| Duplicate outbox on cancel+sweep | Idempotent expire short-circuit; optional causation keys |
| Missing index in prod | Ship with implementation; emulator proof |
| Treating read-boundary as “good enough” forever | Rejected — contradicts offer-model sweeper + post-2J gap |
| Bumping ride.version on offer-only expire | Avoid — offer is separate aggregate doc |
| Inventing Redis/FCM for “complete” expiry UX | Out of scope — outbox only |
| API freeze distraction (ratings) | Defer ratings until contract exists |

---

## 24. Non-goals

Maps, GPS, geofencing, proximity, RTDB, Redis, FCM, Pub/Sub consumers, driver go-online, dispatch/matching, live pricing, payments/wallet/ledger/earnings/receipts, ratings/reviews, support/admin, Cargo/Delivery, Flutter ride UI, `NO_SHOW` state introduction, split cancel terminals, redesign of closed 2E–2J ride APIs, Cloud Scheduler Terraform/wiring beyond documented invoke contract.

---

## 25. Implementation plan

*(For the next implementation prompt only — **do not execute in this investigation**.)*

1. Add offer sweeper query + composite index `rideOffers (status, expiresAt)`.  
2. Implement `expireOffer` (single) + `sweepExpiredOffers` (bounded).  
3. Extend `expireRide` (or immediate follow-up) to durable-expire PENDING offers + `ride.offer.expired`.  
4. Decide cancel-path outbox alignment (§17).  
5. Wire internal worker route + auth reuse.  
6. Race tests + unit proofs + emulator live harness.  
7. Closure doc `phase-02k-…md`.  
8. Regression 2E–2J.

---

## 26. Definition of Done

1. TTL-due PENDING offers become durable `EXPIRED`.  
2. Parent ride EXPIRED cleanup durably expires remaining PENDING offers (bounded + multi-pass if needed).  
3. `ride.offer.expired` outbox written atomically with each durable transition (no duplicates on retry).  
4. Select/withdraw/expire races defined and tested.  
5. Sweeper index present and emulator-proven.  
6. Internal worker auth only — no public abuse surface.  
7. No payments/Maps/Redis/RTDB/FCM/ratings/UI/NO_SHOW.  
8. 2E–2J regressions green.  
9. Read-boundary `effectiveOfferStatus` remains consistent with stored status after sweep.

---

## 27. Open questions

| # | Question | Recommendation |
|---|----------|----------------|
| 1 | Couple offer cleanup into `expireRide` txn vs separate worker pass? | Prefer **in-txn bounded cleanup** on expire + separate TTL sweeper for offer-local clocks |
| 2 | One outbox event per offer or summary event? | **Per offer** — matches `ride.offer.expired` naming and future per-driver notify |
| 3 | Emit `ride.offer.expired` on pre-assign cancel path too? | **Yes if tiny**; else defer with explicit residual gap |
| 4 | Add `expiredAt` field on offer docs? | **No by default** — status + outbox `occurredAt` suffice |
| 5 | Combined internal `/expire-sweep` vs dedicated offer route? | Either OK; dedicated route keeps metrics clearer |
| 6 | Should NO_SHOW be 2K instead? | **No** — larger SM expansion; leaves offer durability hole; missing `arrivedAt` |
| 7 | Should ratings be 2K instead? | **Only if** product freezes HTTP contract **and** explicitly prioritizes post-trip over marketplace hygiene |
| 8 | Fix active-assignment guard (EN_ROUTE+) in same phase? | Optional **tiny sibling**; not required for offer TTL DoD |
| 9 | Sync ride-api.md en-route/close? | Allowed hygiene; not 2K DoD |
| 10 | Batch size / schedule? | Mirror 2J caps; ops configures scheduler |

---

## Final verdict

# READY FOR PHASE 2K IMPLEMENTATION

### Exact implementation boundary for the next prompt

**Phase 2K — Durable Offer EXPIRED Write-Path / Sweeper**

Implement **only**:

- Durable `rideOffers` transition `PENDING → EXPIRED` when offer TTL elapses  
- Durable PENDING offer cleanup when parent ride is/becomes `EXPIRED` (bounded)  
- Atomic outbox `ride.offer.expired`  
- Required offer sweeper composite index(es)  
- Internal/worker invocation (reuse 2J service auth)  
- Tests + emulator verification  

**Do not implement:** NO_SHOW, ratings, payments, Maps/GPS, RTDB, Redis, FCM, dispatch, go-online, live pricing, Admin, Flutter UI, or Phase 2L+.

---

### Hard stop

- Production code **not** modified  
- Flutter **not** modified  
- No endpoints / indexes / collections / states added by this investigation  
- Phase 2K **not** implemented  
- ADRs / contracts **not** changed  
