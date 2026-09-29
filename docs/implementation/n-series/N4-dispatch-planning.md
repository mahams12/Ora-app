# N4 — Dispatch / Matching Waves (Decision Freeze)

**Status:** **IMPLEMENTED** — N4 Dispatch MVP (2026-09-21)  
**Freeze date:** 2026-09-21 (final decision freeze)  
**Resync date:** 2026-09-21 — **COORDINATE-PRIMARY** ([`CITY-PARTITION-STRATEGY-DECISION.md`](CITY-PARTITION-STRATEGY-DECISION.md), N2C/N3 cutover, [`N2C-N3-COORDINATE-PRIMARY-HARDENING-AUDIT.md`](N2C-N3-COORDINATE-PRIMARY-HARDENING-AUDIT.md))  
**Audit status:** **GREEN** — wave orchestration implemented; delivery (FCM/WS) still deferred.  
**Authority:** Code under `backend/auth-service/src` + ADRs + this freeze outweigh conflicting planning prose.  

**Depends on:** N1, N2A, N2C, N3 (**IMPLEMENTED**, coordinate-primary); ride offer/select (**IMPLEMENTED**); valid ride **pickup lat/lng**.  
**Does not depend on:** `rides.city` for matching; `drivers.homeCity` for matching; PBS catalog; Flutter city selector; N2B; FCM; WebSockets; outbox projector (delivery deferred).  
**Must not become:** assignment, auto-offer, auto-accept, Uber-style auto-assign, ranking engine, maps/ETA, payments, M0 replacement, city-based matching, homeCity writer-as-matching-gate.

---

## Product boundary (FROZEN)

**N4 = server-side dispatch/wave orchestration that invites successive nearby-driver cohorts so drivers can create offers.**

Ora remains an **inDrive-style offered-fare marketplace**:

```text
Passenger request
  → nearby/suitable drivers (N3)
  → N4 invite ledger (waves)
  → driver creates offer (existing)
  → passenger chooses driver (existing selectOffer)
  → transactional assignment (Firestore)
  → progression → completion → rating
```

```text
N4 dispatch decision (durable wave + invite ledger)
    ↓
(delivery = SEPARATE later slice — not N4 MVP)
    ↓
driver creates offer via existing POST /v1/rides/:rideId/offers
    ↓
passenger assigns via existing selectOffer
    ↓
RideService.selectOffer Firestore transaction
```

N4 **MUST NEVER** write `assignedDriverId`.  
N4 **MUST NEVER** create `rideOffers`.  
N4 **MUST NEVER** auto-accept an offer or choose a driver.  
N4 **MUST NEVER** replace N3, M0, `createOffer`, or `selectOffer`.

### Distinctions (FROZEN)

| Concept | Owner |
| ------- | ----- |
| **DISPATCH DECISION** | N4 — which drivers are invited on which wave |
| **ACTUAL DRIVER DELIVERY** | **Not N4 MVP** — no FCM/WS/RTDB/poll API in this phase |
| **OFFER** | Existing `createOffer` |
| **ASSIGNMENT** | Existing `selectOffer` |
| **CANDIDATES** | Existing `NearbyDriversService.findNearby` (N3) |

Until a delivery slice ships, drivers continue discovering rides via **M0 pull** (`GET /v1/rides/open`). N4 MVP still builds the **authoritative invite/wave ledger** for future delivery and for correct wave progression.

---

## Candidate source (FROZEN — COORDINATE-PRIMARY)

```text
Passenger ride pickup coordinates (lat/lng)
        ↓
NearbyDriversService.findNearby (N3)
        ↓
GEORADIUS geo:drivers  (coordinate-primary Redis GEO)
        ↓
N3 eligibility filtering (freshness, accuracy, approved, online, not busy)
        ↓
N4 wave invite orchestration (dedupe + durable ledger)
```

