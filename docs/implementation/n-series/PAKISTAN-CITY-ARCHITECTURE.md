# Pakistan-Wide City / Service-Area Architecture

**Status:** **ARCHITECTURE FROZEN** — Slice 1 catalog **data model IMPLEMENTED**; Slice 2D **approved dataset** (565 cities); Slice 2E **import gate YELLOW** (`FIRESTORE_WRITE_STATUS=BLOCKED`, licensing); catalog API / Flutter selector **NOT IMPLEMENTED**  
**Freeze date:** 2026-09-21  
**Audit status:** **YELLOW** — nationwide model frozen; Slice 1 done; **Slice 2E IMPORT BLOCKED ON LICENSING**; remaining SEPARATE FUTURE SLICES before Flutter city UI can ship  
**Product requirement:** Ora is intended to operate **Pakistan-wide** (not a small fixed launch-city set).  
**Authority:** Code + ADRs + this freeze. Supersedes the “small Flutter const launch catalog” membership model in [`CITY-SELECTION-PLANNING.md`](CITY-SELECTION-PLANNING.md).

**Do not implement** catalog API, selector, polygons, or N4 in companion tasks unless explicitly scoped. **Do not invent** a Pakistan city list.

---

## Audit — what exists today

| Artifact | Reality |
| -------- | ------- |
| `POST /v1/rides` `city` | **IMPLEMENTED** — any non-empty `normalizeCitySlug`; **no catalog allowlist**; **not** used as N3/N4 matching gate after coordinate-primary |
| `rides.city` | Stored normalized slug — **metadata** for matching purposes |
| N3 `findNearby` | **Coordinate-primary** — lat/lng → `geo:drivers`; city **not** required |
| N2C projection | `geo:drivers` (+ legacy dual-write if homeCity); homeCity **not** required |
| Flutter city UI / catalog | **Missing** (not an N4 matching blocker) |
| `serviceAreas` Firestore | **Schema docs only** — **not implemented** (geometry/zones future) |
| `cities` Firestore catalog | **IMPLEMENTED (Slice 1)** — `cities/{cityId}` + `CityCatalogService`; **not populated** with Pakistan dataset |
| Pakistan city dataset in repo | **Slice 2D APPROVED** (`final/approved_city_catalog.json`, 565) — **NOT SEEDED**; **Slice 2E** dry-run only — `FIRESTORE_WRITE_STATUS=BLOCKED` (`LICENSING_GATE`) |
| Geocoder / maps / GPS city | **None** |

---

## Product requirement (FROZEN) — D-PK-COVERAGE

**Ora coverage intent = Pakistan-wide.**

Therefore:

| Approach | Verdict |
| -------- | ------- |
| A. Small hardcoded Flutter launch list | **SUPERSEDED / REJECTED** as product SoT |
| B. Huge Pakistan DB inside Flutter APK | **REJECTED** — update lag, size, drift from drivers |
| C. Backend city / service-area catalog API | **REQUIRED** (future slice) |
| D. Server-managed Firestore catalog | **REQUIRED** as durable SoT (align with planned `serviceAreas` or sibling `cities`) |
| E. Free-text city only | **REJECTED** as primary UX — typo shards, no ops control |
| F. Hybrid | **CHOSEN** — server catalog SoT + Flutter searchable UI over fetched/cached active cities |

---

## Recommended architecture (FROZEN — catalog UX; matching is coordinate-primary)

```text
Server city catalog (Firestore, active rows)     ← UX / ops / future allowlist
        ↓
Backend GET catalog API (future)
        ↓
Flutter searchable bottom sheet (future)
        ↓
User may select canonical city id (metadata)
        ↓
POST /v1/rides { city?, pickup lat/lng, … }
        ↓
rides.city = optional metadata slug (create API may still require today)
pickup lat/lng = spatial matching input
        ↓
N3 / N4: GEORADIUS geo:drivers around pickup   ← coordinate-primary
drivers.homeCity = optional metadata (legacy dual-write only)
```

### Layering

```text
Canonical CITY (catalog id)     ← UX/ops metadata; NOT Redis matching shard
    ↓ (matching)
Live coordinates → geo:drivers
    ↓ (future)
Service Area record (display, active, optional polygon, zones)
```

