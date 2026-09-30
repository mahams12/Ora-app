# N3 busy-ride batch prefetch — report (2026-09-30)

## A. Files changed

| File | Change |
|------|--------|
| `backend/auth-service/src/drivers/nearby_service.ts` | `prefetchBusyDriverIds`, `N3_BUSY_PREFETCH_IN_CHUNK_SIZE=30`, N3 loop uses `Set` lookup; N4 `isStillEligibleForInvite` unchanged (single-driver busy query) |
| `backend/auth-service/src/__tests__/n3_busy_prefetch.test.ts` | **new** — batch/chunk/semantics tests |
| `backend/auth-service/src/__tests__/n3_nearby_diagnostics.test.ts` | Updated busy-query expectations (batch prefetch before loop) |

## B. Implementation (minimal)

1. After MGET, collect all GEO `member` IDs (≤100).
2. For each chunk of 30 unique IDs: one `rides` query `assignedDriverId in chunk`, filter `state ∈ N3_BUSY_RIDE_STATES` in memory (avoids Firestore “too many disjunctions” from dual `in` filters).
3. Build `Set<string> busyDriverIds`.
4. Eligibility loop unchanged in order; `isAuthoritativelyEligible(..., { busyDriverIds })` uses set membership instead of per-driver busy query.
5. `isStillEligibleForInvite` calls eligibility **without** set → legacy single-driver busy query.

## C. Firestore operation counts (staging VPC, geoHits=100)

| Limit | Baseline busy Q | After busy Q | Baseline total FS ops* | After total FS ops* |
|-------|-----------------|--------------|------------------------|---------------------|
| 10 | 10 | **4** | 30 | **24** |
| 30 | 30 | **4** | 90 | **64** |
| 100 | 100 | **4** | 300 | **102** |

\*users + drivers + busy query counters from `N3_NEARBY` diagnostics (last run). Users/drivers unchanged per eligible driver; busy count is **batch queries** (4 = ⌈100/30⌉) whenever GEO returns 100 hits.

## D. p50 / p95 end-to-end (staging VPC, real Memorystore + Firestore)

| Limit | Baseline p50 | After p50 | Δ p50 | Baseline p95 | After p95 |
|-------|--------------|-----------|-------|--------------|-----------|
| 10 | 8078 ms | **6438 ms** | **−20%** | 21741 ms | 18496 ms |
| 30 | 23702 ms | **16724 ms** | **−29%** | 23852 ms | 16860 ms |
| 100 | 79048 ms | **26575 ms** | **−66%** | 86386 ms | 26897 ms |

Baseline: `N3_STAGING_BENCHMARK_REPORT_MGET.json` (`n3bench_mget_20260929T112335Z`, rev `00019-z2h`).  
After: `N3_STAGING_BENCHMARK_REPORT_BUSY_PREFETCH.json` (`n3bench_busy_20260930T085443Z`).

## E. Eligible / rejected

Last run limit 100: **eligibleCount=49** (bench/geo mix; same harness as baseline). Rejection buckets empty on successful eligible runs for 10/30. Busy prefetch does not alter rejection semantics (unit tests + nearby tests pass).

## F. Tests

- **376** backend tests pass (includes 10 new/updated N3 busy prefetch + diagnostics).
- Focused: `n3_busy_prefetch.test.ts`, `n3_nearby_diagnostics.test.ts`, `n3_redis_mget_batch.test.ts`, `nearby.test.ts`, `dispatch.test.ts`, `delivery_d1.test.ts`, `open_discovery.test.ts`.

## G. Build

`npm run build` — pass.

## H. Staging deployment

| Revision | Notes |
|----------|--------|
| `ora-auth-service-staging-00021-b6m` | Busy prefetch + in-memory busy state filter (production path) |
| `ora-auth-service-staging-00020-9xp` | **Failed** job — dual `in` query disjunction limit (not deployed behavior) |

## I. Meaningful end-to-end improvement?

**Yes.** Measured staging p50 dropped **20–66%** across 10/30/100 limits while busy Firestore **query count** dropped from O(limit) to O(⌈geoHits/30⌉) (4 for full GEO page). Redis remains 1× MGET.

---

**N3 BUSY PREFETCH = GREEN**

**NEXT OPTIMIZATION = Batch `users` + `drivers` document reads via `getAll` for eligibility candidates (investigation slice #2; do not combine with parallel reads).**