| Input | Role for N4 matching |
| ----- | -------------------- |
| `pickup.lat` / `pickup.lng` | **Required** spatial input |
| `radiusKm = 10` | Fixed (D-RADIUS) |
| `rides.city` | **Optional metadata only** — **NOT** a matching prerequisite; **NOT** a spatial boundary |
| `drivers.homeCity` | **Optional metadata only** — **NOT** required for discovery |
| PBS city catalog | **NOT** required for dispatch matching |
| Maps / geocoding | **Separate** from spatial candidate generation |

**Explicit non-gates:**

- City is **NOT** a physical matching boundary.
- A driver may be invited if **physically** nearby and eligible even if `homeCity` differs from any ride city label.
- Missing/wrong city metadata **must not** exclude a physically eligible driver.
- N4 **must not** query `geo:drivers:{city}` for matching.
- N4 **must not** require “candidate city == ride city”.

Authority: [`CITY-PARTITION-STRATEGY-DECISION.md`](CITY-PARTITION-STRATEGY-DECISION.md), [`N3-nearby-planning.md`](N3-nearby-planning.md), [`N2C-redis-geo.md`](N2C-redis-geo.md).

---

## Code reality

| Component | Status |
| --------- | ------ |
| createRide → SEARCHING + outbox `ride.created` PENDING | IMPLEMENTED |
| M0 open discovery | IMPLEMENTED |
| createOffer / selectOffer | IMPLEMENTED |
| N3 nearby (coordinate-primary) | IMPLEMENTED |
| N2C `geo:drivers` (+ legacy dual-write) | IMPLEMENTED |
| Outbox consumer / FCM / RTDB cards | MISSING |
| Dispatch waves | **IMPLEMENTED** (MVP) |
| `RideDoc.city` | Optional metadata field may exist on create — **not** N4 matching input |

---

## Dispatchable ride & stop (FROZEN)

**Dispatchable** iff all hold:

- `state ∈ { SEARCHING, OFFERS_AVAILABLE }`
- `assignedDriverId == null`
- `expiresAt > serverNow`
- usable **pickup lat/lng** (finite, in range) — **not** “usable city”

**Stop immediately** (no further waves) when any of:

- `DRIVER_ASSIGNED` (or later assigned progression)
- `CANCELLED`
- `EXPIRED`
- wave budget exhausted (3 waves / 30 invites)

**Does not stop** solely because offers exist (see D-STOP-OFFERS).

---

## Waves & candidates (FROZEN)

| Wave | New invites (not previously invited this ride) |
| ---- | ---------------------------------------------- |
| 1 | 5 |
| 2 | 10 |
| 3 | 15 |
| Cap | **30** |
| Cadence | **5 seconds** between end of wave *n* and eligibility of wave *n+1* (D-WAIT) |

- **Source:** `NearbyDriversService.findNearby` in-process (no duplicate GEO implementation in N4).
- **Spatial args:** `{ lat: pickup.lat, lng: pickup.lng, radiusKm: 10, limit: … }` — **no city**.
- **Order:** `distanceKm` ASC (D-RANK).
- **Radius:** fixed **10 km** all waves (D-RADIUS).
- **Eligibility re-check at invite time:** approved, online, marker ≤15s, accuracy ≤50, **not** busy (`DRIVER_ASSIGNED|DRIVER_EN_ROUTE|DRIVER_ARRIVED|RIDE_STARTED`), **not** already invited, ride still dispatchable.  
  **Do not** re-check “city match”.

---

## N4 safety requirements (FROZEN)

### 1. Candidate deduplication across waves

A driver already present in any **COMPLETED** wave’s `driverIds` for this ride **must not** be invited again merely because they reappear in a later N3 result.  
**Already invited** = union of `driverIds` across COMPLETED waves.

### 2. Candidate revalidation

N3 returns a snapshot. Between discovery and invite commit, a driver may become busy, go offline, or go stale.  
N4 **must** re-check authoritative eligibility (Firestore + marker rules as above) at invite time — **do not** trust the N3 list as still valid.

