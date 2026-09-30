# N3 slice #2 — users + drivers `getAll`

**Revision:** `ora-auth-service-staging-00022-bkc`  
**Prior baseline:** `ora-auth-service-staging-00021-b6m` (busy prefetch)  
**Benchmark artifact:** `N3_STAGING_BENCHMARK_REPORT_GETALL.json`  
**Prefix:** `n3bench_busy_20260930T085443Z` (same seed as busy-prefetch proof)

---

## A. Files changed

| Path | Change |
|------|--------|
| `backend/auth-service/src/drivers/nearby_service.ts` | Prefetch users/drivers via sequential `getAll`; map-backed N3 eligibility; extended diagnostics |
| `backend/auth-service/src/routes/internal.ts` | Log batch RPC + `firestoreRpcTotal` on `N3_NEARBY` |
| `backend/auth-service/src/__tests__/helpers/memory_db.ts` | `getAll()` for tests |
| `backend/auth-service/src/__tests__/n3_users_drivers_getall.test.ts` | **New** focused tests |
| `backend/auth-service/src/__tests__/n3_nearby_diagnostics.test.ts` | Prefetch logical-read semantics |
| `backend/auth-service/src/__tests__/n3_redis_mget_batch.test.ts` | Prefetch logical-read semantics |
| `backend/auth-service/scripts/run_n3_staging_benchmark_vpc.ts` | Report name env; RPC total helper |
| `backend/auth-service/scripts/run_n3_staging_benchmark_vpc_job.sh` | Default report `…_GETALL.json` |
| `backend/auth-service/scripts/run_n3_staging_benchmark_vpc.bundle.cjs` | Rebuilt bundle |

---

## B. Exact implementation

1. After MGET + `prefetchBusyDriverIds`, build `uniqueGeoMemberIdsInOrder(geoHits)`.
2. Sequential `db.getAll(...users refs)` then `db.getAll(...drivers refs)` (chunk size `N3_FIRESTORE_GETALL_MAX = 100`).
3. Maps `userByDriverId` / `driverByDriverId` (`null` = missing doc).
4. N3 loop unchanged (GEO order, marker gates, stop at `limit` eligible); `isAuthoritativelyEligible(..., { busyDriverIds, prefetched })` reads maps only.
5. `isStillEligibleForInvite` → `isAuthoritativelyEligible(driverId)` **without** `prefetched` → per-doc `.get()` + per-driver busy query (unchanged).

---

## C. New revision

`ora-auth-service-staging-00022-bkc`

---

## D. Before/after Firestore RPC counts

| Limit | Before (~RPC) | After `firestoreRpcTotal` |
|-------|---------------|---------------------------|
| 10 | ~24 (10+10+4) | **6** (1+1+4) |
| 30 | ~64 | **6** |
| 100 | ~102 (49+49+4) | **6** |

Batch RPCs (all scenarios): `firestoreUsersBatchRpcs=1`, `firestoreDriversBatchRpcs=1`, `firestoreBusyRideQueries=4`.

---

## E. Before/after logical document reads

| Limit | Before users / drivers | After users / drivers |
|-------|------------------------|------------------------|
| 10 | 10 / 10 | **100 / 100** (all GEO unique IDs prefetched) |
| 30 | 30 / 30 | **100 / 100** |
| 100 | 49 / 49 | **100 / 100** |

Logical reads increase; round-trips decrease. Eligibility **decisions** unchanged (same fields, same loop).

---

## F. Before/after p50 / p95 (staging VPC)

| Limit | p50 before | p50 after | Δ p50 | p95 before | p95 after |
|-------|------------|-----------|-------|------------|-----------|
| 10 | 6438 ms | **4964 ms** | −23% | 18496 ms | **5006 ms** |
| 30 | 16724 ms | **2096 ms** | −87% | 16860 ms | **2155 ms** |
| 100 | 26575 ms | **1816 ms** | −93% | 26897 ms | **1857 ms** |

---

## G. Before/after eligible / rejected (semantic check)

| Limit | eligible before | eligible after | Key buckets |
|-------|-----------------|----------------|-------------|
| 10 | 10 | **10** | `marker_missing` 10 |
| 30 | 30 | **30** | `marker_missing` 30 |
| 100 | 49 | **49** | `marker_missing` 51 |

No change to survivor counts or rejection mix on the bench harness.

---

## H. Semantic equivalence proof

- **Same fields:** `banned`, `isActive`, `role`, `driverStatus`, `availabilityState`, busy `Set`.
- **Same GEO order** and stop-when-`limit`-eligible.
- **Missing docs:** map `null` → same buckets as `!snap.exists`.
- **N4:** `isStillEligibleForInvite` does not pass `prefetched`; tests assert `getAll` not called on invite path.
- **Unit tests:** 391/391 pass including busy prefetch, MGET, diagnostics, new getAll suite.

---

## I. Test results

- **391/391** backend tests pass  
- **Build:** `npm run build` pass  

---

## J. Build result

Pass (tsc).

---

## K. Latency improvement meaningful?

**Yes.** End-to-end p50 dropped materially at all three limits (especially 30 and 100 where sequential per-driver gets dominated). p95 collapsed to near p50 (stable ~2–5 s vs prior 17–27 s tail on large limits). RPC count fixed at **6** for full GEO fan-out.

---

**N3 USERS+DRIVERS GETALL = GREEN**

**NEXT OPTIMIZATION = NONE** (measure before any further slice; remaining cost is mostly 4 busy batch queries + 2 getAll payloads over 100 docs, not O(limit) sequential RTTs)
