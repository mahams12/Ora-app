# City Dependency Audit (READ-ONLY)

**Status:** AUDIT COMPLETE — **NO IMPLEMENTATION**  
**Date:** 2026-09-21  
**Scope:** Determine whether `city` / `homeCity` is a product/domain requirement or primarily a Redis GEO / dispatch sharding optimization.  
**Authority:** Repository code + committed docs/ADRs only.  
**Explicit non-actions:** No production code changes, no Firestore writes, no PBS import, no N4/Maps/GPS/Redis redesign.

---

## 1. Executive Verdict

```text
REQUIRED_FOR_CURRENT_ARCHITECTURE_ONLY
```

### Why this verdict (evidence, not opinion)

| Claim | Evidence |
| ----- | -------- |
| City is **not** a ride-assignment correctness field | `createOffer` / `selectOffer` / progression / close / expire paths in `ride_service.ts` never read `ride.city`. Assignment SoT remains Firestore transactions. |
| City is explicitly documented as a **Redis shard selector** | [`RIDE-CITY-SCHEMA.md`](RIDE-CITY-SCHEMA.md): “City is a **client-asserted Redis shard selector**, not authorization to assign.” |
| Redis GEO itself is an **optimization**, not SoT | [`ADR-004`](../../architecture-final/ADRs/ADR-004-Redis-GEO-Optimization.md): Redis GEO for candidate generation; “never authoritative”; correctness via Firestore. |
| Without `homeCity`, core driver online + location still work | N2C skips `GEOADD` when `homeCity` missing (`geo_projection.ts` `missing_home_city`); N2A accept still succeeds. |
| Without usable `rides.city`, M0 open discovery still works | `publicOpenRide` **omits** `city`; open-list eligibility ignores city. |
| N3/N4 **require city only because** keys are `geo:drivers:{city}` | `geoDriversKey(city)` in `redis/types.ts`; N3 `parseNearbyQuery` requires `city`; N4 freeze says candidates come from N3 with city match. |
| Product “Pakistan-wide catalog” is a **coverage/UX/ops** layer, not proof that ride physics need a city enum | [`PAKISTAN-CITY-ARCHITECTURE.md`](PAKISTAN-CITY-ARCHITECTURE.md) freezes server catalog for nationwide selection UX; createRide today accepts **any** non-empty slug (no allowlist). |

**Rejected alternatives:**

- `REQUIRED_DOMAIN_DEPENDENCY` — rejected: fare, assignment, state machine, and M0 discovery do not need city for correctness.
- `OPTIONAL_OPTIMIZATION` — rejected: under **current** code, createRide and N3 **hard-require** city; removing it without redesign breaks those contracts.
- `OBSOLETE / SHOULD_BE_REMOVED` — rejected: city is actively wired into N2C/N3 and planned N4; removal would be a deliberate partition redesign, not cleanup of dead code.

---

## 2. Actual Dependency Map