### 3. Dispatch tick idempotency

Re-running the same worker tick / sweep item **must not** duplicate invitations or incorrectly advance `dispatchWave` / `dispatchNextAt`.  
Primary barrier: create-once `rideDispatchWaves/{rideId}_w{n}` (D-IDEM).

### 4. Ride lifecycle races

Cancellation, expiry, assignment, or other terminal/authoritative transitions may occur between discovery and invite commit.  
N4 **must not** override those transitions: re-read ride in txn; if no longer dispatchable → **STOP** / abort without invite commit.

### 5. requestVersion / concurrency

Preserve existing `ride.requestVersion` model (D-REQUEST-VERSION): read + bind on wave; abort if mismatch; **never** invent a second concurrency system; **never** bump `requestVersion` because a wave ran.

### 6. Wave limits

Maximum **3** waves: **5 / 10 / 15**; maximum total invites **30**.

### 7. Timing

**5-second** wave cadence via `dispatchNextAt` (D-WAIT). First wave due immediately when dispatchable.

### 8. Dispatch termination

Once assigned, cancelled, expired, or otherwise not dispatchable — **no further waves**.

---

## Known N3 limitation — COUNT-100 under-fill (FROZEN acknowledgment)

N3 performs a bounded Redis read equivalent to:

```text
GEORADIUS geo:drivers … COUNT 100 ASC
```

then eligibility filtering ([`N2C-N3-COORDINATE-PRIMARY-HARDENING-AUDIT.md`](N2C-N3-COORDINATE-PRIMARY-HARDENING-AUDIT.md)).

Therefore:

- the nearest **100** Redis members are examined first;
- some may be rejected (stale / accuracy / approval / online / busy);
- N3 may return **fewer** eligible drivers even when an eligible driver exists **beyond** the first 100;
- this limitation **pre-existed** city-sharded GEO but can be **more noticeable** with national `geo:drivers`;
- this is a **known bounded-underfill limitation**, **not** a correctness/authorization bug;
- **not fixed in this documentation slice**;
- future bounded refill/over-fetch may be considered **separately after profiling**.

N4 MVP **accepts** possible under-filled waves under high reject density.

---

## Known Firestore read-amplification risk (FROZEN acknowledgment)

N3 may perform multiple Redis GETs + Firestore reads per nearby request (sequential eligibility per candidate; worst-case order of hundreds of reads per call when many markers pass early filters).

- **Acceptable** for current low-QPS MVP.  
- **Requires profiling** before high-concurrency / national-scale dispatch.  
- **Do not** implement batching/parallelization in the N4 freeze or this docs slice.

---

## Legacy city GEO / rollback (FROZEN wording)

| Item | Status |
| ---- | ------ |
| Matching key | `geo:drivers` (N3 reads this) |
| Legacy `geo:drivers:{city}` | N2C **dual-write** when `homeCity` present — **migration compatibility only** |
| Legacy staleness | Known **migration debt**; does **not** affect current N3 matching |
| Cleanup / sweeper | **Out of this freeze** — do not add in docs-only resync |

**Rollback** of N3 to city-sharded readers is an **emergency / compatibility** procedure only. It is **NOT behaviorally equivalent**:

- drivers **without** `homeCity` may disappear from results;
- coordinate-primary drivers can have **stale/mismatched** legacy city membership;
- **supply may be reduced** under rollback.

---

## Final decision matrix

