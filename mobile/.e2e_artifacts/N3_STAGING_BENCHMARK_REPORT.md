# N3 staging benchmark — final report (2026-09-29)

**Verdict:** **N3 STAGING BENCHMARK = GREEN** (real Memorystore + Firestore; in-VPC runner)

---

## REDIS

| Item | Detail |
|------|--------|
| **Provider** | Google Cloud **Memorystore for Redis** (BASIC, 1 GB) |
| **Instance** | `ora-staging-n3-redis` |
| **Region** | `us-central1` |
| **Network** | **Private** — `default` VPC, authorized network only |
| **Cloud Run connectivity** | Serverless VPC Access connector `ora-staging-vpc` (`10.8.0.0/28`), egress `private-ranges-only` |
| **REDIS_URL** | Secret Manager `ora-staging-redis-url` → Cloud Run env (not in git) |
| **Secrets exposed in reports** | **No** |

**Cloud Run revision (post-wire):** `ora-auth-service-staging-00016-btx`  
**N3 HTTP smoke:** `200` with worker token; `redis_geo_init.configured=true` in logs.

---

## Test setup

- **100** isolated bench drivers (`_n3BenchPrefix`, Firestore `users`/`drivers` + `geo:drivers` + `driver:online:*`).
- **Pickup:** `31.4127578, 74.1725224`, `radiusKm=10`.
- **Runner:** Cloud Run Job `ora-n3-staging-benchmark` — **in-VPC** `NearbyDriversService.findNearby` (same code path as production N3; fresh markers each run to respect **30s** TTL).
- **Runs:** 5 per scenario (limits **10 / 30 / 100**).
- **Artifact:** `mobile/.e2e_artifacts/N3_STAGING_BENCHMARK_REPORT.json`

---

## Results (staging)

### 10 candidates (`limit=10`)

| Metric | Representative (median / p95) |
|--------|-------------------------------|
| **durationMs** | **8244 / 9601** |
| **geoHits** | 100 (fixed GEORADIUS cap) |
| **redisGetCount** | **10** |
| **firestoreUsersReads** | **10** |
| **firestoreDriversReads** | **10** |
| **firestoreBusyRideQueries** | **10** |
| **eligibleCount / resultCount** | **10 / 10** |
| **Rejections** | none |

Matches local audit shape: **1 GEORADIUS + 10 GETs + 30 Firestore ops** on eligible path.

### 30 candidates (`limit=30`)

| Metric | Representative (median / p95) |
|--------|-------------------------------|
| **durationMs** | **24370 / 24485** |
| **redisGetCount** | **30** |
| **Firestore reads (U/D/Q each)** | **30 / 30 / 30** |
| **eligibleCount** | **30** |
| **Rejections** | none |

Matches audit: **30 GETs + 90 Firestore ops**.

### 100 candidates (`limit=100`)

| Metric | Representative (median / p95) |
|--------|-------------------------------|
| **durationMs** | **30036 / 30144** |
| **redisGetCount** | **100** |
| **Firestore reads (U/D/Q each)** | **37 / 37 / 37** |
| **eligibleCount** | **37** (not 100) |
| **Rejections** | **marker_missing: 63** |

**Note:** `geo:drivers` returns up to **100** members near pickup; **63** were non-bench GEO entries without `driver:online:*` markers (mixed index). Bench drivers are present; limit-100 run still exercised **100 Redis GETs** and full loop depth. For a pure 100-eligible slice, GEO would need fewer non-bench members in radius (ops hygiene), not an N3 code change.

---

## Repeated runs

- **10 / 30:** Stable op counts; duration **~8.2–9.6s** (10) and **~24.4s** (30) across 5 runs.
- **100:** Stable **~30s** wall time; eligible count **37** on all runs (GEO mix).

---

## vs baseline

| Path | Audit expectation | Staging observed |
|------|-------------------|------------------|
| 10 eligible | ≤10 GET, ≤30 FS ops | **10 / 30** ✓ |
| 30 eligible | ≤30 GET, ≤90 FS ops | **30 / 90** ✓ |
| 100 eligible | ≤100 GET, ≤300 FS ops | **100 GET, 111 FS ops**, **37 eligible** (GEO mix) |

**Latency:** Staging RTT dominates (seconds vs local sub-ms). **N+1 sequential pattern confirmed** at production scale.

---

## Optimization justified?

**Yes — investigation warranted, but do not implement in this slice.**

- **~8s** for 10 eligible and **~24–30s** for 30–100 depth is high for dispatch-adjacent paths.
- Op counts match design (**no batching**); slowness is **RTT × sequential awaits**, not wrong Redis/Firestore counts.
- **Smallest next step (future):** measure one bounded change (e.g. pipelined Redis GETs only) with the same staging harness before/after.

---

## TESTS

- **Build:** PASS  
- **Tests:** **359 / 359** PASS (includes `n3_nearby_diagnostics.test.ts`)

---

## Infrastructure / ops changes (no N3 product logic changes)

- Enabled APIs: Compute, Redis, Service Networking, VPC Access, Secret Manager  
- Memorystore + VPC connector + Secret `ora-staging-redis-url`  
- Scripts: `wire_staging_redis.sh`, `run_n3_staging_seed_job.sh`, `run_n3_staging_benchmark_vpc_job.sh`, `run_n3_staging_benchmark_vpc.ts`, seed bundle in image  
- `deploy_staging_cloud_run.sh` preserves Redis secret + VPC when secret exists  
- `Dockerfile` copies benchmark bundles (ops-only image additions)
