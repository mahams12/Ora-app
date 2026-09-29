# City Partition Strategy Decision (FROZEN)

**Status:** **ARCHITECTURE FROZEN** — decision only; **NOT IMPLEMENTED**  
**Date:** 2026-09-21  
**Slice:** `CITY-PARTITION-STRATEGY DECISION`  
**Authority:** This freeze + code reality + [`CITY-DEPENDENCY-AUDIT.md`](CITY-DEPENDENCY-AUDIT.md) + ADR-004.  
**Product model:** inDrive-style offered-fare marketplace (passenger chooses driver). **Not** Uber-style auto-assignment.

```text
INSPECT → DECIDE → FREEZE → DOCUMENT   ← this slice
IMPLEMENT → TEST → …                  ← later slices only
```

---

## 1. Decision

```text
MOVE_TO_COORDINATE_PRIMARY
```

**Rejected:** `KEEP_CITY_SHARDING` (`geo:drivers:{city}` as the matching partition).

City labels may remain as **optional product/ops metadata**. They are **not** the spatial search boundary and **must not** gate nearby-driver eligibility.

---

## 2. Why

### Product principle (frozen)

```text
city ≠ physical search boundary
```

A passenger near a metro edge must still discover drivers who are physically nearby. A driver who is physically near a pickup must be eligible based on **live coordinates + eligibility gates**, not registered/home city.

### Repository evidence

| Fact | Source |
| ---- | ------ |
| `city` is not a ride-assignment correctness field | [`CITY-DEPENDENCY-AUDIT.md`](CITY-DEPENDENCY-AUDIT.md) |
| City is documented as a Redis **shard selector**, not auth | [`RIDE-CITY-SCHEMA.md`](RIDE-CITY-SCHEMA.md) |
| Redis GEO is non-authoritative optimization | [ADR-004](../../architecture-final/ADRs/ADR-004-Redis-GEO-Optimization.md) |
| Missing `homeCity` → skip GEOADD, empty N3 supply | `geo_projection.ts`, N3 D7 |
| Matching meaning is “drivers near pickup” | [`N3-nearby-planning.md`](N3-nearby-planning.md) |
| Offered-fare flow already exists without city in offer/assign | `ride_service.ts` |

### A vs B against ride-hailing criteria

| Criterion | A — city shard | B — coordinate-primary (**chosen**) |
| --------- | -------------- | ----------------------------------- |
| **Correctness** | Valid nearby drivers missed when passenger `city` ≠ driver `homeCity` (boundaries, mis-seeded homeCity, free-text drift) | Candidates from physical proximity; eligibility filters remain |
| **Candidate quality** | Proximity diluted by label partitioning | Distance ASC from pickup reflects reality |
| **Boundary behavior** | Lahore/Sheikhupura, RWP/ISB, Karachi metro edges systematically fail | Works across arbitrary political labels |
| **Driver mobility** | Moving cities without updating `homeCity` orphans GEO membership | Live GPS updates position in the same spatial index |
| **Drivers without homeCity** | Invisible to N3 despite online+GPS | Visible if projected from live lat/lng |
| **Passenger mobility / edge pickup** | Wrong or missing city empties supply | Pickup lat/lng sufficient |
| **GPS-only operation** | Needs city catalog/selector + homeCity seeding for matching | Matching runs from coordinates |
| **PBS 565 catalog for matching** | Becomes a de-facto matching dependency | **Not required** for matching |
| **Flutter city selector for matching** | Required to feed `rides.city` → N3/N4 | **Not required** for matching |
| **Scalability (100 → 100k)** | Smaller keys, but wrong-shard emptiness is a product bug | Single/national GEO + `COUNT` is proven; cell sharding later **within** coordinate-primary if needed |
| **Ops simplicity** | Must keep passenger city ↔ driver homeCity aligned forever | Align on location freshness/accuracy/online/busy — already N3 gates |
| **Migration cost** | Low short-term (keep current N2C/N3) | Real cutover cost on N2C/N3 contracts (documented in §14) |
| **inDrive offer model** | Preserved | Preserved — only candidate generation input changes |

