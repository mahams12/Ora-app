# N3 — Nearby Drivers

**Status:** **IMPLEMENTED** (2026-09-21)  
**Freeze date:** 2026-09-21  
**Authority:** Code under `backend/auth-service/src` + this freeze outweigh planning prose that conflicts.  
**Depends on:** N1, N2A, N2C (**IMPLEMENTED**).  
**Does not depend on:** N2B (**DEFERRED**).  
**Must not become:** M0 open rides, dispatch, offers, assignment, FCM, RTDB, maps, ETA, ranking.

---

## Implementation closure

| Item | Location |
| ---- | -------- |
| Route | `GET /v1/internal/drivers/nearby` — `routes/internal.ts` |
| Service | `drivers/nearby_service.ts` |
| Redis GEORADIUS | `redis/client.ts`, `redis/memory_redis.ts`, `redis/types.ts` |
| Vitest | `src/__tests__/nearby.test.ts` |
| Unit proof | `npm run test:phase-n3-unit-proof` |
| Live Redis proof | `REDIS_URL=… npm run test:nearby-redis-proof` |

**Ops dependency (D7):** ~~`drivers.homeCity` required for GEO~~ **SUPERSEDED** by coordinate-primary cutover — homeCity optional; matching uses `geo:drivers`.

---

## Product meaning (FROZEN)

**NEARBY = drivers near passenger pickup** via Redis GEO candidate generation (physical distance).

Not:

- open rides near driver (`GET /v1/rides/open` = M0)
- dispatch / matching waves / offers / assignment
- FCM / RTDB / maps / ETA / ranking
- city / homeCity label matching

---

## Prerequisite reality

| Item | Status |
| ---- | ------ |
| N1 / N2A / N2C | IMPLEMENTED (N2C coordinate-primary) |
| Redis radius command on `RedisGeoClient` | **IMPLEMENTED** (`georadius`) |
| Nearby HTTP route | **IMPLEMENTED** — internal worker path |
| `drivers.homeCity` for matching | **NOT REQUIRED** |
| Firestore geo fallback | MUST NOT exist |
| RTDB for N3 | MUST NOT be required |

---

## Frozen flow (coordinate-primary)

```text
Internal worker (X-Ora-Worker-Token)
  ↓
validate lat + lng + radiusKm + limit
  (city optional — ignored for matching if present)
  ↓
GEORADIUS geo:drivers lng lat radiusKm km ASC WITHCOORD WITHDIST COUNT {redisCount}
  ↓
for each member (bounded):
  require GET driver:online:{driverId}
  parse marker; freshness ≤15s; accuracy ≤50
  Firestore users: approved driver, not banned/disabled
  Firestore drivers: availabilityState == online
  Firestore rides: not busy (ASSIGNED|EN_ROUTE|ARRIVED|STARTED)
  ↓
sort by distanceKm ASC; take API limit
  ↓
200 internal candidate DTO
```

**Old key (legacy dual-write only):** `geo:drivers:{city}` — **not** consulted by N3.
---

## D1 — Route (FROZEN)

**Decision:** `GET /v1/internal/drivers/nearby`

**Not:** `GET /v1/drivers/nearby` for N3 MVP.

**Reasoning:**

- Existing worker APIs live under `/v1/internal/*` with `createInternalWorkerMiddleware` (`X-Ora-Worker-Token` / `ORA_INTERNAL_WORKER_TOKEN`) — see `routes/internal.ts`, `middleware/internal_worker.ts`, `app.ts`.
- Architecture-final named `/v1/drivers/nearby` for a **dual** auth model (internal + future passenger). N3 MVP is **internal-only**; mounting under `/v1/drivers` next to JWT `go-online`/`go-offline` invites the wrong security model.
- Exact coordinates are allowed only for trusted internal callers → internal mount matches privacy.

**Mapping note:** Architecture-final `GET /v1/drivers/nearby` remains a **planning alias**; N3 MVP implements the internal path. A future passenger-coarse surface needs a separate freeze.

---

## D2 — Radius bounds (FROZEN)

| Bound | Value | Unit |
| ----- | ----- | ---- |
| Default | `10` | km |
| Minimum | `1` | km |
| Maximum | `25` | km |

**Semantics:** Finite number; must satisfy `1 ≤ radiusKm ≤ 25`. Default when omitted: `10`.

