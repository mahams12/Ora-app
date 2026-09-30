# N3 Firestore performance — investigation (read-only)

**Scope:** `GET /v1/internal/drivers/nearby` → `NearbyDriversService.findNearby`  
**D1:** closed — no changes. **Production code:** unchanged (investigation scripts only).  
**Date:** 2026-09-30

---

## A. Current N3 Firestore call graph

```
findNearby
├── redis.georadius(geo:drivers)                    [1×, ≤100 members]
├── redis.mget(driver:online:{id}…)                 [1×, batched — MGET slice]
└── for hit in geoHits (GEO order, stop at limit):
      └── isAuthoritativelyEligible(driverId)       [SEQUENTIAL await per hit]
            ├── firestore users/{driverId}.get()    [+1 read count]
            ├── firestore drivers/{driverId}.get()  [+1 read count]
            └── firestore rides query               [+1 query count]
                  .where(assignedDriverId == driverId)
                  .where(state in N3_BUSY_RIDE_STATES)
                  .limit(1).get()
```

**Sequential Firestore:** Yes. Each geo hit awaits a full eligibility chain before the next hit (`nearby_service.ts` loop + `await this.isAuthoritativelyEligible`).

**Early exit:** Loop stops adding candidates when `surviving.length >= limit`, but eligibility runs on hits in order until then (up to `limit` successful eligibles; fewer Firestore calls if markers reject first).

---

## B. Exact operation counts (eligible bench path, geoHits=100)

From staging VPC benchmark (`N3_STAGING_BENCHMARK_REPORT_MGET.json`, prefix `n3bench_mget_20260929T112335Z`, revision `00019-z2h`, all markers valid):

| Scenario (limit) | redis georadius | redis mget | users `.get` | drivers `.get` | busy ride queries | Total Firestore ops* |
|----------------|-----------------|------------|--------------|------------------|-------------------|----------------------|
| **10** | 1 | 1 | **10** | **10** | **10** | **30** |
| **30** | 1 | 1 | **30** | **30** | **30** | **90** |
| **100** | 1 | 1 | **100** | **100** | **100** | **300** |

\*One users read + one drivers read + one rides query per eligibility invocation (diagnostics counters match).

Instrumented re-run (`N3_FIRESTORE_INVESTIGATION_REPORT.json`, real **staging Firestore**, bench prefix `n3bench_fs_invest_20260930T070256Z`, local Redis markers refreshed each run — Redis ≪1 ms; **not** used for end-to-end totals):

| Scenario | users reads (run 1) | drivers reads | busy queries |
|----------|---------------------|---------------|--------------|
| 10 | 10 | 10 | 10 |
| 30 | 30 | 30 | 30 |
| 100 | 100 | 100 | 100 |

---

## C. Measured latency breakdown

### C1. End-to-end — **real staging VPC** (Memorystore + Firestore, in-process `NearbyDriversService`)

Source: `N3_STAGING_BENCHMARK_REPORT_MGET.json` (post–Redis MGET deploy).

| Scenario | p50 total (ms) | p95 total (ms) | Redis ops (p50 path) |
|----------|----------------|----------------|----------------------|
| **10** | **8078** | **21741** | 1× GEORADIUS + 1× MGET |
| **30** | **23702** | **23852** | same |
| **100** | **79048** | **86386** | same |

MGET vs pre-MGET baseline: ~**2–3%** p50 improvement at limits 10/30 (see `N3_REDIS_MGET_OPTIMIZATION_REPORT.md`). **Total latency still dominated by non-Redis work** (~98%+ implied).

### C2. Firestore component timings — **instrumented, real staging Firestore**

Source: `N3_FIRESTORE_INVESTIGATION_REPORT.json` (`run_n3_firestore_investigation_local.ts`).  
**Note:** Laptop → Firestore RTT; absolute ms **higher** than VPC, but **op counts and ~equal split across the three Firestore steps** match production diagnostics.

| Scenario | p50 total (ms) | p50 Firestore total (ms) | p50 busy queries (ms) | p50 Redis (ms) | p50 app processing (ms) | Firestore share (p50) |
|----------|----------------|--------------------------|------------------------|----------------|-------------------------|------------------------|
| **10** | 16516 | 16512 | 5513 | ~1 | ~8 | **~100%** |
| **30** | 48364 | 48352 | 15961 | ~0 | ~13 | **~100%** |
| **100** | 161943 | 161901 | 54002 | ~0 | ~42 | **~100%** |

Representative **run 1** breakdown (ms), limit **100**:

| Redis | Firestore users | Firestore drivers | Firestore busy | App | Total |
|-------|-----------------|-------------------|----------------|-----|-------|
| ~0 | 53731 | 53645 | 54525 | 42 | 161901 |