### Why not keep A “because N2C/N3 already work”

Working city-sharded N2C/N3 prove Redis GEO projection/query plumbing. They do **not** prove city labels are the right **product** partition. Freezing A would force further investment (PBS import, Flutter city selector, homeCity writer, N4-on-city) into a known boundary-correctness defect.

**Mature pattern chosen:** Redis GEO (or equivalent spatial index) keyed for **coordinate search**, with Firestore remaining durable SoT for availability, busy state, offers, and assignment (ADR-004 unchanged).

---

## 3. Current Architecture

| Layer | Today |
| ----- | ----- |
| Passenger create | `POST /v1/rides` **requires** `city` → `rides.city` slug |
| Driver profile | `drivers.homeCity` ops-seeded; **no writer API** |
| N1 | Online/offline in Firestore; offline best-effort GEO `ZREM` using homeCity |
| N2A | Accepts lat/lng/accuracy/seq; SoT `locationStreams` |
| N2C | `GEOADD geo:drivers:{normalizeCitySlug(homeCity)}` + `driver:online:{id}` TTL 30s; skip GEO if no homeCity |
| N3 | Internal nearby requires `city`+lat+lng; `GEORADIUS geo:drivers:{city}`; freshness ≤15s; accuracy ≤50m; Firestore eligibility + busy exclusion |
| M0 | Open rides by state/expiry — **no city filter** |
| Offer / select | Transactional; **no city** |
| N4 | **Not implemented**; freeze currently assumes `rides.city` → N3 |
| City catalog / PBS | Dataset artifacts exist; **production import blocked**; not used by runtime matching |
| Flutter | **No** city selector implemented |

---

## 4. Target Architecture

Conceptual only — **no code in this slice**.

```text
Driver online (Firestore)
    + live GPS accepted (N2A)
    → project lat/lng into coordinate-primary Redis GEO (N2C')
    → driver:online marker (freshness/accuracy)

Passenger create ride (pickup/destination + offered fare)
    → SEARCHING (Firestore SoT)

Nearby / dispatch candidate generation
    → GEORADIUS (or GEOSEARCH) on coordinate-primary index
       around pickup lat/lng + radius + COUNT
    → filter: online marker fresh, accuracy, approved, not banned,
              not busy, category prefs as already designed
    → NOT filtered by rides.city / homeCity

Drivers may create offers (existing)
Passenger selects offer (existing transactional assignment)
Progression → completion → rating (existing)
```

**City / service-area labels** (if kept) are for display, analytics, ops coverage, or future polygons — **after** spatial candidacy, never instead of it.

**Firestore remains SoT.** Redis remains non-authoritative candidate optimization (ADR-004).

---

## 5. Redis Design

**Intent (not mutated in this slice):**

| Key | Role |
| --- | ---- |
| `geo:drivers` | Primary national (or env-scoped) GEO index of **online-projected** drivers. Member = `driverId`. Score/coords = live lng/lat. |
| `driver:online:{driverId}` | Unchanged role: TTL marker with freshness/accuracy/seq; **city field optional/ignored for matching**. |

### Scale stance

| Online drivers (order of magnitude) | Approach |
| ----------------------------------- | -------- |
| ~100 – ~10,000 | Single `geo:drivers` + `GEORADIUS … COUNT 100` (matches existing matching-engine COUNT habit) |
| ~100,000+ national concurrent | Still coordinate-primary; **optional later** geohash/H3 **cell** keys derived from coordinates — not city names |

Cell sharding is an allowed **future scale tactic inside Option B**, not a reversion to Option A.

### Explicitly rejected Redis matching keys

```text
geo:drivers:{city}     ← matching partition (rejected)
geo:drivers:{homeCity} ← same defect
```