| Decision | Current state | Options considered | **Chosen (FROZEN)** | Reason | Implementation consequence |
| -------- | ------------- | ------------------ | ------------------- | ------ | --------------------------- |
| **D-TRIGGER** | No dispatch start | T1 sweeper; T2 per-ride tick; T3 outbox consumer | **T1 + T2**: primary **dispatch-sweep**; optional **per-ride dispatch-tick** | Matches 2J/2K/2M worker style; no projector; tick enables tests + immediate advance; sweep encodes 5s waits via `dispatchNextAt` | Cron calls sweep; no outbox consumer |
| **D-OWNER-SHAPE** | No route | Various internal shapes | See routes below | Same auth/middleware as existing internals | Two POST internal routes + service |
| **D-CANDIDATE-SOURCE** | Was city-sharded N3 | City shard; geocode; **pickup lat/lng → N3 `geo:drivers`** | **Pickup lat/lng → N3 coordinate-primary** | Matches frozen partition strategy; city ≠ search boundary | `findNearby({ lat, lng, radiusKm: 10, … })` — **no city** |
| **D-CITY-METADATA** | `rides.city` on create | Required for matching; optional metadata | **Optional for matching** — field may remain on create API for UX/ops | Coordinate-primary cutover | N4 **does not SKIP** solely for missing `rides.city` |
| **D-WAIT** | Docs 4–6s vs 5s | 4–6 range; 5s | **5 seconds** | Matches `matching-engine.md`; simple | After wave *n* completes → `dispatchNextAt = now+5s` (wave 3: no next) |
| **D-RADIUS** | N3 default 10 | Fixed 10; per-wave expand | **Fixed 10 km** | Expansion not frozen | `findNearby({ radiusKm: 10, … })` |
| **D-RANK** | N3 ASC distance | Distance; scoring; DM | **`distanceKm` ASC only** | No ranking code | Take next unused candidates in order |
| **D-STOP-OFFERS** | Docs “enough offers” unnumbered | Stop at N; no stop | **NO offer-count stop** | No authoritative N | Continue through OFFERS_AVAILABLE until assign/terminal/budget |
| **D-DELIVERY** | No FCM/WS/RTDB | Poll API; FCM; WS; durable intent only | **Durable dispatch decision only; delivery deferred** | Honest: no delivery infra; M0 remains discovery | Persist waves/invites; optional outbox PENDING; **no** driver wake API in N4 |
| **D-SCHEMA** | None | Ride-only; Redis-only; new collection | **Ride cursor fields + `rideDispatchWaves` collection** | Recoverable, queryable, Firestore SoT | Conceptual — **do not implement in docs slice** |
| **D-IDEM** | None | Redis-only; HTTP key only; create-once wave doc | **Create-once `rideDispatchWaves/{rideId}_w{n}` + optional HTTP Idempotency-Key** | Firestore txn barrier; Redis not SoT | Duplicate ticks SKIP completed waves |
| **D-REQUEST-VERSION** | Always `1`, never bumped | Increment on wave; ignore; bind | **Read + store on wave; never increment in N4** | Offer uniqueness already uses it; rematch out of scope | Abort wave if `ride.requestVersion !==` wave binding |
| **D-CARD-TTL** | N/A | Cards with TTL | **NO DISPATCH CARD IN N4** | Delivery deferred; no card surface | N/A |

> **Supersession:** Prior **D-CITY** wording that made `rides.city` / “city match” a **matching prerequisite** for N4 is **SUPERSEDED** by **D-CANDIDATE-SOURCE** + **D-CITY-METADATA**. [`RIDE-CITY-SCHEMA.md`](RIDE-CITY-SCHEMA.md) remains the create-path field freeze for optional/required API metadata — not the spatial matching gate.

---

## D-TRIGGER (FROZEN)

**Primary:** Periodic internal **dispatch sweeper** (same convention as `expire-sweep` / `offer-expire-sweep` / `no-show-sweep`).

**Secondary:** Per-ride **dispatch tick** for a single ride (ops/tests / optional post-create caller). Does **not** require inventing Pub/Sub.

**Not chosen:** Outbox consumer (no projector).  
**Not chosen:** Sleeping in-request for 5s on Cloud Run as the primary wait mechanism.

