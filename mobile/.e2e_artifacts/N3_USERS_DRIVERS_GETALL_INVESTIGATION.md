# N3 investigation #2 — users + drivers `getAll` (read-only)

**Baseline:** `ora-auth-service-staging-00021-b6m` (busy prefetch GREEN)  
**Artifact:** `N3_STAGING_BENCHMARK_REPORT_BUSY_PREFETCH.json`  
**Date:** 2026-09-30  
**No production code changes in this investigation.**

---

## A. Current users/drivers read call graph

```
findNearby
├── redis.georadius (1×)
├── redis.mget (1×)
├── prefetchBusyDriverIds(geoMemberIds)     [⌈uniqueIds/30⌉ ride queries]
└── for hit in geoHits (GEO order, stop at limit eligible):
      ├── marker checks (Redis only)
      └── isAuthoritativelyEligible(driverId, { busyDriverIds })
            ├── users/{driverId}.get()      [+1 firestoreUsersReads, 1 RPC each call]
            ├── drivers/{driverId}.get()    [+1 firestoreDriversReads, 1 RPC each call]
            └── busyDriverIds.has(id)       [no RPC]
```

**Sequential RPCs:** Each eligibility attempt performs **two back-to-back** document gets (users, then drivers). Calls happen **only after** marker checks pass. Loop stops when `surviving.length >= limit` (not when geo hits exhausted).

**N4 path (unchanged):** `isStillEligibleForInvite` → `isAuthoritativelyEligible(driverId)` **without** `busyDriverIds` → still uses per-driver busy query + sequential users/drivers `.get()`.

---

## B. Exact required fields

From `nearby_service.ts` → `isAuthoritativelyEligible`:

| Collection | Fields read | Condition |
|------------|-------------|-----------|
| `users/{driverId}` | *(existence)* | reject `user_missing` |
| | `banned` | reject if `=== true` |
| | `isActive` | reject if `=== false` |
| | `role` | must be `'driver'` |
| | `driverStatus` | must be `'approved'` |
| `drivers/{driverId}` | *(existence)* | reject `driver_missing` |
| | `availabilityState` | must be `'online'` |

**Not used in N3:** `profileComplete`, display name, homeCity, or any other user/driver fields. No composite index on users/drivers for eligibility.

---

## C. Logical reads vs RPC / round-trips (current behavior)

| Metric | Meaning today |
|--------|----------------|
| `firestoreUsersReads` / `firestoreDriversReads` | **+1 per eligibility invocation** (one logical document read each), not batch-aware |
| **Firestore RPC round-trips** | **2 × E** sequential, where **E** = number of times `isAuthoritativelyEligible` runs (marker-pass hits until loop exits) |
| **Application-level `.get()` calls** | Same as **2 × E** (users then drivers) |

**E vs limit:** `E ≥ eligibleCount`. Equality holds when every eligibility attempt that starts user read eventually passes (bench path). Failures after `users.get` still increment both counters when driver read runs; user-only failures increment users only.

**Busy prefetch (current):** **4** RPCs when `geoHits = 100` (⌈100/30⌉), independent of limit.

**Redis:** 1 GEORADIUS + 1 MGET per request.

### Staging measured (VPC, busy prefetch baseline)

| Scenario | p50 (ms) | p95 (ms) | users | drivers | busy Q | FS diag total* | redisGet | eligible |
|----------|----------|----------|-------|---------|--------|----------------|----------|----------|
| limit 10 | **6438** | 18496 | 10 | 10 | 4 | **24** | 1 | 10 |
| limit 30 | **16724** | 16860 | 30 | 30 | 4 | **64** | 1 | 30 |
| limit 100 | **26575** | 26897 | 49 | 49 | 4 | **102** | 1 | 49† |

\* `users + drivers + busyRideQueries` from diagnostics (last/summary runs).  
† limit 100: **51** `marker_missing`, **49** eligible — only **49** eligibility attempts; **98** user/driver RPCs + **4** busy RPCs ≈ **102** application Firestore round-trips.

---

## D. Current staging p50 / p95

See table above (source: `N3_STAGING_BENCHMARK_REPORT_BUSY_PREFETCH.json`, prefix `n3bench_busy_20260930T085443Z`).

---

## E. Current Firestore operation counts

Same as section C. **Logical document reads** (diagnostics) match **eligibility attempts** for users/drivers, not “all GEO members.”

---

## F. `getAll` batch-size constraints

| Constraint | Value for Ora N3 |
|------------|------------------|
| Firestore `getAll()` / batch read | **Max 100 document references per call** (Firebase/Firestore standard; no `getAll` usage elsewhere in this repo yet) |
| Max GEO members | **`N3_REDIS_GEO_COUNT = 100`** |
| Unique IDs | `new Set(geoMemberIds)` — duplicates in GEO list collapse to one ref |

**Chunking:** For N3, **one `getAll` per collection** suffices (≤100 refs). Chunk only if future GEO cap &gt; 100.

**Collections:** Users and drivers are **separate** `getAll` calls (different collection paths) → **2 RPCs minimum** per request when prefetching all unique GEO IDs.

---

## G. Safety / semantic analysis

