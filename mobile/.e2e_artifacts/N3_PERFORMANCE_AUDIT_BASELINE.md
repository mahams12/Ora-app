# N3 Nearby Driver — Performance Audit Baseline

**Date:** 2026-09-29  
**Scope:** Read-only audit of current `NearbyDriversService` (no batching, no rule/limit/architecture changes).  
**Authority:** ADR-004 (Redis GEO non-authoritative), coordinate-primary `geo:drivers`, Firestore eligibility SoT.

---

## A. Current N3 flow

**Entry:** `GET /v1/internal/drivers/nearby` (worker token only) → `NearbyDriversService.findNearby` (`nearby_service.ts`).

1. **Parse query** — `lat`/`lng` required; `city` optional echo; `radiusKm` (1–25, default 10); `limit` (1–100, default 30).
2. **Redis dependency gate** — `redis == null` → **503** `DEPENDENCY_ERROR` (no Firestore geo fallback).
3. **Candidate generation (Redis only)** — one `GEORADIUS` on `geo:drivers` with fixed **`COUNT = N3_REDIS_GEO_COUNT (100)`**, ASC + distance/coords. City does **not** gate matching.
4. **Per GEO hit (sequential loop)** — stop when `surviving.length >= limit`:
   - `GET driver:online:{driverId}` — drop if missing / bad JSON.
   - Marker filters — freshness (`≤ 15s`), accuracy (`≤ 50m`). No city/homeCity gate.
   - **Firestore authoritative eligibility** (`isAuthoritativelyEligible`) — see rejections below.
   - Append to response list (distance order preserved from Redis).
5. **Response** — `{ pickup, radiusKm, candidates[], city? }`.

**Downstream (N4):** `DispatchWaveService` calls `findNearby` with `limit: N3_MAX_LIMIT (100)`, `radiusKm: N4_RADIUS_KM (10)`, then **re-validates each selected candidate** via `isStillEligibleForInvite` (+1 Redis GET + up to 3 Firestore ops per invite). This audit focuses on **N3 `findNearby` only**; N4 multiplies cost on the invite subset.

**Existing production instrumentation:** `logSafe('N3_NEARBY', { resultCount, durationMs, radiusKm, city })` on the HTTP handler only — **no per-stage or Redis/Firestore counters**.

---

## B. Actual Firestore reads / operations per call

Per candidate that reaches `isAuthoritativelyEligible`:

| Step | Operation | Short-circuit |
|------|-----------|---------------|
| 1 | `users/{driverId}` `.get()` | Always |
| 2 | `drivers/{driverId}` `.get()` | After user checks pass |
| 3 | `rides` query `assignedDriverId == id` + `state in busy` + `limit(1)` | After driver `online` |

**Rejection reasons (Firestore path):** `user_missing`, `banned`, `inactive`, `not_driver_or_not_approved`, `driver_missing`, `driver_not_online`, `busy_ride` (any of `N3_BUSY_RIDE_STATES`).

**Pre-Firestore drops (no Firestore):** missing marker, malformed marker, stale/future timestamp, accuracy &gt; 50m.

**Counting model:**

- **Round-trips / logical ops:** `users_get + drivers_get + rides_queries` (each `.get()` / query `.get()` is one client operation).
- **Firestore billing (typical):** one read per document read; empty `limit(1)` query still bills **1 read** per query executed.

**Measured (instrumented local run — see § I):**

| Scenario | GEO hits | Users `.get` | Drivers `.get` | Rides queries | Eligible | FS ops (U+D+Q) |
|----------|----------|--------------|----------------|---------------|----------|----------------|
| 0 drivers in GEO | 0 | 0 | 0 | 0 | 0 | **0** |
| 1 eligible | 1 | 1 | 1 | 1 | 1 | **3** |
| 10 eligible | 10 | 10 | 10 | 10 | 10 | **30** |
| 50 eligible | 50 | 50 | 50 | 50 | 50 | **150** |
| 100 eligible, limit 100 | 100 | 100 | 100 | 100 | 100 | **300** |
| 100 GEO, limit 30, all eligible | 100 | 30 | 30 | 30 | 30 | **90** (early break) |
| 100 GEO, all FS-offline after Redis pass | 100 | 100 | 100 | **0** | 0 | **200** (short-circuit before rides) |
| 100 GEO, no Redis markers | 100 | 0 | 0 | 0 | 0 | **0** |

Linear scaling: **~3 × (number of GEO hits processed that pass Redis filters and reach eligibility)**; **~2 × hits** if every driver fails at `availabilityState !== 'online'` before busy query.

---

## C. Actual Redis operations per call

| Operation | Count |
|-----------|--------|
| `GEORADIUS` | **Always 1** per `findNearby` |
| `GET driver:online:*` | **0 … min(geoHits, processing depth)** |

Processing depth = GEO hits examined until loop breaks (`limit` satisfied or hits exhausted).

**Measured:**

| Scenario | GEORADIUS | GET |
|----------|-----------|-----|
| 0 GEO hits | 1 | 0 |
| N eligible (N≤100, limit≥N) | 1 | N |
| 100 GEO, limit 30, all eligible near front | 1 | **30** |
| 100 GEO, limit 100, all pass Redis | 1 | **100** |
| 100 GEO, no markers | 1 | **100** (GET then continue) |

---

## D. Latency

| Source | What is measured |
|--------|------------------|
| **HTTP** | `N3_NEARBY.durationMs` — end-to-end handler only |
| **Per-stage** | **Not implemented** (no timers around GEORADIUS, GET loop, or Firestore) |