**Wait encoding:** After completing wave *n* (*n* < 3), set `dispatchNextAt = serverNow + 5s`. Sweeper/tick only advances when `dispatchNextAt <= now` (or null/`epoch` for first wave due immediately).

**First wave:** Due as soon as ride is dispatchable and `dispatchWave === 0` with `dispatchNextAt` null or ≤ now (no artificial delay before wave 1).

---

## D-OWNER-SHAPE (FROZEN)

| Item | Value |
| ---- | ----- |
| Auth | `X-Ora-Worker-Token` == `ORA_INTERNAL_WORKER_TOKEN` (≥16) |
| Runtime | `auth-service` modular monolith |
| Service | New domain service (e.g. `DispatchWaveService`) calling `NearbyDriversService` + Firestore — **conceptual name only** |
| Route A | `POST /v1/internal/rides/dispatch-sweep` |
| Query | optional `limit` (positive int; same pattern as other sweeps) |
| Route B | `POST /v1/internal/rides/:rideId/dispatch-tick` |
| Body | empty / ignored for MVP |
| Actors | Worker only — **no** passenger/driver JWT |

Do **not** register a public passenger/driver dispatch trigger.
---

## D-WAIT / D-RADIUS / D-RANK / D-STOP-OFFERS / D-DELIVERY / D-SCHEMA / D-IDEM / D-REQUEST-VERSION / D-CARD-TTL

Unchanged from prior freeze except candidate args (see matrix). Summary:

- **Wait:** 5s via `dispatchNextAt`; stop wait on leave-dispatchable.  
- **Radius:** fixed 10 km.  
- **Rank:** `distanceKm` ASC only.  
- **Stop-offers:** no offer-count stop.  
- **Delivery:** durable decision only; M0 remains discovery today.  
- **Schema concept:** ride cursor fields + `rideDispatchWaves/{rideId}_w{n}` create-once.  
- **Idempotency:** wave doc create-once + optional HTTP Idempotency-Key.  
- **requestVersion:** bind only; never increment in N4.  
- **Cards:** none in N4.

### Schema concept (do not implement here)

**Ride cursor:** `dispatchWave`, `dispatchNextAt`, `dispatchStatus` (`none` \| `active` \| `exhausted` \| `stopped`).

**Wave doc:** `rideId`, `waveNumber` (1\|2\|3), `requestVersion`, `driverIds` (ordered), `radiusKm` (10), `status`, timestamps, optional `correlationId`.

Redis `dispatch:notified:*` — **not** SoT.

---

## Terminal race model (FROZEN)

| Scenario | Behavior |
| -------- | -------- |
| Wave running → passenger cancels | **STOP**; mark `dispatchStatus=stopped`; no further waves; do not resurrect |
| Wave running → selectOffer assigns | **STOP**; `stopped` |
| Wave running → ride expires (2J) | **STOP** |
| Candidate selected → driver offline before commit | **SKIP** that driver; continue filling wave if others eligible |
| Driver becomes busy | **SKIP** |
| Candidate stale at invite time | **SKIP** |
| After terminal, worker retries | Re-read ride → not dispatchable → **SKIP** |

---

## Failure model (FROZEN)

| Condition | Behavior |
| --------- | -------- |
| Redis / N3 fail | **FAIL** tick; **RETRY** later while dispatchable; no Firestore geo fallback |
| Firestore fail | **FAIL** tick; bounded retry |
| Worker crash | Retry same wave via D-IDEM |
| Duplicate worker | **SKIP** completed wave |
| Partial wave | Not visible: commit wave atomically or not at all |
| Empty / under-filled candidates (incl. COUNT-100) | Complete wave with available `driverIds` (may be `[]`); schedule next wave if budget remains |
| Cancel/expire mid-tick | **STOP**; abort without invite commit if ride no longer dispatchable |

**Bounds:** max **3** waves; stop at ride `expiresAt`.

---

## Security (FROZEN)