Legacy city keys may exist during migration dual-write; they are not the target SoT for candidacy.

---

## 6. N3 Contract

**Conceptual target** (supersedes city-required query for matching):

**Inputs**

| Input | Required | Meaning |
| ----- | -------- | ------- |
| `lat`, `lng` | **Yes** | Pickup (or search) point |
| `radiusKm` | Yes (bounded default) | Search radius |
| `limit` | Yes (bounded) | Max returned candidates |
| `city` | **No** for matching | Must not be required; if present, ignore for GEO key selection |

**Outputs**

| Field | Meaning |
| ----- | ------- |
| `pickup` | Echo lat/lng |
| `radiusKm` | Applied radius |
| `candidates[]` | `driverId`, `distanceKm`, `lat`, `lng`, `lastLocationTs`, `accuracy` |

**Eligibility filters (retain / strengthen — already directionally present):**

1. Redis marker present (online projection)
2. Freshness window (≤15s today)
3. Accuracy ceiling (≤50m today)
4. Firestore: approved driver, active, not banned
5. Not busy on active ride states
6. Optional later: category / service-area polygon — **post**-spatial

**Meaning frozen:** Nearby = drivers near passenger pickup **in physical space**.

---

## 7. N4 Impact

N4 remains **not implemented**. This freeze updates the **conceptual** input:

| Was (N4 planning) | Target |
| ----------------- | ------ |
| Read `rides.city` → `findNearby({ city, lat, lng })` | Read pickup `lat/lng` → `findNearby({ lat, lng, radiusKm })` |
| SKIP ride if missing city | SKIP only if missing/invalid pickup coordinates (or ride not dispatchable) |
| “city match” as invite eligibility | **Remove** as matching gate |

N4 still:

- Does **not** assign (`assignedDriverId`)
- Does **not** create offers
- Only orchestrates invite/wave cohorts from N3-ordered distance
- Preserves passenger offer selection as assignment authority

N4 planning docs that hard-require `rides.city` for dispatch are **superseded for matching** by this freeze (update those docs in a later doc-sync slice if needed; **not** this slice’s implementation work).

---

## 8. `rides.city`

| Horizon | Status |
| ------- | ------ |
| **Today (unchanged code)** | Still required by current API (do not change in this slice) |
| **Target after coordinate-primary cutover** | **Optional metadata** — not required for nearby/dispatch matching |
| **Not** | Domain correctness field; **not** deleted in this decision slice |

Future createRide may keep accepting `city` for analytics/UX without using it as a GEO shard. Deprecation of the **required** validation is part of the migration slice, not this freeze’s code.

---

## 9. `drivers.homeCity`

| Horizon | Status |
| ------- | ------ |
| **Matching** | **Not required** |
| **N2C projection** (target) | Must not depend on homeCity to `GEOADD` |
| **Field** | May remain as optional profile/ops metadata |
| **Writer API** | Not a matching prerequisite |

Drivers without a meaningful home city must still enter the spatial index when online + location-accepted.

---

## 10. PBS Catalog

| Question | Answer |
| -------- | ------ |
| Required for matching? | **No** |
| Required for core ride flow? | **No** |
| UX / ops / coverage labeling? | **Deferred** — optional later product work |
| Production import now? | **Forbidden** (licensing + this freeze) |

Pakistan-wide 565-city PBS work is **not** on the critical path for coordinate-primary matching.

---

## 11. Google Maps / GPS

Keep these **separate**:

| Concern | Role in Ora | Performs nearby matching? |
| ------- | ----------- | ------------------------- |
| **GPS / location acquisition** | Produce trusted-enough lat/lng/accuracy/time for drivers (and later passenger pickup UX) | No — feeds N2A |
| **Maps rendering** | Show map UI / route visualization | No |
| **Geocoding / place lookup** | Address ↔ coordinates / place search | No |
| **Spatial candidate generation** | Redis GEO (server) | **Yes** — Ora’s own index |