| Requirement | Safe with batched `getAll`? | Notes |
|-------------|----------------------------|-------|
| Same eligibility decisions | **Yes** | Apply **identical** field checks on snapshot/map entries |
| GEO survivor ordering | **Yes** | Loop order unchanged; only replace `.get()` with map lookup |
| Rejection buckets | **Yes** | Same branches / increment rules on missing/banned/inactive/not approved/offline/busy |
| Missing documents | **Yes** | `getAll` returns non-existent refs as missing docs — same as `!snap.exists` |
| Marker / freshness / accuracy | **Yes** | Unchanged; still before eligibility |
| Busy prefetch Set | **Yes** | Unchanged |
| Duplicate GEO IDs | **Yes** | Dedupe refs for `getAll`; map keyed by `driverId` |
| Stop at `limit` eligible | **Yes** | Do not change loop termination |
| `isStillEligibleForInvite` | **Yes** | Keep separate code path with single `.get()` (no batch) |

**Prefetch scope (design choice for implementation):**

- **Recommended (matches busy prefetch):** Prefetch users + drivers for **all unique GEO member IDs** (≤100) **before** the loop, then run marker checks and map lookups in existing order.
- **Logical reads:** May **exceed** current diagnostics (e.g. load 100 user docs while today only **49** eligibility reads at limit 100) — **survivor set unchanged** because marker-failed IDs never consult maps for eligibility.
- **Do not** parallelize users vs drivers `getAll` if avoiding concurrent eligibility I/O is a hard constraint; **2 sequential `getAll` RPCs** still cut round-trips vs **2×E** sequential `.get()`.

**Authorization / approval:** Unchanged — same fields, same strict equality checks.

---

## H. Expected reduction in RPC / round-trips

Let **U** = `|unique(geoMemberIds)|` (≤100), **E** = eligibility invocations (current user/driver diag counts).

| Phase | Current RPC (approx) | After users+drivers `getAll` (prefetch all GEO IDs) |
|-------|----------------------|-----------------------------------------------------|
| Users + drivers | **2 × E** sequential `.get()` | **⌈U/100⌉ + ⌈U/100⌉** = **2** RPCs (sequential) |
| Busy (unchanged) | **4** when geoHits=100 | **4** |
| **Example limit 100 (bench)** | **98 + 4 = 102** | **2 + 4 = 6** Firestore batch/query RPCs |

**Logical document reads (billing-style):** Up to **2×U** documents loaded (users + drivers for all GEO IDs) vs **2×E** today — **may increase** logical reads while **decreasing round-trips**.

---

## I. Expected effect on end-to-end latency

- Busy prefetch removed **~66%** p50 at limit 100 by cutting **O(E)** ride queries to **4** batch queries.
- Remaining cost is dominated by **2×E sequential document RTTs** (investigation #1: ~⅓ users, ~⅓ drivers per eligible attempt).
- Replacing **2×E** sequential gets with **2** `getAll` calls at limit 100 (**E=49**): **~96 fewer sequential RTTs** on the eligibility path — **material improvement likely**, but **must be measured on staging** after implementation (not claimed here).
- Limit 10 (**E=10**): **20 → 2** document RPCs — moderate gain; p50 already **6438 ms**.

---

## J. Firestore index / schema

**None required** for `getAll` by document ID (users/{id}, drivers/{id}). No new composite queries.

---

## K. Recommended implementation approach (if approved later)

1. After MGET + busy prefetch, `uniqueIds = [...new Set(geoMemberIds)]`.
2. `userSnaps = await db.getAll(...uniqueIds.map(id => db.collection('users').doc(id)))` (chunk if &gt;100 ever).
3. Same for `drivers`.
4. Build `Map<string, DocumentSnapshot | null>` (or `{ exists, data }`).
5. Extend `isAuthoritativelyEligible` to accept optional maps; **N3 only** passes maps; **N4** omits maps (current `.get()`).
6. **Diagnostics:** Keep per-invocation user/driver counters **or** add explicit `firestoreUsersBatchGets` / `documentsLoaded` — document in N3_NEARBY log; do not silently count one RPC as zero reads.
7. **Do not** combine with parallel reads, caching, or users+drivers merge into one collection.

---

## L. What must NOT be changed

- API response, query params, limits, radius, GEO key, marker/freshness/accuracy rules  
- GEO ordering and stop-when-`limit`-eligible behavior  
- Busy prefetch semantics and chunk size (30)  
- N4 `isStillEligibleForInvite` behavior  
- D1, dispatch, ride lifecycle, pricing, auth  
- Eligibility field rules and rejection bucket meanings  
- Firestore schema  

---

## Tests (investigation run)

- `npm run build` — pass  
- `npm test` — **376/376** pass (N3 diagnostics, MGET, busy prefetch, nearby, dispatch, D1, open discovery, full suite)  
- **No test or production code modified** for this investigation  

---

## Artifacts

| File | Role |
|------|------|
| `N3_STAGING_BENCHMARK_REPORT_BUSY_PREFETCH.json` | Current staging metrics |
| `N3_BUSY_PREFETCH_OPTIMIZATION_REPORT.md` | Prior slice summary |
| `N3_FIRESTORE_INVESTIGATION.md` | Original Firestore bottleneck analysis |

---

**N3 USERS+DRIVERS INVESTIGATION = GREEN**

**NEXT OPTIMIZATION = Implement batched `getAll` for `users` and `drivers` document refs for unique GEO member IDs (≤100, 2 sequential RPCs per request when U≤100), map-backed eligibility in N3 `findNearby` only; measure staging p50/p95 vs 6438 / 16724 / 26575 ms baseline; extend diagnostics to separate batch RPCs vs logical document reads.**
