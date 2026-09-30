# N3 Redis batch optimization — final report (2026-09-29)

## N3 REDIS BATCH OPTIMIZATION = **FAILED** (latency goal)

**Implementation and behavior:** **GREEN** — one `MGET` per `findNearby`, semantics unchanged, **366/366** tests + build pass.

**Staging latency goal:** **not met** — comparable 10/30 scenarios improved only **~2–3%** median; Firestore remains the bottleneck. Per instruction: **no further optimizations** in this slice.

---

## Files changed

| File | Change |
|------|--------|
| `backend/auth-service/src/redis/types.ts` | `mget(keys)` on `RedisGeoClient` |
| `backend/auth-service/src/redis/client.ts` | ioredis `MGET` wrapper |
| `backend/auth-service/src/redis/memory_redis.ts` | in-memory `mget` |
| `backend/auth-service/src/drivers/nearby_service.ts` | batch marker reads before eligibility loop |
| `backend/auth-service/scripts/run_n3_performance_audit.ts` | count `mget` as one Redis op |
| `backend/auth-service/src/__tests__/n3_nearby_diagnostics.test.ts` | `redisGetCount` = 1 per invocation |
| `backend/auth-service/src/__tests__/n3_redis_mget_batch.test.ts` | **new** — batch keys, no `get` on N3 path, rejections, ordering, failure |

**Unchanged:** N4 `isStillEligibleForInvite` (single `get`), Firestore loop, GEO, limits, API, dispatch.

---

## Implementation

After `GEORADIUS`, build keys `driver:online:{driverId}` in **GEO hit order**, one `redis.mget(markerKeys)`, `redisGetCount += 1`. Eligibility loop reads from a `Map`; validation/rejections/Firestore **unchanged**.

---

## Tests

- `n3_nearby_diagnostics.test.ts` — diagnostics + limit cap
- `n3_redis_mget_batch.test.ts` — keys, no extra `get`, ordering, missing/stale/accuracy, `mget` failure → 503, mixed rejections
- Full suite: **366 passed**

---

## Cloud Run

| Item | Value |
|------|--------|
| **Revision (MGET deploy)** | `ora-auth-service-staging-00019-z2h` |
| **Benchmark job** | `ora-n3-staging-benchmark-z4wbc` (~11m) |
| **Bench prefix** | `n3bench_mget_20260929T112335Z` |
| **Artifact** | `N3_STAGING_BENCHMARK_REPORT_MGET.json` |

Baseline reference: `N3_STAGING_BENCHMARK_REPORT.md` (`n3bench_20260929T102322Z`).

---

## Before vs after (staging, same harness)

### 10 candidates (`limit=10`)

| | Baseline (sequential GET) | After (MGET) |
|--|---------------------------|--------------|
| **p50 durationMs** | **8244** | **8078** (−166 ms, ~2.0%) |
| **p95 durationMs** | **9601** | **21741** (run 1 outlier; runs 2–5: 8032–8150) |
| **redisGetCount** | **10** | **1** |
| **Firestore (U/D/Q)** | 10 / 10 / 10 | 10 / 10 / 10 |
| **eligible / result** | 10 / 10 | 10 / 10 |
| **Rejections** | none | none |

### 30 candidates (`limit=30`)

| | Baseline | After |
|--|----------|--------|
| **p50 durationMs** | **24370** | **23702** (−668 ms, ~2.7%) |
| **p95 durationMs** | **24485** | **23852** |
| **redisGetCount** | **30** | **1** |
| **Firestore (U/D/Q)** | 30 / 30 / 30 | 30 / 30 / 30 |
| **eligible / result** | 30 / 30 | 30 / 30 |
| **Rejections** | none | none |

### 100 candidates (`limit=100`)

| | Baseline | After |
|--|----------|--------|
| **p50 durationMs** | **30036** | **79048** |
| **p95 durationMs** | **30144** | **86386** |
| **redisGetCount** | **100** | **1** |
| **Firestore (U/D/Q)** | **37 / 37 / 37** | **100 / 100 / 100** |
| **eligible** | **37** | **100** |
| **Rejections** | **marker_missing: 63** | none |

**100-scenario latency is not apples-to-apples:** baseline GEO mix had **63** non-bench members without markers (37 eligible). MGET seed run had **100** bench-only eligible drivers → **3×** Firestore work and ~**2.6×** wall time. Redis batching still shows **1** op vs **100**; end-to-end time tracks Firestore depth, not Redis GET count.

---

## Behavior

On comparable 10/30 runs: **identical** eligibility counts, rejection buckets, Firestore op counts, and candidate ordering semantics. **Redis marker read round-trips:** N → **1** per N3 invocation.

---

## Conclusion

Redis GET batching is **correct and deployed** but does **not** materially reduce N3 latency while Firestore eligibility remains sequential. **Stop here** — no Firestore or other changes in this task.