**Do not assume Google Maps performs driver matching.** Maps SDK ≠ Redis GEO.

Coordinate-primary matching needs **GPS acquisition + server spatial index**, not a Maps dependency.

---

## 12. inDrive-style Product Flow

Chosen architecture **preserves**:

```text
Passenger: pickup → destination → propose/accept fare → request
        → suitable nearby drivers can see/respond
        → driver offer
        → passenger chooses driver
        → transactional assignment (Firestore)
        → progression → completion → rating

Driver: online → live location → eligible via nearby
      → sees suitable requests → offer
      → selected → navigate/progress → complete → rate
```

**Explicitly not introduced by this decision:**

- Uber-style automatic assignment
- Automatic fare replacement of offered-fare marketplace
- City label as invite gate

---

## 13. Ora Improvement Opportunities

Compatible with the proven model; **do not implement here**:

- Faster candidate discovery (coordinate GEO without city miss)
- Stronger stale-driver filtering / marker TTL alignment
- Clearer busy vs online vs projected-in-GEO states
- Better race/idempotency on dispatch invites (N4 later)
- Safer location validation (already N2A direction)
- Correct boundary handling (primary motivation for B)
- Observability: distance distributions, empty-candidate causes without city blame
- UX: pickup/destination first; no forced city selector for matching
- Optional later: service-area polygons / surge zones as **overlays**, not GEO key names

---

## 14. Migration Risk

Changing from working city-sharded N2C/N3 is **real** and must be intentional.

| Area | Impact |
| ---- | ------ |
| Redis keys | Writers move to `geo:drivers`; readers stop requiring `{city}` |
| N3 HTTP/query contract | `city` ceases to be required (breaking for any caller passing only city) |
| N2C | Project from live lat/lng always when online+accepted; homeCity optional |
| `rides.city` API | Required→optional in a later API slice; historical docs may omit city |
| N4 freeze text | D-CITY matching dependency superseded |
| Flutter | Avoid building city selector for matching; pickup coords matter |
| PBS / catalog | Matching path decoupled; import stays blocked |
| Tests / proofs | Nearby + GEO proofs must be rewritten for coordinate-primary |
| Dual-write window | Recommended during cutover: write new key (+ optionally old) until readers flipped |
| Rollback | Keep ability to read old `geo:drivers:{city}` briefly; feature-flag reader source if needed |

**Fields remain** during migration: do not delete `rides.city` / `drivers.homeCity` / catalog code in the cutover without a dedicated cleanup slice.

**Race / idempotency:** Assignment transactions unchanged. Candidate generation remains best-effort; empty Redis still degrades dispatch, not assignment correctness (ADR-004).

---

## 15. Explicit Non-Goals (this slice)

| Item | Done? |
| ---- | ----- |
| PBS import | **NO** |
| Firestore changes | **NO** |
| Redis changes | **NO** |
| N3 implementation changes | **NO** |
| N4 implementation | **NO** |
| Google Maps implementation | **NO** |
| GPS package | **NO** |
| Flutter changes | **NO** |
| API changes | **NO** |
| Deletion of existing city fields | **NO** |
| Production code changes | **NO** |

Only this decision document is added.

---

## 16. Final Next Slice

```text
N2C+N3 COORDINATE-PRIMARY CUTOVER
```

**Scope of that future slice (do not start now):**

1. Project accepted driver locations into `geo:drivers` (coordinate-primary).
2. Change nearby discovery to query by pickup lat/lng only (no city key).
3. Keep Firestore eligibility / freshness / accuracy / busy gates.
4. Dual-write or flagged cutover with proofs; no PBS import; no N4; no Maps; do not delete city fields yet.
5. Leave `rides.city` / `homeCity` as unused-or-optional for matching until a follow-up API soft-deprecation slice.

**Stop.** Do not implement in this slice.