**N3/N4 matching:** lat + lng (+ radius). City is **not** the shard key. Polygons remain a **future** eligibility overlay.

---

## Decision matrix

| ID | Current | Options | **Chosen** | Reason | Consequence |
| -- | ------- | ------- | ---------- | ------ | ----------- |
| **D-PK-COVERAGE** | Implicit small list in prior UI freeze | Limited launch; Pakistan-wide | **Pakistan-wide** | Product requirement | Reject Flutter-only closed launch list as SoT |
| **D-CITY-MEANING** | Client string → Redis shard | Municipality; district; free text; **canonical service city id** | **Canonical Ora city id = catalog / metadata id** (matching uses coordinates) | Catalog UX + optional metadata | Display name ≠ storage id; **not** N3/N4 GEO key |
| **D-CITY-CATALOG-SOURCE** | None | Flutter const; huge APK DB; **server Firestore + API** | **Server-managed catalog** | Add/disable cities without app store; shared with drivers | **SEPARATE FUTURE SLICE** |
| **D-CITY-CATALOG-SCHEMA** | serviceAreas doc sketch | — | Conceptual schema below | Stable ids + active flag | Do not populate dataset here |
| **D-CITY-UX** | Prior: closed sheet | Closed list; **searchable sheet**; free text | **Searchable bottom sheet** over catalog (local filter; no new package required for MVP search) | Nationwide cardinality | Supersedes closed-only list UX |
| **D-CITY-ID** | `normalizeCitySlug` | New scheme | **Catalog `id` already slug-shaped; store via `normalizeCitySlug` only** | One normalizer | No second system |
| **D-CITY-VALIDATION** | Slug non-empty only | Trust any string; **allowlist active ids** | **Backend must validate `city` ∈ active catalog** | Prevent arbitrary shard spam / typo cities | **SEPARATE FUTURE SLICE** (today: syntactic only) |
| **D-CITY-UNKNOWN** | Any slug accepted | Accept; reject | **Reject** once catalog validation exists (`VALIDATION_ERROR`) | Catalog authority | Until then: gap (documented) |
| **D-CITY-NO-SUPPLY** | N3 empty `[]` | Block create; allow create | **Allow create**; empty nearby/dispatch is OK | Supply ≠ catalog membership | No fake drivers |
| **D-HOMECITY-COMPATIBILITY** | Same slug function | Divergent ids | **`rides.city` and `drivers.homeCity` MUST share catalog ids** | Same Redis keys | homeCity writer still future |
| **D-NEW-CITY-OPS** | Manual seed only | App update; **catalog activate** | Activate city in catalog → drivers use id → GEO fills → rides use id | Ops without Flutter release | Admin tooling future |
| **D-CATALOG-FAILURE** | N/A | Soft fail; hard gate | **Cannot select/submit city if catalog unavailable and no usable cache** | Honesty | Exact cache rules = future slice |

---

## D-CITY-MEANING (FROZEN)

| Concept | Role |
| ------- | ---- |
| **displayName** | UI only (e.g. localized label) |
| **canonical city id** | Stable slug stored as `rides.city` / used as `drivers.homeCity` |
| **Redis matching key** | **`geo:drivers`** (coordinate-primary) — **not** city-sharded |
| **Legacy dual-write** | Optional `geo:drivers:{canonicalId}` when homeCity present — **not** N3/N4 read path |

`rides.city` is **not** “whatever the user typed as a place name.” It is the **Ora service-city identifier** (metadata / catalog). It is **not** the spatial matching boundary.

---

## D-CITY-CATALOG-SCHEMA — IMPLEMENTED Slice 1 (`cities/{cityId}`)

**Chosen collection:** `cities/{cityId}` (not `serviceAreas`). Reason: current city concept is a canonical shard/id + display metadata, not a polygon. `serviceAreas` remains planned for future geometry/zones.

**Writer rule:** normalize with existing `normalizeCitySlug()` before write; reject empty; reject non-slug shape after normalize (`^[a-z0-9]+(?:-[a-z0-9]+)*$`). Document id = canonical id.

**IMPLEMENTED NOW fields:**