| Component | Exact usage | Required for correctness? | Optimization only? | Evidence |
| --------- | ----------- | ------------------------- | ------------------ | -------- |
| `POST /v1/rides` create | Validates `body.city` via `normalizeCitySlug`; stores `rides.city` | **API contract yes** (400 if missing). **Ride physics no** | Shard selector for later N3/N4 | `ride_service.ts` ~521–528, ~590; `RIDE-CITY-SCHEMA.md` D-CITY-REQUIRED |
| `publicRide` response | Echoes `city` if present | No | Metadata exposure | `ride_service.ts` `publicRide` |
| `publicOpenRide` (M0) | **Does not include** city; does not filter by city | No | N/A | `ride_service.ts` `publicOpenRide` |
| Offer / select / progression / close / expire / no-show / rating | No city reads | No | N/A | `ride_service.ts` grep: city only at create + `publicRide` |
| `drivers.homeCity` field | Read by N2C projection + offline GEO removal | Not for availability SoT | **Yes** — chooses GEO key | `location_update_service.ts` passes `homeCity`; `geo_projection.ts` |
| N1 go-online | Does **not** read/write `homeCity` | No | N/A | `driver_availability_service.ts` `goOnline` |
| N1 go-offline | Reads `homeCity` only to tell Redis which GEO keys to `ZREM` | Availability write is Firestore-only | **Yes** (cleanup of optimization index) | `driver_availability_service.ts` `goOffline` |
| N2A location update | Does not require city in body; reads `homeCity` for post-accept projection | Location cursor SoT is Firestore | Projection is optional side effect | `location_update_service.ts` |
| N2C Redis GEO | `GEOADD geo:drivers:{normalizeCitySlug(homeCity)}` | Redis non-authoritative | **Yes** — partition key | `geo_projection.ts`, `N2C-redis-geo.md` |
| N3 nearby | Query param `city` required → `GEORADIUS geo:drivers:{city}`; marker city must match | Candidate list only; not assignment | **Yes** under current shard design | `nearby_service.ts` |
| N4 (planned) | Read `rides.city` → call N3; skip if missing | Planned dispatch invites only | Inherits N3 shard | `N4-dispatch-planning.md` D-CITY |
| City catalog (`cities/{id}`) | Schema + service; **not** consulted by createRide/N3 today | No runtime ride dependency yet | Future allowlist / UX SoT | `city_catalog_service.ts`; createRide has no catalog check |
| Flutter | **No** city field in ride request / models | No implemented dependency | Planned selector only | `RIDE-CITY-SCHEMA.md` Flutter audit; `mobile/lib` grep |
| Firestore queries | No live `.where('city'…)` on rides in auth-service | No | Planned index `driverStatus+homeCity` (docs) unused by N1–N3 code | Grep `src/**/*.ts`; `indexes.md` |
| Pricing / fees / auth | No city dependency in implemented paths | No | Schema mentions city on some planned fee docs | `ride_service.ts` pricing uses snapshot id |

---

## 3. Ride Lifecycle

```text
create → search/open → location → nearby → dispatch → offer → assignment → progression → closure → history
```

| Stage | `city` role | Mark |
| ----- | ----------- | ---- |
| **create** | Required request field; stored on `RideDoc` | **REQUIRED** (current API) |
| **search/open (M0)** | Not exposed; not filtered | **NOT USED** |
| **location (N2A)** | Not in location body; driver `homeCity` only for Redis side effect | **OPTIONAL** (projection) |
| **nearby (N3)** | Required query param; selects GEO key + marker match | **REQUIRED** (current N3) |
| **dispatch (N4)** | Planned: read `rides.city` → N3; skip if absent | **REQUIRED** (planned architecture) / **NOT USED** (code not implemented) |
| **offer** | Not read | **NOT USED** |
| **assignment** | Not read | **NOT USED** |
| **progression** | Not read | **NOT USED** |
| **closure** | Not read | **NOT USED** |
| **history** | Not required in Flutter history models; may appear if client stores `publicRide` | **OPTIONAL** / **NOT USED** in backend history queries |

---

## 4. Redis Analysis

### Current keys involving city

| Key | Role | City required? |
| --- | ---- | -------------- |
| `geo:drivers:{city}` | GEO set / ZSET of driver members | **Yes** — city is part of key name |
| `driver:online:{driverId}` | TTL marker JSON; includes `city: string \| null` | Marker exists without city; GEO membership does not |

Helpers: `geoDriversKey(city)`, `normalizeCitySlug` — `backend/auth-service/src/redis/types.ts`.

### Why was city chosen as the shard?

Repository rationale chain:

1. Matching docs assume `GEORADIUS geo:drivers:{city}` ([`matching-engine.md`](../../algorithms/matching-engine.md), [`12-matching-and-dispatch.md`](../../architecture-final/12-matching-and-dispatch.md)).
2. N2C implements that key shape; N3 queries the same shape.
3. N4 freeze chose client `rides.city` specifically as the **non-geocode** way to pick the same shard ([`N4-dispatch-planning.md`](N4-dispatch-planning.md) D-CITY).
4. [`RIDE-CITY-SCHEMA.md`](RIDE-CITY-SCHEMA.md) states the trust model: lying about city mainly yields empty nearby / self-DoS — i.e. **partitioning**, not authorization.

There is **no** repository proof that Redis GEO *must* be city-sharded. Redis GEO operates on coordinates inside a key; the key can be global (`geo:drivers`) or another partition (geohash cell, H3, region id).

### Could coordinates alone support candidate generation?