Per eligible candidate (100 case): **~537 ms** users + **~536 ms** drivers + **~545 ms** busy query ≈ **~1.62 s** sequential Firestore per driver (three round-trips).

Scaling: limit **100** → ~**79048 ms** staging p50 vs **~300** sequential Firestore ops — ~**260 ms** average effective cost per op end-to-end in VPC (RTT + query execution + sequential stacking).

---

## D. Single largest measured bottleneck

**Sequential per-candidate Firestore eligibility** (users get → drivers get → busy ride query), scaling **3 × limit** round-trips in the common bench case (first `limit` geo hits pass markers).

Redis (GEORADIUS + MGET) is **not** the bottleneck after MGET (~2–3% end-to-end gain). **Busy-ride queries are not individually the largest sub-step** in the instrumented split (~⅓ of Firestore ms each); the **aggregate cost is the sequential sum of all three**, scaling linearly with `limit`.

---

## E. Safe optimization candidates (semantics-preserving only)

| Candidate | Addresses | Safe if |
|-----------|-----------|---------|
| **1. Prefetch busy drivers** — one (or chunked) `rides` query: `assignedDriverId in candidateIds` + `state in busy`, build `Set<driverId>`, O(1) check in loop | Removes **O(limit)** busy queries → **O(1–4)** queries (chunk `in` ≤ 30) | Same per-driver busy rule; candidate set = driver IDs from geo hits **before** eligibility loop (max 100); ordering of **survivors** unchanged if loop order unchanged |
| **2. `getAll` batch for `users` and `drivers`** — batch doc refs for IDs entering eligibility | Cuts round-trips for point reads | Same docs/fields; approval/banned/offline checks unchanged; still apply checks in GEO order |
| **3. Parallelize the three reads inside one eligibility** (`Promise.all` user + driver + busy) | Lowers per-candidate latency from sum → max | **Risk:** concurrency / ordering under load — needs explicit proof; not “batching” |
| **4. Cache user/driver snapshots** | Repeated N3/N4 reads | **Out of scope** — freshness & invalidation change operational semantics unless very tight TTL + invalidation (not recommended without design) |

**Not safe without contract/schema changes:** dropping busy check, merging eligibility order, changing GEO order, changing response shape, weakening freshness/marker rules.

---

## F. Recommended ONE next implementation slice

**Prefetch busy-ride eligibility for the current geo-hit member list (≤100 IDs), then replace per-driver busy queries with in-memory set lookup.**

**Evidence:** Staging shows **limit × 1** busy queries (10/30/100); instrumented timing shows busy checks ≈ **⅓ of Firestore ms** but **~100 sequential queries** at limit 100; MGET already proved micro-optimizations on Redis don’t move p50. One batched busy query (plus ≤4 chunks for `in` size 30) preserves eligibility while removing the largest **count** of round-trips.

**Follow-on slice (not simultaneous):** batched `getAll` for users + drivers for the same ID set.

---

## G. What must NOT be changed

- API response / query params / limits / radius / GEO key / freshness / accuracy rules  
- N4 dispatch, D1 FCM, ride lifecycle, pricing, auth  
- Firestore schema, indexes (unless a new batch query requires an index — evaluate before implement)  
- Eligibility semantics (approved driver, online, not busy, marker rules)  
- Candidate ordering (GEO distance order, stop at `limit`)  
- `isStillEligibleForInvite` single-driver path (separate from N3 batch investigation)  
- Using memory-only benchmarks as production proof  

---

## Tests / build (investigation run)

- `npm run build` — pass  
- `npm test` — **366/366** pass (includes `n3_nearby_diagnostics.test.ts`, `n3_redis_mget_batch.test.ts`)  
- No test changes for this investigation  

---

## Artifacts

| File | Purpose |
|------|---------|
| `N3_FIRESTORE_INVESTIGATION_REPORT.json` | Instrumented latency breakdown (real Firestore) |
| `N3_STAGING_BENCHMARK_REPORT_MGET.json` | Staging VPC end-to-end + op counts (MGET) |
| `scripts/run_n3_firestore_investigation_local.ts` | Read-only instrumentation harness |
| `scripts/run_n3_firestore_investigation.ts` | VPC bundle (optional; not deployed this run) |

---

**N3 FIRESTORE INVESTIGATION = GREEN**

**NEXT OPTIMIZATION = Batch busy-ride eligibility: prefetch `assignedDriverId in (geo hit IDs)` + busy states, replace per-candidate `limit(1)` ride queries with set membership (chunked `in` queries, semantics unchanged).**