**Local instrumented runs (MemoryDb + MemoryRedis, single-threaded Node):** sub-5 ms for up to 100 candidates (not representative of Cloud Run + real Firestore/Redis RTT).

**Staging (2026-09-29):** `GET /healthz/` → **200**. `GET /v1/internal/drivers/nearby` without worker token → **403** (expected). **No worker token in repo `.env`** — full staging N3 latency/op-count proof not run here; Cloud Logging would only show aggregate `durationMs` / `resultCount` if called with valid token + Redis configured on the service.

---

## E. Candidate / eligible counts

- **Redis GEO cap:** 100 members returned per call (`N3_REDIS_GEO_COUNT`), independent of API `limit`.
- **API default limit:** 30; **N4 uses 100**.
- **Ordering:** Redis ASC distance; response truncated at `limit` eligible survivors.
- **Eligibility unchanged:** Unit tests confirm coordinate-primary behavior, busy-state exclusion, stale/accuracy drops, no legacy city GEO key, worker auth.

---

## F. N+1 behavior — confirmed

**Yes.** Implementation is a **sequential `for (const hit of geoHits)`** with **await per iteration**:

- 1× Redis `GET` per examined hit.
- Up to 3× sequential Firestore operations per hit that passes Redis/marker gates.

No batching, no `Promise.all`, no pipelined Redis. Worst-case **100 iterations** when `limit === 100` and all hits pass Redis filters but fail or pass Firestore slowly.

**Partial mitigation already in code:** eligibility short-circuits after `drivers` doc (offline) **skips rides query** — reduces FS ops but not loop count or Redis GETs.

---

## G. Exact safe batching opportunity (audit only — not implemented)

Smallest **correctness-preserving** wins (Firestore remains SoT; Redis unchanged):

1. **Phase A — Redis marker pass:** Collect driver IDs that pass `GET` + parse + freshness + accuracy (still sequential GET unless Redis `MGET` for `driver:online:{id}` batch of current slice — **does not change authority**).
2. **Phase B — Firestore batch reads:** For IDs in slice, `getAll` / batched reads:
   - `users/{id}` for all IDs in batch (≤10/30 per Firestore `in` limit if using queries; `getAll` up to 500 refs per call).
   - `drivers/{id}` same batch.
3. **Phase C — Busy checks:** Hardest part — one query per driver today. Safer batch: chunked `assignedDriverId in [...]` (max 30) + `state in busy` + client-side map; **must not change** busy state set or semantics.

**Do not:** batch across eligibility rule changes, add Firestore geo, or make Redis authoritative.

---

## H. Risks

| Risk | Notes |
|------|--------|
| **Latency at 100× sequential FS RTT** | Dispatch wave uses `limit: 100`; p95 N3 could dominate tick latency on real Firestore. |
| **Staging without `REDIS_URL`** | N3 returns 503 — dispatch/nearby disabled (ADR-004 degradation). |
| **False sense from local ms timings** | Need Cloud Run + Redis + Firestore proof for production-like latency. |
| **N4 double-touch** | Each invited driver re-runs Redis GET + FS eligibility after N3. |
| **Busy-query index** | Per-driver query assumes composite index exists; missing index → 500 (ops audit separate). |
| **Instrumentation gap** | Cannot validate worst-case in prod without temporary counters or log sampling. |

---

## I. Tests / proof

| Proof | Result |
|-------|--------|
| `src/__tests__/nearby.test.ts` | **29/29 pass** — eligibility contract frozen |
| `npm run test:phase-n3-unit-proof` | **8/8 pass** |
| `scripts/run_n3_performance_audit.ts` (local counters, **not deployed**) | JSON baseline — see repo run output 2026-09-29 |

**Reproduce local baseline:**

```bash
cd backend/auth-service
./node_modules/.bin/esbuild scripts/run_n3_performance_audit.ts --bundle --platform=node --format=cjs --outfile=.tmp/n3_performance_audit.cjs && node .tmp/n3_performance_audit.cjs
```

**Staging:** HTTPS reachable; N3 blocked without worker token. For controlled staging proof: call with `X-Ora-Worker-Token` (Cloud Run secret) + ensure `REDIS_URL` on revision; compare `N3_NEARBY` logs for `durationMs` / `resultCount` only.

---

## J. Recommendation — smallest next implementation

1. **Add read-only observability first (minimal diff):** extend `N3_NEARBY` log (or temporary feature-flagged debug) with **`geoHits`, `redisGetCount`, `fsUsersGets`, `fsDriversGets`, `fsRidesQueries`, `rejectedByReason` counts** on staging — no behavior change.
2. **Run one staged load test** with known seeded drivers (0 / 30 / 100 in GEO) to capture **real** p50/p95 `durationMs`.
3. **Then** implement **Firestore `getAll` batching for users+drivers** for the current slice of IDs that passed Redis/marker checks (keep per-driver busy query initially) — smallest batch win with unchanged rules and no Redis authority shift.

**Stop line:** No batching, schema, limit, or eligibility changes in this audit pass.

---

## Answer to audit questions 8–10

| # | Answer |
|---|--------|
| **8** | Behaviors at 0 / 1 / 10 / 50 / 100 reproduced locally (table §B/C). |
| **9** | **~100 Redis GETs:** **confirmed** when 100 GEO hits are processed and each has a marker attempt. **~300 Firestore ops:** **confirmed** when all 100 pass Redis **and** reach busy check (100+100+100). **Not** 300 if all fail at offline driver doc (**200**). Prior “~300 reads” is the **full eligibility path**, not the offline short-circuit path. |
| **10** | Eligibility results match existing tests (approved online, not busy, fresh marker, etc.) — **unchanged**. |