- Trigger: worker token only.  
- No passenger/driver JWT trigger.  
- No public candidate enumeration.  
- Never log worker token.  
- Prefer logging `rideId`, `waveNumber`, `invitedCount` — not full coordinate dumps / secrets.  
- No new driver PII surface in N4 MVP (no cards).  
- City labels are **not** authorization.

---

## Final N4 flow (FROZEN)

```text
createRide → SEARCHING (pickup lat/lng required for dispatch spatial input)
    ↓
ops cron: POST /v1/internal/rides/dispatch-sweep
    (or POST /v1/internal/rides/:rideId/dispatch-tick)
    ↓
if not dispatchable → skip
if wave doc exists → skip (idempotent)
if dispatchNextAt > now → skip
    ↓
NearbyDriversService.findNearby({
  lat: pickup.lat, lng: pickup.lng,
  radiusKm: 10,
  limit: …   // sized for wave fill; subject to N3 COUNT-100 bound
})
    // NO city parameter for matching
    ↓
filter out already-invited; take next 5|10|15 by distanceKm ASC
re-check eligibility per driver (no city match)
    ↓
txn: create rideDispatchWaves/{rideId}_w{n} + update ride dispatch cursor
    (+ optional outbox PENDING)
    ↓
wait 5s (via dispatchNextAt) → next wave if still dispatchable
    ↓
drivers still use M0 + createOffer; passenger selectOffer assigns
    ↓
on assign/cancel/expire → dispatchStatus=stopped
```

---

## Explicit non-goals (FROZEN)

Automatic assignment; `assignedDriverId` writes; offer create/select; FCM; WebSockets; RTDB; maps; ETA; ranking engine; surge; payments; city-based matching; requiring homeCity/PBS for matching; passenger/driver nearby HTTP; M0 changes; Redis assignment locks; geocoding-as-matching; offer-count stop; wave radius expansion; COUNT-100 refill implementation (future).

---

## Remaining blockers (UPDATED)

| Blocker | Type | Notes |
| ------- | ---- | ----- |
| N4 wave **implementation** | Eng | Explicit implementation prompt required |
| Delivery wake-up | **D1 FROZEN** | [`D1-dispatch-delivery-planning.md`](D1-dispatch-delivery-planning.md) — NOT IMPLEMENTED |
| Dense-market COUNT-100 under-fill | Known N3 limitation | Documented; profile before national peak |
| N3 FS read amplification | Profiling risk | Documented; not fixed here |

**Removed as matching blockers:** ops `homeCity` seeding; Flutter city selector; PBS catalog; `rides.city` presence.

All **D-\*** architecture decisions for N4 remain **FROZEN** (with D-CANDIDATE-SOURCE / D-CITY-METADATA superseding matching use of D-CITY).

> N4 wave implementation may proceed under this freeze **without** waiting for city catalog / Flutter city UI / homeCity writer.

---

## Related

- [`CITY-PARTITION-STRATEGY-DECISION.md`](CITY-PARTITION-STRATEGY-DECISION.md)  
- [`N2C-N3-COORDINATE-PRIMARY-HARDENING-AUDIT.md`](N2C-N3-COORDINATE-PRIMARY-HARDENING-AUDIT.md)  
- [`N3-nearby-planning.md`](N3-nearby-planning.md)  
- [`N2C-redis-geo.md`](N2C-redis-geo.md)  
- [`RIDE-CITY-SCHEMA.md`](RIDE-CITY-SCHEMA.md) (create metadata; not matching gate)  
- [`ORA_CURRENT_STATE.md`](../../ORA_CURRENT_STATE.md)  
- ADR-003, ADR-004, ADR-005, ADR-007  

---

## Verdict

> **N4 D-\* decisions remain frozen; candidate source is coordinate-primary.**  
> **Do not implement N4** until an explicit implementation prompt.  
> **Do not** reintroduce city / homeCity / PBS as matching prerequisites.  
> Delivery wake-up is explicitly **out of N4 MVP**.