```text
id            string   // = document id = rides.city = homeCity (metadata ids)
displayName   string
countryCode   "PK"     // enforced exactly
active        boolean
createdAt     string   // ISO
updatedAt     string   // ISO
```

**NOT IMPLEMENTED:** catalog HTTP API, Pakistan city population, createRide allowlist, Flutter selector, homeCity writer, polygons, N4.

---

## D-CITY-UX (FROZEN; supersedes closed-list-only)

1. Compose screen: “Pickup city” control  
2. Opens `showOraBottomSheet`  
3. Search/filter over **fetched active catalog** (simple in-memory filter — reuse Ora text field; **no new package** without separate approval)  
4. User selects one row → form holds `cityId` + displayName  
5. Submit sends `city: cityId`  
6. Persistence: form-scoped MVP (unchanged)

Closed tiny list is **not** the nationwide product model.

---

## D-CITY-VALIDATION & UNKNOWN (FROZEN target)

**Target (after catalog slice):**

```text
createRide city
→ normalizeCitySlug
→ lookup active catalog by id
→ miss / inactive → 400 VALIDATION_ERROR
→ hit → store canonical id
```

**Today (code):** only non-empty slug — **insufficient** for Pakistan-wide trust. Hardening is **SEPARATE FUTURE SLICE**. Do not weaken create requirement for `city`.

---

## D-CITY-NO-SUPPLY (FROZEN)

Catalog membership ≠ online drivers.

- Ride create **allowed** for active city with zero GEO members.  
- N3 → healthy `candidates: []` or Redis fail `DEPENDENCY_ERROR`.  
- N4 → no fabricated supply.

---

## D-HOMECITY-COMPATIBILITY (FROZEN)

| Field | Must use |
| ----- | -------- |
| `rides.city` | Canonical catalog id |
| `drivers.homeCity` | **Same** canonical catalog id |

Divergence of catalog ids between UX surfaces is an **ops/catalog** concern. **Matching** uses live coordinates → `geo:drivers`, not city label equality. homeCity **writer** remains a separate ops/onboarding slice if desired for metadata/legacy dual-write.

---

## D-NEW-CITY-OPS (FROZEN process; no admin UI yet)

```text
1. Add/activate city in server catalog (id + displayName + active=true)
2. Drivers may set homeCity = same id (optional metadata / legacy dual-write)
3. Passengers may select same id → rides.city (metadata; create API may still require)
4. N3/N4 match via pickup lat/lng → geo:drivers (NOT geo:drivers:{id})
5. To pause selections: active=false → stop new catalog selections (existing rides keep stored city metadata)
```

---

## D-CATALOG-FAILURE (FROZEN intent)

- No city selected → cannot submit (existing honesty).  
- Catalog request fails and **no** usable cache → show error; **do not** invent city; **do not** fall back to free-text nationwide.  
- Stale cache policy = **future slice** (TTL, refresh).

---

## Option evaluation (summary)

| Option | Pakistan-wide | Add cities | Typos | App update | Backend authority | N3/N4 |
| ------ | ------------- | ---------- | ----- | ---------- | ----------------- | ----- |
| A Small Flutter list | No | App release | Low if closed | Yes | Weak | OK if ids match |
| B Huge Flutter DB | Maybe | App release | Medium | Yes | Weak | Drift risk |
| C+D Server catalog + API | Yes | Ops | Low | No | Strong | Strong |
| E Free text | Yes loosely | N/A | High | No | Weak today | Shard chaos |
| **F Hybrid (chosen)** | Yes | Ops | Low | No | Strong | Strong |

---

## N3 / N4 compatibility (UPDATED — coordinate-primary)

**Matching (authoritative):**

```text
pickup lat/lng
→ NearbyDriversService.findNearby({ lat, lng, radiusKm })
→ geo:drivers
→ N4 waves (when implemented)
```

City catalog / `rides.city` / `drivers.homeCity` remain **UX/ops/metadata**. They **must not** be reintroduced as Redis matching shard keys.

See [`CITY-PARTITION-STRATEGY-DECISION.md`](CITY-PARTITION-STRATEGY-DECISION.md) and [`N4-dispatch-planning.md`](N4-dispatch-planning.md).

**Do not** redesign offer/assignment. Catalog work does **not** redefine N3/N4 spatial contracts.