**Reasoning:** Default `10` matches matching-engine / architecture-final. Cap prevents unbounded GEO fanout. Min `1` avoids micro-radius spam while remaining useful. Wave radius expansion is **N4**, not N3.

---

## D3 — Limit vs Redis COUNT (FROZEN)

| Knob | Value |
| ---- | ----- |
| API `limit` default | `30` |
| API `limit` max | `100` |
| API `limit` min | `1` |
| Redis `COUNT` | **Fixed `100`** (not derived from `limit`) |
| Pagination / cursor | **None** |

**Semantics:**

1. Redis returns up to **100** members (ASC by distance, WITHCOORD WITHDIST).
2. Server applies freshness / Firestore filters in order.
3. Response includes at most **`limit`** surviving candidates (still ASC by `distanceKm`).

**Reasoning:** Matching-engine already freezes COUNT 100. Fixed over-fetch compensates for stale/busy drops without a second query. Deriving COUNT from `limit` adds complexity without removing the hard 100 cap. No cursor keeps N3 minimal.

---

## D4 — Redis command (FROZEN)

**Decision:** **`GEORADIUS`** (not `GEOSEARCH`).

**Parameters (conceptual):**

```text
GEORADIUS geo:drivers {lng} {lat} {radiusKm} km ASC WITHCOORD WITHDIST COUNT 100
```

Note Redis argument order: **longitude, latitude**.

**Reasoning:** Coordinate-primary cutover ([`CITY-PARTITION-STRATEGY-DECISION.md`](CITY-PARTITION-STRATEGY-DECISION.md)). `ioredis` supports GEORADIUS. Legacy `geo:drivers:{city}` is dual-write only.

---

## D5 — Freshness (FROZEN)

**N2C marker TTL remains 30s — do not change in N3.**

**N3 freshness gate (independent):**

```text
fresh ⇔ marker exists
      ∧ lastLocationTs is a finite number
      ∧ (serverNowMs - lastLocationTs) >= 0
      ∧ (serverNowMs - lastLocationTs) <= 15_000
```

| Case | Behavior |
| ---- | -------- |
| Marker key missing / TTL expired | Drop candidate |
| Missing / non-numeric `lastLocationTs` | Drop |
| Malformed JSON marker | Drop |
| `lastLocationTs` in the future (`> serverNowMs`) | Drop (reject clock skew / bad client) |
| Age `> 15_000` ms | Drop (stale) |
| `accuracy` missing or `> 50` | Drop |
| Marker `city` present and ≠ request normalized city | Drop |

**Accuracy gate (FROZEN):** `accuracy <= 50` (metres), aligned with N2A.

---

## D6 — Redis failure error (FROZEN)

| Condition | HTTP | Code | Body |
| --------- | ---: | ---- | ---- |
| Redis unset / client null / command throws / timeout | **503** | **`DEPENDENCY_ERROR`** | `{ error: { code, message }, requestId }` via `sendApiError` |
| Worker token missing/misconfigured | 503 | `INTERNAL` | Existing internal middleware |
| Bad worker token | 403 | `FORBIDDEN` | Existing |
| Healthy Redis, zero candidates after filters | **200** | — | `candidates: []` |

**Message (suggested):** `Nearby candidate generation is temporarily unavailable.`  
**Logging:** `logSafe` with error type only — no tokens, no full Redis URLs with secrets.

**Reasoning:** `docs/api/error-codes.md` already defines `DEPENDENCY_ERROR` 503 for Redis/Firestore/Maps dependency failure. Distinguishes outage from empty supply. Aligns with phase-1.6 “no uncontrolled full-driver scan” / no canonical Firestore geo fallback. Fail closed — never silent `[]` on Redis failure.

---

## D7 — homeCity population (SUPERSEDED for matching)

**Coordinate-primary cutover:** `homeCity` is **optional metadata** / legacy dual-write only.

- N2C projects to `geo:drivers` **without** requiring homeCity.
- N1 still may read homeCity on go-offline for **legacy** city-key ZREM cleanup.
- N3 **must not** require homeCity or city label consistency for candidacy.
- A homeCity writer remains optional ops/UX — **not** a matching prerequisite.

**Previous D7 “empty GEO without homeCity” limitation is lifted** for the primary index.

---

## D8 — City + worker trust (UPDATED)