**Yes, architecturally.** `GEORADIUS` / `GEOSEARCH` need a key + lng/lat + radius. City is not a Redis GEO primitive. A single national `geo:drivers` key (or geohash-sharded keys derived from coordinates) can return the same spatial candidates. Eligibility (approved, online, fresh, accuracy, not busy) already uses Firestore + marker fields independent of city.

### What would be lost by removing city partitioning?

| Loss | Severity |
| ---- | -------- |
| Bounded key size / blast radius per metro | Operational / scale risk if one huge GEO set |
| Simple ops mental model (“Lahore supply”) | Ops UX |
| Alignment with planned catalog / serviceAreas naming | Product/ops naming |
| Current N3/N4 contracts as written | **Breaking** without redesign |

### Correctness guarantees depending on city?

**None for assignment.**  
City mismatch only affects **which GEO set is searched** and N3’s marker city equality filter (prevents cross-shard ghosts). Wrong city → empty or wrong candidate pool → fewer offers, not corrupt `assignedDriverId`.

### Is city actually needed by Redis GEO?

**No.** Needed by **Ora’s current key convention**, not by Redis GEO.

---

## 5. N3 Analysis

**Does N3 fundamentally require city?**

- **Fundamentally (spatial nearby):** No — needs pickup lat/lng + radius + online driver positions.
- **In this repository’s N3 implementation:** Yes — `city` is a required query parameter and the Redis key selector (`nearby_service.ts` `parseNearbyQuery` / `geoDriversKey(parsed.city)`).

N3 also re-checks `marker.city === parsed.city` after GEORADIUS. That is shard-consistency hygiene, not a domain law of ride-hailing.

**Do not change N3** (audit only). Conclusion: N3’s city requirement is **inherited from N2C’s sharded key design**.

---

## 6. N4 Analysis

**Does N4 fundamentally require city?**

N4 is **not implemented**. The freeze says:

- Candidates = `NearbyDriversService.findNearby` (N3).
- `rides.city` chosen because there is no geocoder and pickup has no city.
- Rides without usable `city` must be **SKIP**ped by N4 — not invented.

Therefore N4 requires city **only as the planned way to call N3 under the current shard**. An alternate candidate API (coordinate-only GEORADIUS on a non-city key) would let N4 dispatch without a static city catalog.

**Do not implement N4** (audit only).

---

## 7. PBS Catalog Impact

> If city is only an optimization and not a domain requirement, is the Pakistan-wide 565-city PBS catalog actually necessary for the core ride flow?

### Answer

**No — not for the core ride flow.**

| Core capability | Needs PBS 565 catalog? | Needs any `city` string today? |
| --------------- | ---------------------- | ------------------------------ |
| Create ride (coords + fare + state) | No | Yes (API requires a slug; **any** non-empty slug works — no allowlist) |
| M0 open discovery / offers / assignment / progression | No | No |
| N2A location accept | No | No |
| N2C/N3 under **current** shard design | No PBS list required | Needs **matching** slug between `rides.city` and `drivers.homeCity` |
| Controlled passenger city picker UX | **Yes** (product choice in Pakistan-wide freeze) | Catalog ids |
| Ops-controlled coverage / disable cities | **Yes** (future catalog validation) | Catalog |
| Licensing-gated production import | Separate legal gate — **not** a ride-physics need | N/A |

### What remains without the catalog

Still possible with current code:

- Ride create/search/offer/assign/complete with client-supplied free-text city slugs.
- Driver location streams + availability.
- Redis GEO **if** `homeCity` is seeded to match those slugs (even a tiny ops set).
- Full fare/assignment correctness path.

What does **not** remain / stays blocked:

- Authoritative Pakistan-wide selectable city UX.
- Allowlisted createRide validation.
- Justified production import of 565 PBS-derived rows (licensing still blocked anyway).

**PBS import is not authorized and is not required to continue core matching architecture decisions.**

---

## 8. Google / GPS Impact (architectural comparison only)

**Not implemented. Not recommended as a next coding slice here.**

Separate concerns:

| Concern | Role | Needs PBS city catalog? |
| ------- | ---- | ----------------------- |
| GPS / location acquisition | Produce lat/lng (/accuracy/time) | No |
| Maps rendering | UI display | No |
| Geocoding / place lookup | Address ↔ coordinates / maybe city label | Optional convenience |
| Spatial candidate generation | Nearby drivers by distance | No — needs positions + index |