---

## Superseded decisions

| Prior | Status |
| ----- | ------ |
| [`CITY-SELECTION-PLANNING.md`](CITY-SELECTION-PLANNING.md) “small Flutter const launch catalog” as product SoT | **SUPERSEDED** by D-PK-COVERAGE + D-CITY-CATALOG-SOURCE |
| “Product approves a tiny hardcoded membership then ship” as final model | **SUPERSEDED** — membership lives in **server catalog** |
| Backend “no allowlist” (RIDE-CITY-SCHEMA trust note) as permanent | **SUPERSEDED as end-state** — allowlist validation is now a **required future hardening**; current code remains syntactic until that slice |

UX freeze that remains useful: bottom sheet + explicit selection + form-scoped + required city + no GPS/geocode.

---

## Separate future slices (order)

1. ~~**City catalog data model**~~ — **DONE (Slice 1):** `cities/{cityId}` + `CityCatalogService` + unit/live proofs  
2. **Populate / activate Pakistan-wide (or phased) active cities** — **Slice 2D:** approved service-city dataset ready; **Slice 2E:** import prep + dry-run gate only; **Firestore population BLOCKED** on licensing (`BLOCKED_PENDING_LICENSING_REVIEW`).  
3. **Backend catalog list API** (`GET` active cities)  
4. **Backend createRide catalog validation**  
5. **Flutter searchable city selector** wired to API (+ optional cache)  
6. **homeCity writer** aligned to catalog ids  
7. Optional: polygons / point-in-polygon (post-N3) — may use `serviceAreas`  
8. N4 waves (already frozen separately)

---

## Slice 2 — data authority gate (2026-09-21)

**Status: YELLOW — BLOCKED ON PRODUCT/OPS CITY DATA**

### Classification

**B / C** — only test/doc/example fixtures exist; **no** authoritative product/ops Pakistan city catalog in:

- repository files / seed scripts / CSV / JSON fixtures
- backend data loaders
- Flutter catalogs
- approved product docs (beyond coverage intent)
- ops configuration
- agent/user attached stores (empty)

Lahore / Karachi / Islamabad appearances are **test & doc examples only** — not approved catalog membership.

### NOT performed

- No Firestore population
- No seed/import script with invented cities
- No activation of geographically real cities without product approval

### Product / ops data required before Slice 2 can proceed

An explicit approved dataset (file or equivalent) with **at least**:

```json
[
  {
    "id": "<canonical-slug>",
    "displayName": "<official display name>",
    "active": true
  }
]
```

Rules:

- `countryCode` is always `"PK"` (may be omitted in source; importer enforces PK)
- `id` must already be slug-compatible with `normalizeCitySlug()` (or an explicit, non-ambiguous transform table must be approved)
- `active` must be **explicit per row** (or one explicit ops rule: “all rows in this file are active=true”)
- “Pakistan-wide” coverage intent alone is **not** a city list — do not infer membership from geography
- Source must be named (ops sheet, product sign-off, attached file path)

Until that arrives: **PRODUCT / OPS DATA REQUIRED — DO NOT PROCEED** to population or Slice 3 assumptions of a filled catalog.

---

## Explicit non-goals (this freeze)

Implementing selector, catalog, API, GPS, geocoding, maps, IP, address parse, hardcoded nation list, N4, Redis key redesign, free-text-as-primary UX.

---

## Related

- [`CITY-SELECTION-PLANNING.md`](CITY-SELECTION-PLANNING.md) (partially superseded)  
- [`RIDE-CITY-SCHEMA.md`](RIDE-CITY-SCHEMA.md)  
- [`N3-nearby-planning.md`](N3-nearby-planning.md)  
- [`N4-dispatch-planning.md`](N4-dispatch-planning.md)  
- `docs/database/firestore-schema.md` § `cities` (implemented) / § `serviceAreas` (planned geometry)  

---

## Verdict

> **Pakistan-wide coverage requires a server-managed city catalog + validation + searchable Flutter UI.**  
> **Small Flutter launch lists are not the product architecture.**  
> **Do not implement the selector until catalog source + validation slices are planned/shipped (or an implementation prompt explicitly sequences them).**