| Question | Decision |
| -------- | -------- |
| Is `city` mandatory for nearby? | **No** — optional echo only |
| Used for GEO key selection? | **No** |
| Used as authorization? | **No** |
| lat/lng validation | Finite; `lat ∈ [-90,90]`, `lng ∈ [-180,180]` |
| Empty / unknown spatial miss | **200** `candidates: []` |
| Polygon / service-area | **No** in N3 |

**Privacy / logging:** Do not log worker token. May log `city`, candidate counts, durations. Exact coords only in internal response body.

---

## Cross-check (consistency)

| Check | Result |
| ----- | ------ |
| Route matches internal caller | Yes — `/v1/internal/...` + worker token |
| City model matches N2C | Yes — same slug + `geo:drivers:{city}` |
| Redis command matches docs + ioredis | Yes — `GEORADIUS` |
| COUNT / radius bounded | Yes — COUNT 100; radius 1–25 |
| Freshness vs marker TTL | Yes — N3 15s gate; N2C TTL 30s unchanged |
| Redis fail ≠ empty supply | Yes — 503 `DEPENDENCY_ERROR` vs 200 `[]` |
| homeCity explicit | Yes — D7 dependency |
| No public coords | Yes — internal only |
| No new Redis keys | Yes |
| No RTDB / dispatch / offers | Yes |

---

## Final frozen N3 contract

| Item | Frozen value |
| ---- | ------------ |
| **Route** | `GET /v1/internal/drivers/nearby` |
| **Auth** | `X-Ora-Worker-Token` == `ORA_INTERNAL_WORKER_TOKEN` (≥16 chars configured) |
| **Inputs** | Query: `city` (required), `lat`, `lng` (required), `radiusKm` (optional), `limit` (optional). No `rideId`. |
| **Defaults** | `radiusKm=10`, `limit=30` |
| **Bounds** | `radiusKm ∈ [1, 25]`; `limit ∈ [1, 100]` |
| **Redis command** | `GEORADIUS` … `km ASC WITHCOORD WITHDIST COUNT 100` |
| **Redis COUNT** | Fixed **100** |
| **Freshness** | `0 ≤ serverNow - lastLocationTs ≤ 15000` ms; future/missing/malformed → drop |
| **Accuracy** | `accuracy ≤ 50` |
| **City/shard** | Mandatory normalized `city`; single shard; no geocoder; no multi-shard |
| **Firestore checks** | `users` approved/active; `drivers.availabilityState==online`; busy ride filter |
| **Busy states** | `DRIVER_ASSIGNED`, `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, `RIDE_STARTED` |
| **Response** | `{ data: { city, pickup, radiusKm, candidates:[{ driverId, distanceKm, lat, lng, lastLocationTs, accuracy }] }, requestId, timestamp }` |
| **Errors** | `VALIDATION_ERROR` 400; `FORBIDDEN` 403; `INTERNAL` 503 (worker unconfigured); `DEPENDENCY_ERROR` 503 (Redis) |
| **Redis failure** | Fail closed — never `200 []` |
| **Privacy** | Exact coords + driverId **internal only**; never Redis keys |

---

## Remaining blockers

**Architecture blockers:** **NONE** (implemented per D1–D8).

**Operational / data dependency (not architecture blocker):**

- **D7** — `drivers.homeCity` must be seeded for non-empty GEO in real environments.

**Known limitation (not blocker):**

- Offer-create busy check still only `DRIVER_ASSIGNED` (narrower than N3). Align later if desired; N3 uses the broader set.

**Verdict:**

> **N3 is IMPLEMENTED** — internal nearby candidates via Redis GEORADIUS + Firestore filters. Next frontier: **N4** (dispatch/matching waves) or ops `homeCity` writer.

---

## Explicit non-goals

N2B, N4, FCM, RTDB, Maps/ETA, payments, passenger nearby UI, driver competitor browse, Firestore geo fallback, homeCity writer, N2C TTL change, M0 GEO-ification, pagination.

---

## Related

- [`ORA_CURRENT_STATE.md`](../../ORA_CURRENT_STATE.md)
- [`N_LOCATION_FLOW.md`](../../architecture/N_LOCATION_FLOW.md)
- [`N2C-redis-geo.md`](N2C-redis-geo.md)
- `docs/architecture-final/24-phase-1.6-condition-closure.md` §8, §10
- ADR-004