### CURRENT vs POSSIBLE

| Dimension | CURRENT: coordinates + city shard | POSSIBLE: coordinates + spatial index (no city / non-city partition) |
| --------- | --------------------------------- | -------------------------------------------------------------------- |
| **Correctness** | Assignment still Firestore; city only scopes candidates | Same if eligibility gates preserved |
| **Scalability** | Smaller per-city GEO sets; risk of wrong-shard empty supply | Single/global or geohash shards; may need different ops tuning |
| **Redis usage** | `geo:drivers:{city}` + `driver:online:{id}` | Could be `geo:drivers` or `geo:drivers:{cell}` + same markers |
| **Privacy** | City slug on ride doc; open list hides city today | Fewer stable region labels on rides if city omitted |
| **Stale location** | Marker TTL 30s + N3 freshness 15s / accuracy 50m | Same mechanisms apply without city |
| **Dispatch** | N4 planned to pass `rides.city` into N3 | N4 could pass only pickup lat/lng into a city-free nearby API |
| **Operational complexity** | Must keep passenger city ↔ driver homeCity aligned; catalog ops | Must operate spatial index + maybe multi-cell query; less catalog coupling |

**Do not claim Google Maps is required for nearby-driver matching.** Maps ≠ GEO index.

---

## 9. Recommendation (evidence-only; do not implement)

1. **Treat `city` / `homeCity` as a current-architecture partition key**, not as a ride-domain invariant.
2. **Do not proceed with PBS 565 production import** as if it were blocking core ride/dispatch correctness — it is not (and licensing remains blocked).
3. **Keep existing fields for now** (do not delete): removing them without a partition redesign would break createRide + N3 contracts.
4. **Before more catalog / Maps / N4 build-out**, freeze a partition strategy decision:
   - **A.** Keep city-sharding (then catalog + Flutter selector + homeCity writer remain justified as ops/UX).
   - **B.** Move candidate generation to coordinate-primary indexing (then city becomes optional metadata / analytics; PBS catalog is not a matching prerequisite).
5. Prefer wording: **keep `city` as optional-or-shard metadata pending ADR**, not “remove immediately,” and not “domain-required forever.”

---

## 10. Scope / Change Audit

| Item | Changed? |
| ---- | -------- |
| production code changed | **NO** |
| Firestore changed | **NO** |
| PBS catalog imported | **NO** |
| API changed | **NO** |
| Flutter changed | **NO** |
| Redis schema changed | **NO** |
| N3 changed | **NO** |
| N4 implemented | **NO** |

Only this audit document was added.

---

## Appendix A — Key file anchors

| Area | Path |
| ---- | ---- |
| createRide city require | `backend/auth-service/src/rides/ride_service.ts` |
| RideDoc.city comment | `backend/auth-service/src/rides/types.ts` |
| GEO key | `backend/auth-service/src/redis/types.ts` `geoDriversKey` |
| N2C projection | `backend/auth-service/src/redis/geo_projection.ts` |
| N1 offline GEO cleanup | `backend/auth-service/src/drivers/driver_availability_service.ts` |
| N2A → N2C handoff | `backend/auth-service/src/location/location_update_service.ts` |
| N3 | `backend/auth-service/src/drivers/nearby_service.ts` |
| ADR-004 | `docs/architecture-final/ADRs/ADR-004-Redis-GEO-Optimization.md` |
| Ride city freeze | `docs/implementation/n-series/RIDE-CITY-SCHEMA.md` |
| N4 freeze | `docs/implementation/n-series/N4-dispatch-planning.md` |
| Pakistan catalog product freeze | `docs/implementation/n-series/PAKISTAN-CITY-ARCHITECTURE.md` |

---

## Appendix B — Exact next architectural slice

```text
SLICE: CITY-PARTITION-STRATEGY DECISION (docs-only freeze)
```

**Goal:** Explicitly choose whether Ora’s matching index remains `geo:drivers:{city}` or becomes coordinate-primary (global/geohash/other), and freeze consequences for:

- `rides.city` required vs optional
- `drivers.homeCity` required vs optional
- PBS catalog necessity for matching vs UX-only
- N4 candidate input shape
- Whether Flutter city selector is a matching prerequisite

**Must not:** import PBS, implement Maps, implement N4, mutate Redis, or delete fields.
