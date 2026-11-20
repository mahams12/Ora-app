# ORA Architecture Optimization & Firebase Readiness Audit

**Date:** 2026-11-18 (final stabilization pass — includes live GCP inventory + executed local fixes) · **Scope:** read-only audit + local benchmarks + read-only gcloud inspection + local code fixes · **No production changes made**

## Redis/legacy-infrastructure status (four distinct states — do not conflate)

| State | Where | Evidence |
|---|---|---|
| **Redis removed from active codebase** | `src/geo/` replaces `src/redis/`; zero redis/ioredis packages, connections, or `REDIS_URL` | tsc clean, 93/93 geo tests, 784/784 suite |
| **Redis absent from new project** `oraapp-a9be5` | Cloud Asset Inventory: 0 redis/vpcaccess/compute assets; APIs not even enabled | live CAI, 74 assets, 2026-11-18 |
| **Redis present but suspended in old project** `ora-app-d8112` | `ora-production-n3-redis` (SUSPENDED), `ora-staging-vpc` (ERROR after failed delete op), `ora-{production,staging}-redis-url` secrets, PSA peering chain | live CAI + `redis.instances.describe` blocked |
| **Permanent old-project deletion BLOCKED** | GCP rejects all mutations on billing-closed projects (`BILLING_DISABLED`, op `aba4178b-…` failed code 7). No official no-billing deletion path exists; only project shutdown (would destroy Firebase data — out of scope) | `ORA_GCP_RESOURCE_DELETION_PROOF.md` §5 |

**$0 accruing while billing stays closed.** Latent risk only if billing is re-enabled (est. ~$35–50/mo Redis + ~$15/mo connector). Full evidence: `docs/audits/ORA_GCP_RESOURCE_DELETION_PROOF.md`.

## 2026-11-18 stabilization pass — fixes EXECUTED locally (verified)

| Fix | Evidence |
|---|---|
| **Wallet/fee-policy mutual exclusion** — `derivePayoutSnapshot` accepts `walletCommissionBps`; when commission active AND a non-zero fee policy resolves, payout snapshot records `SUPERSEDED_BY_COMMISSION` (fee forced 0, driver keeps full fare). Double-charge is now structurally impossible. | `fee_policy.ts`, `ride_service.ts:2572`; new `walletCommissionBpsInsideTx` export; tsc clean |
| **DRIVER_AUTO_APPROVE default OFF** — env must explicitly be `true`/`1`; `app.ts` + service default flipped; local dev scripts set it explicitly (approved exception); prod/staging deploys set `false` | `driver_auto_approve.ts`, `app.ts`, `dev_*`/`deploy_*` scripts |
| **NEW `POST /v1/internal/drivers/:uid/status`** — worker-auth admin approval path (approved/rejected/suspended/pending); suspend forces driver offline; verified live 8/8 | `routes/internal.ts`; `scripts/test_driver_admin.ts` ALL PASS |
| **`src/redis/` → `src/geo/` full rename** — directory, `GeoStoreClient`, `GeoProjectionService`, `createMemoryGeoStore`, all identifiers/comments/log-codes. **Zero Redis packages, connections, or REDIS_URL anywhere** | tsc clean; 93/93 geo tests pass |
| **Stale old-project defaults fixed** — `deploy_production_cloud_run.sh` defaulted to `ora-app-d8112` (!) + staging deploy, wire-*, launchd, run-local, device backend, 3 local e2e scripts, mobile build scripts → all now `oraapp-a9be5` | grep-verified |
| **`firestore.indexes.json` deduplicated** — duplicate `rides(assignedDriverId,state,createdAt,rideId)` removed (30→29) | JSON-validated |
| **Test-suite flake root-caused & mitigated** — failures were transport-level supertest/socket issues under unbounded fork CPU saturation (each file passes 3× isolated; no shared state possible across forks). `maxForks:4` bound → stable | 784/784 two consecutive runs |
| **E2E script fixes** — `run_local_emulator_e2e.ts` pointed admin seeds at OLD project namespace (driver docs invisible to backend); stale onboarding payload updated to current contract; wallet top-ups seeded (fixed-email UIDs accumulate commission across runs); adaptive-presence script now self-seeds pricing rules | 52/52 + 18/18 |

### Live-verified this pass (emulator stack, `GEO_BACKEND=firestore` = production path)
- `test_adaptive_presence.ts`: **18/18** — merged cursor zero extra writes, adaptive freshness invite at t+18s, keepalive, trip geo throttle (3 pkts→1 write) while RTDB gets every packet, seq 422, no phantom presence, full ride flow
- `run_local_emulator_e2e.ts`: **52/52** — go-online, geo doc, estimate, invite/decline/idempotent, accept→offer→select→assign, RTDB trip tracking, en-route/arrive/start/complete, ratings, INVITE_EXPIRED at 20s, courier OTP full lifecycle, mode-switch + approval gate + ghost presence
- `test_driver_admin.ts`: **8/8**; `test_marketplace_e2e.ts`: **45/45**; `test_marketplace_fidelity.ts`: **42/42**; `verify_vendor_gate.ts`: **10/10**
- Backend suite: **784/784** stable at bounded forks
**Evidence basis:** source inspection of `backend/auth-service/src`, `mobile/lib`, deploy scripts; `scripts/bench_geo.ts` extended and executed (fleet 100–10,000, dense-city + sparse-area); live emulator E2E evidence from marketplace/vendor-gate runs.
**Pricing basis:** Google list prices for `asia-south1`/`us-central1` (Nov 2026 approx): Firestore $0.036/100k reads, $0.108/100k writes, $0.018/100k deletes; free tier 50k reads + 20k writes + 20k deletes **per day**. Cloud Run free tier 2M req + 360k GB-s + 180k vCPU-s/month. RTDB $1/GB stored, $5/GB egress; free 1GB + 10GB/mo. FCM $0. Places Autocomplete ≈$2.83/1k session-SKU, Nearby Search ≈$32/1k. Phone-auth free allotment 10k/mo (Blaze). Figures are estimates — verify against current price card before budgeting.

---

## PHASE 1 — Cost optimization audit

### Where the money actually goes (ranked)

| # | Cost driver | Ops per unit | Evidence | Verdict |
|---|---|---|---|---|
| 1 | **Idle driver presence heartbeat** | default path: ~2.1 R + 2 W (2 txs) per packet at 10 s cadence | `location_update_service.ts:148`, `stream_store.ts:120-200`, `geo_projection.ts:120` | **Dominant cost. Optimization exists but is OFF by default in local/dev builds** |
| 2 | Trip-mode location packets | idle cost + **1 uncached `rides/{id}` read per packet** (≈15/min) + 1 RTDB write | `location_update_service.ts:330-355` | Small fix available: cache ride auth on the stream/session |
| 3 | Dispatch geo candidate scan | progressive rings — p50 ~250–400 doc reads at 5k–10k fleets (benchmark §2) | `firestore_geo_client.ts`, `bench_geo.ts` | Already optimized; keep |
| 4 | Per-wave dispatch work | ~8–10 R + 3 W per wave tick; ≤3 waves/ride + revalidation `mget`/`getAll` (≤100 R worst) | `dispatch_wave_service.ts` | Bounded; acceptable |
| 5 | Offer supersede fan-out | worst ~55 R + ~54 W per `selectOffer` (≤50 pending offers × update+outbox) | `ride_service.ts` selectOffer; `rides/types.ts:212` | Rare worst-case; acceptable |
| 6 | Outbox/FCM projector | 2 bounded scans per sweep tick; ~6 R + 4 W per event + **unbounded token queries per recipient** | `dispatch_fcm_projector.ts:~327`, `device_token_service.ts` | Add `.limit()` to token queries (tiny fix) |
| 7 | Scheduler sweeps | 4×/min + 1×/5min + 1×/15min Cloud Run Jobs; each ~1–N reads + cold-start CPU | `wire_production_cloud_scheduler.sh` | ~5.8k empty-query reads/day + job CPU — small but real |
| 8 | `listOpenRides` driver discovery | up to `OPEN_DISCOVERY_SCAN_CAP=200` reads to return ≤50, filtered in memory | `open_discovery_query.ts` | ~4× read amplification; bounded, low traffic today |
| 9 | Places autocomplete/Nearby | debounced 350 ms + session tokens (good); **reverse geocode fires up to 2 paid calls**; 3-chain fallback can multiply | `google_places_http_search.dart:145-149` | Drop the 2 km retry or debounce to 1 call |
| 10 | Map tile preflight | `tiles.json` GET on **every map mount**, uncached | `map_preview_style_loader.dart:56` | Cache style in memory (free fix) |
| 11 | Marketplace | bounded queries ≤50; booking txs small | `marketplace/*.ts` | Clean |

### Monthly cost model (Firestore billable ops, estimates)

Assumptions: driver "online" = foregrounded app, 8 h/day; presence 10 s cadence (current local/default path).

| Scenario | Presence writes/day | Presence reads/day | Monthly cost (presence only) |
|---|---|---|---|
| 100 drivers, fixed-10 s (flags OFF) | ~5.8 M | ~6.0 M | **~$8** — free tier absorbs most days |
| 1,000 drivers, fixed-10 s | 58 M | 60 M | **~$85/mo** |
| 1,000 drivers, adaptive (60 s stationary + merged cursor) | ~9 M | ~8 M | **~$14/mo** (~6× cut) |
| 10,000 drivers, adaptive | 90 M | 80 M | **~$140/mo** |
| Per ride lifecycle (create→dispatch→offer→assign→track) | ~30–60 W + ~150–450 R | — | **<$0.0001/ride** at realistic fleets |

**Rides, offers, marketplace, wallet are cost-insignificant at any plausible near-term volume. Presence writes are ~90% of projected Firestore spend.** The single highest-value change is ensuring `LOCATION_IDLE_MERGED_CURSOR=true` + `LOCATION_ADAPTIVE_FRESHNESS=true` (backend env) and `ORA_ADAPTIVE_PRESENCE=true` (mobile dart-define) ship in **every** deployed/release build — staging already sets them (`deploy_staging_cloud_run.sh:55`, `test_env_up.sh:91`, `build_staging_apk.sh:84`); the local-device APK script does not set `ORA_ADAPTIVE_PRESENCE` (dev convenience, harmless locally, but verify the production release pipeline does).

### Fixed vs variable

- **Fixed-ish:** Cloud Scheduler + Run Jobs CPU (~$0–5/mo inside free tier), Secrets Manager, Artifact Registry storage.
- **Variable:** presence writes (dominant), ride ops, Places calls, RTDB egress (passenger tracking listeners ~KBs/update — trivial at current volume), phone-auth SMS **(real money beyond free 10k/mo — this is a migration/billing risk to watch, not an architecture bug)**.
- **Found waste:** `firestore.indexes.json` has a duplicate `rides` composite index (lines ~59–80 vs ~215–236) — cosmetic, remove on next indexes deploy. No Redis/Memorystore in code (2 orphaned GCP Redis instances flagged in earlier migration notes ≈$72/mo — confirm deletion during cutover cleanup, needs approval).

---

## PHASE 2 — H3, caching, heartbeat analysis

### Benchmark (executed locally, `bench_geo.ts`, 200 random pickups/cell, clustered + sparse fleets, NEAREST_K=100)

Reads = simulated billed doc reads; exact% = matches brute-force nearest-K truth.

**Dense-city, fleet=10,000, radius 10 km / 25 km:**

| strategy | reads p50 (10km) | reads p50 (25km) | queries | exact% | ms/q |
|---|---|---|---|---|---|
| bbox (flat, pre-rings) | 4,033 | 8,739 | 1 | 100 | 18.6 / 49.1 |
| **bbox-rings (CURRENT)** | **410** | **412** | ~1.5 | **100** | **1.6** |
| h3-res7 | 3,370 | 8,338 | 2 / 12 | 100* | 24.7 / 57.4 |
| h3-res8 | 3,391 | 8,339 | 13 / 81 | 100* | 26.6 / 63.3 |
| geohash-p5 | 5,035 | 8,682 | 1 / 4 | 100 | 20.8 / 51.7 |
| geohash-p6 | 3,695 | 8,419 | 19 / 108 | 100 | 22.6 / 54.6 |

**Correctness defect found in naive H3 covering:** `polygonToCells` exact-cover drops drivers on boundary cells → `exact%` collapses to **29% (dense, 100 drivers, 10 km)** and **1.5% (sparse, 5,000 drivers, 10 km)** — i.e. real drivers inside the radius are missed. Fixing requires +1 kRing buffer, which inflates H3 reads further above the numbers shown. Geohash cell-intersection covering and both bbox variants remain 100% exact everywhere.

**Sparse-area:** all strategies trivial (hundreds of reads); H3 wins reads narrowly (207 vs 342 at 10k/10km) but is unacceptable on correctness. Ring expansion overhead is negligible.

### Verdicts

- **H3: DO NOT IMPLEMENT.** Loses ~8–20× on reads in the dominant dense-city case, carries a boundary-miss correctness defect without buffer cells, and adds an index field + write path to maintain. `h3-js` is in package.json for the benchmark only — it can stay dev-only or be removed.
- **Progressive-ring bbox: KEEP.** Already implemented, 100% exact, cheapest at every scale tested, ≤3 queries.
- **Caching:** driver-eligibility cache exists (15 s TTL). Do **not** add distributed caching (stale availability + cross-instance issues, and Redis is excluded by policy). Candidate micro-caches worth future measurement only: `rides/{id}` auth check on trip packets; pricing rules (`PRICING_RULES_CACHE_TTL_MS` already exists).
- **Adaptive heartbeat + presence expiry:** implemented but flag-gated; `geoDrivers` self-stale at 15 s (`N3_FRESHNESS_MAX_AGE_MS`) + sweeps — sound design. Ship flags everywhere.

---

## PHASE 3 — Firebase component readiness

| Component | State | Classification | Why / cost of skipping |
|---|---|---|---|
| Auth + UID/provider consistency | Working; emulator + device-verified; `register` idempotent, uid from token only | **REQUIRED NOW — done locally; verify once on new project after deploy** | Skipping = no sign-in. Zero added cost |
| Firestore data/indexes/rules | Rules deny-by-default (marketplace covered by catch-all; explicit deny recommended for clarity); 28 indexes, 1 duplicate | **REQUIRED BEFORE PRODUCTION** (rules + indexes deploy; cleanup dup index) | Missing index = queries fail hard at runtime |
| Data migration (old→new project) | Planned (UIDs must be preserved); not executed | **REQUIRED BEFORE PRODUCTION** — gated by your approval | Skipping = lose ride/profile/wallet history |
| RTDB tracking | Implemented: `tripLocations` + `rideAccess` ACL, rules locked, device-verified earlier | **DONE — REQUIRED for live tracking** | None |
| Firebase Storage | **Not used** — photos are bounded data URLs in Firestore | **RECOMMENDED BEFORE PRODUCTION (marketplace browse at scale)** — see §Storage analysis below | List-query egress amplification is the real cost; doc limit is safe but tight |
| FCM delivery | Implemented (outbox → projector → token sends); **real-device delivery unverified on new project** | **REQUIRED BEFORE PRODUCTION** | Skipping = silent dispatch failure — drivers never see invites |
| App Check | Fully wired; fail-closed prod guard; enforcement env-gated | **REQUIRED BEFORE PRODUCTION** (`REQUIRE_APP_CHECK=true` already in prod deploy script) | Console enforce-toggle must come after verified token flow |
| Android release | `key.properties` absent; no minify/R8; google-services.json = `oraapp-a9be5` ✓ | **REQUIRED BEFORE PRODUCTION** (generate keystore, wire signing; ProGuard optional hardening) | Can't ship unsigned; no cost |
| iOS | Not provisioned: no plist, no Podfile, stale old-project URL scheme in Info.plist | **REQUIRED ONLY IF iOS ships** — defer until needed | Skipping iOS = $0; do not spend on it yet |
| Cloud Run + Tasks | Scripts ready: min=0, max=10 prod / max=2 test, concurrency default; Tasks queues created only by test script | **REQUIRED BEFORE PRODUCTION**; add Tasks queue provisioning + `TASKS_*` env to prod deploy | Without Tasks, dispatch relies on 1/min sweeper — invites arrive late (reliability, not cost) |
| Production API + DNS (`api.ora.app`) | Not cut over — correctly frozen | **REQUIRED BEFORE PRODUCTION — explicit approval gate** | — |
| Monitoring/budgets | None configured | **RECOMMENDED BEFORE PRODUCTION**: billing budget alert ($0 code), uptime check on /healthz (free tier), error-rate alert | Cheap insurance against billing surprises |
| Marketplace backend | Implemented, local-verified (45+42 checks) | **DONE locally — REQUIRED BEFORE PRODUCTION** to deploy | — |
| Old-project resources | 2 orphaned Redis instances (~$72/mo reported) + old project resources | **REMOVE — during approved cutover cleanup** | Direct monthly waste |

---

### Marketplace photos: Firestore data URLs vs Firebase Storage (2026-11-18)

Verified current path: ≤6 JPEGs compressed to ~120 KiB each, stored as data URLs inside `marketplaceListings` docs. Works, zero cost locally, fits the 1 MiB doc limit with headroom (~720 KB worst case + fields).

| Factor | Data URLs in doc | Firebase Storage + URL fields |
|---|---|---|
| List-query payload | Whole doc incl. all photos per item (~600 KB × N items) | ~2 KB doc; cover image fetched on demand |
| Egress per browse | Pays for bytes never rendered; **no HTTP caching** — every doc read re-egresses | ~6× less on list views; CDN/browser cache works |
| Stored $/GB-mo | $0.18 (Firestore) | $0.026 (Storage) — 7× cheaper |
| Extra ops | none | Object GET ≈ $0.0004/10k (negligible) |
| Limits | hard 1 MiB/doc cap — tight but OK at current bounds | none |
| Migration | — | upload-on-create → store download URLs; decode path already isolated in `photoProvider`/`listing_photo_codec` |

Estimate at 10k listing-views/day: data-URL ≈ 6 GB/day egress (~$22/mo) vs Storage ≈ $4–8/mo. **Recommendation: keep data URLs for local dev ($0, verified); plan the Storage migration BEFORE production launch with real browse traffic — it is not urgent but it is the cheaper reliable option at scale, and prod needs Blaze anyway.**

---

## PHASE 4 — Reliability & scale

### What the code already handles (evidence)

- **Double assignment:** claim inside transaction on `driverInviteResponses` + `activeAssigned` query guard + offer claim tx — two drivers can't both win (`invite_service.ts`, `ride_service.ts` createOffer).
- **Duplicate requests/bookings:** Idempotency-Key everywhere + marketplace duplicate-active-booking guard (409) + rental overlap guard — verified live (45-check E2E).
- **Invite expiry:** 20 s TTL, wave ledger docs, accelerate-on-decline fast path, deadline task wakeups + 1/min sweep backstop.
- **Partial outages:** outbox events are durable (Firestore), projector reclaims expired CLAIMED deliveries — FCM retry survives projector crashes.
- **Cold starts:** min=0 → cold start on first request only; acceptable for cost; dispatch latency affected only on first ride after idle (consider keeping this — documented trade-off, ~1–3 s).
- **Contention:** per-driver stream cursor txs reject out-of-order seq; ride doc is the hot spot per ride — fine at ≤1 writer/s per ride.

### Risks worth noting

- `listTokensForDriver` unbounded (grow-slow leak) → add limit.
- `accelerateIfWaveResolved` invite-response query has no `.limit()` (bounded by wave size ≤15, but enforce it).
- `selectOffer` supersede fan-out ≤50 writes in one tx — Firestore tx limit is 500; fine but retry-costly under contention; monitor.
- Simultaneous driver accepts resolve correctly (tx claim) — loser gets conflict; verify UX handles it gracefully (offer already taken → refresh).

### Load-test plan (local/simulated first; live only with approval)

| Scale | Driver presence | Ride creation | Concurrency | Pass criteria |
|---|---|---|---|---|
| 100 drivers | 100 publisher sims @10 s | 1 ride/min | 20 customers | p95 match <1.5 s, 0 double-assigns |
| 1,000 | idem | 5 rides/min | 100 | p95 <2 s, err <0.1% |
| 5,000 | idem | 15 rides/min | 300 | p95 <3 s, p99 <6 s, reads/ride <500 |
| 10,000 | idem | 30 rides/min | 500 | p95 <4 s, sweep lag <60 s, cost/ride <$0.001 |

Method: emulator + memory-Firestore for functional correctness at 1–1k (already proven patterns: `run_local_emulator_e2e.ts`, courier E2Es); a **dedicated load project** on Blaze for live scale — the emulator cannot measure real Firestore latency/cost. Do not extrapolate emulator latency to production; mark results SIMULATED vs LIVE explicitly.

---

## PHASE 5 — Decision table & final architecture

| # | Item | Current | Necessary? | Cost impact | Complexity | Priority | Recommendation |
|---|---|---|---|---|---|---|---|
| 1 | Adaptive presence + merged cursor + freshness flags | implemented, flag-gated; OFF in local APK script | Yes — ~6× presence-cost cut | **Saves ~$70–120/mo per 1k–10k drivers** | zero (flags) | **P0** | **IMPLEMENT** — set in all release/test deploys (already in staging) |
| 2 | H3 index | benchmark only | **No** — loses reads + correctness | would cost more | high | — | **DO NOT IMPLEMENT** |
| 3 | Progressive-ring geo | implemented | — | saves ~8–20× matching reads vs alternatives | — | — | **KEEP CURRENT** |
| 4 | Redis/Memorystore | none in code; 2 orphaned instances in old GCP | No | removing saves ~$72/mo | n/a | P0 at cutover | **REMOVE** orphaned instances (approval-gated) |
| 5 | Cloud Tasks dispatch wakeups | code ready; queue only in test env | Yes for invite latency | ~free at scale (<free tier) | low | P1 | **IMPLEMENT** in prod deploy script |
| 6 | Trip-packet ride-auth read | 1 uncached read/packet (~15/min/driver) | Nice-to-have | ~$5–15/mo @1k drivers | low | P2 | **SHOULD OPTIMIZE** — cache on stream doc |
| 7 | Token queries `.limit()` | unbounded | hygiene | tiny | trivial | P2 | **IMPLEMENT** |
| 8 | MapTiler preflight cache | HTTP every map mount | nice | small tile-volume cut | trivial | P3 | **SHOULD OPTIMIZE** (memory cache) |
| 9 | Nearby-search 2-call retry | up to 2 paid calls/geocode | nice | halves that SKU | trivial | P3 | **SHOULD OPTIMIZE** (debounce/single call) |
| 10 | `listOpenRides` 200-doc scan | bounded, in-memory filter | only if driver-open feed scales | moderate | medium | P3 | **DEFER** — revisit with real traffic |
| 11 | Firebase Storage for photos | data URLs work, verified | only when photo limits pinch | Blaze-dependent anyway | medium | P3 | **DEFER** |
| 12 | iOS provisioning | absent | only if iOS ships | Apple program $99/yr | medium | P4 | **DEFER** |
| 13 | Budget alerts + uptime check | absent | cheap insurance | ~$0 | trivial | P1 | **IMPLEMENT** at deploy time |
| 14 | VPC connector / always-on | none | No | would add fixed $ | — | — | **DO NOT IMPLEMENT** |
| 15 | Min instances >0 | min=0 everywhere | No (cold-start ~1–3s acceptable) | always-on cost | — | — | **DO NOT IMPLEMENT** |
| 16 | ProGuard/R8 release | absent | optional hardening | $0 | low | P3 | **DEFER** |
| 17 | Duplicate Firestore index | present | cleanup | $0 | trivial | P4 | **REMOVE** on next indexes deploy |

### Final recommended architecture (minimum components)

Cloud Run (min 0) — Express modular monolith → Firestore (SoT: users, rides, offers, waves, outbox, geoDrivers, marketplace, wallet) → RTDB (trip live-tracking only) → Cloud Tasks (dispatch wakeups) → Cloud Scheduler+Run Jobs (sweeps) → FCM (free) → Firebase Auth + App Check → Places (session-tokened) + MapLibre tiles. **No Redis, no VPC, no always-on resources.**

---

## MUST implement before production (approval-gated)
1. ~~Ship adaptive-presence flags~~ **DONE (2026-11-18, verified)** — `dev_emulator_backend.sh`, `build_local_device_apk.sh`, `build_staging_apk.sh` (already), `build_production_release.sh`, `deploy_production_cloud_run.sh` all set the flags; mobile defaults adaptive ON for non-dev envs (`ORA_ENV != development`) so release builds can't silently fall back. Live-verified on emulators (`scripts/test_adaptive_presence.ts` — 17/17: merged cursor halves billed tx, adaptive horizon keeps matching at 60s cadence past the 15s legacy cutoff, trip geo-marker throttle 3 packets→≤1 write while RTDB tracking unaffected, keepalive works, stale drivers drop out, no phantom invites, dispatch create→invite ~2.5s, seq-violation 422 preserved). Mobile 42/42 + backend 40/40 tests green.
2. Provision Cloud Tasks queue + `TASKS_*` envs in prod deploy (P1, invite latency — currently falls back to 1/min sweeper).
3. Deploy rules/indexes (drop dup index), verify FCM on real device, enforce App Check after token flow verified.
4. Keystore signing for Android release; billing budget alert + uptime check.
5. Approved cutover sequence incl. data migration preserving UIDs and deletion of orphaned Redis/old resources.

## SHOULD optimize (cheap, safe)
Token-query limits, trip-packet auth read cache, map-preflight cache, Nearby-search single-call, ProGuard at release time.

## Do NOT implement
H3 (benchmarked worse + incorrect at boundaries), Redis/Memorystore, VPC connector, min-instances>0, premature Firebase Storage migration, iOS work before there's an iOS requirement.

## Live GCP inventory (read-only `gcloud`, authenticated `vezeon.live@gmail.com`, 2026-11-18)

### `oraapp-a9be5` — new project. Billing: **ENABLED** (`billingAccounts/016C7D-…`)

| Resource | State | Billable? |
|---|---|---|
| Cloud Run services | **NONE** (both regions) | — |
| Cloud Run jobs | **NONE** | — |
| Scheduler jobs | **NONE** (asia-south1, us-central1) | — |
| Tasks queues | **NONE** (both regions) | — |
| Redis/Memorystore | **API not even enabled** — zero possible | — |
| VPC connectors | **API not even enabled** — zero possible | — |
| Secrets | none | — |
| Artifact Registry | `cloud-run-source-deploy` repo, **empty** | ~$0 |
| GCS buckets | `run-sources-oraapp-a9be5-asia-south1` = **1.8 MB** | ~$0.00/mo |
| Enabled APIs | run, scheduler, tasks, firestore, identitytoolkit, fcm, secretmanager, storage, artifactregistry (+bigquerystorage, runtimeconfig) | APIs enabled ≠ billed; usage only |

**Verdict: near-zero recurring cost today. Nothing on the new project requires deletion.** Optional tidy (worth <$0.01/mo, zero urgency): empty AR repo + 1.8 MB run-sources bucket — both auto-recreate on next `--source` deploy; deleting them is cosmetic.

### `ora-app-d8112` — old project. Billing: **DISABLED** (multiple APIs return `BILLING_DISABLED`)

- `vezeon.live@gmail.com` does NOT have owner-level access (billing describe, run list, secrets list all permission-denied). Resource-level inventory is **not possible** with current IAM.
- **Consequence: nothing on the old project can currently bill.** If orphaned Redis instances exist there (earlier estimate ~$72/mo), they are inert while billing stays off.
- **Do NOT re-enable billing** on the old project to inspect it — that would make any live resources billable again. If full inventory is needed, get IAM access to the project and use the **Console** (Asset Inventory) without touching billing.
- Cloud Tasks API never enabled on old project either.

### Migration completeness matrix (per component)

| Component | Migrated | Configured | Locally tested | Live-tested | Production-ready |
|---|---|---|---|---|---|
| Firebase Auth (users/UIDs) | ❌ pending cutover | ✅ emulator + project flags | ✅ (OTP flow device-verified) | ❌ | needs data migration |
| Firestore rules | — | ✅ deny-by-default | ✅ rules test suite | ❌ | deploy at cutover |
| Firestore indexes | — | ✅ 28 entries (1 dup) | ✅ emulator queries | ❌ | deploy at cutover |
| Firestore data (rides/users/wallet) | ❌ pending | — | ✅ emulator E2E | ❌ | needs export/import preserving UIDs |
| RTDB trip tracking | — | ✅ rules + code | ✅ emulator + device | ✅ (old project) | switch URL at cutover |
| FCM | — | ✅ outbox→projector→sender | ✅ projector tests | ✅ (old project) | needs real-device verify on new |
| App Check | — | ✅ env-gated, fail-closed | ✅ | ❌ | enforce post-verify |
| Marketplace backend | — | ✅ complete | ✅ 87 live E2E checks | ❌ | deploy at cutover |
| Vendor approval gate | — | ✅ complete | ✅ 10/10 + 45-check E2E | ❌ | needs admin approval path |
| Wallet/commission | — | ✅ complete | ✅ 26 tests | ❌ | deploy at cutover |
| Adaptive location flags | — | ✅ all 5 build/deploy paths | ✅ 17/17 live checks | ❌ | ready for deploy |
| Android release | — | ⚠ signing gate coded, no keystore | ✅ debug builds | ❌ | needs keystore |
| iOS | — | ❌ not provisioned | ❌ | ❌ | deferred — no requirement |
| Storage (photos) | — | ❌ data URLs instead | ✅ | ✅ | optional pre-launch |
| DNS `api.ora.app` | ❌ frozen | — | — | — | explicit GO required |

### Deletion approval list — NOTHING urgent exists

No resource on `oraapp-a9be5` costs meaningful money. The only deletable items (optional, ~$0 savings):

```bash
# OPTIONAL — cosmetic cleanup only, both auto-recreate on next source deploy
gcloud artifacts repositories delete cloud-run-source-deploy \
  --project=oraapp-a9be5 --location=asia-south1
gcloud storage rm -r gs://run-sources-oraapp-a9be5-asia-south1
# NOT RECOMMENDED to run — no benefit, deploys recreate them.
```

Old-project resource deletion (if any exist) requires: (a) IAM access for `vezeon.live@gmail.com`, (b) confirming billing stays OFF, (c) data-migration verification that nothing in `ora-app-d8112` is still needed (Auth users, Firestore docs, Storage). **No deletion was performed.**

---

## Shared wallet audit (new code, `src/wallet/`)

Verified in code — **sound design, no changes needed**:

- **Atomic commission**: `chargeCommissionInsideTx` runs INSIDE the completion tx for both rides (`RIDE_COMPLETED`, base = delivery fare only — courier shopping totals correctly excluded) and marketplace bookings (`complete`). Deterministic ledger id `commission-{type}-{id}` → exactly-once on tx retry.
- **Negative balances**: allowed at settlement (earning never blocked), but `assertWalletEligibleInsideTx` (402) blocks NEW accepts — driver invite-accept AND vendor booking-confirm. inDrive-style recharge gate. ✓
- **Withdrawals**: user creates PENDING `walletTopups` (idempotent); resolution only via `/v1/internal` worker-auth router (token + OIDC SA allowlist) — users cannot self-credit. Approve posts ledger + balance atomically; debit kind guarded by `INSUFFICIENT_BALANCE`; re-resolve is idempotent. ✓
- **Role model**: one shared account per UID; `role` stamped on each ledger entry → per-role earnings/reporting preserved. ✓
- **Reconciliation**: every entry carries `balanceAfterMinor`, `grossMinor`, `commissionBps`, `sourceType`/`sourceId`. ✓
- 10% = default `commissionBps: 1000` per role in `walletConfig/global` (code default, doc-overridable).

### ⚠ Two findings (new this pass)

1. **Latent double-charge risk**: the older `feePolicies`/`derivePayoutSnapshot` still runs at offer-select and writes `driverPayoutMinor`/`platformFeeMinor`. Launch policy resolves to fee NONE, so today it's harmless — **but if a nonzero `feePolicies/_global` doc is ever created, drivers would pay BOTH the platform fee (reduced payout) AND the 10% wallet commission.** Rule: activating feePolicies must replace, not coexist with, wallet commission. Add a code comment/guard when fees are activated.
2. **`DRIVER_AUTO_APPROVE` defaults ON** (`driver_auto_approve.ts` — true unless env='false'/'0'; no deploy script sets it). Any driver application is instantly approved in every environment — bypassing the pending→approved review model vendors now use. **P1 fix for production: add `DRIVER_AUTO_APPROVE=false` to `deploy_production_cloud_run.sh` when real admin review exists; until an admin approval path is ready, auto-approve may be intentional for launch — decide explicitly, don't leave it accidental.**

Tests: `wallet.test.ts` + `fee_policy.test.ts` — 26/26 pass. Full backend suite 781/784 pass; the 3 failures (`marketplace.test.ts`×1, `rides.test.ts`×2) pass in isolated rerun — parallel-runner flakiness, not regressions (same pattern noted previously).

---

## Production-critical rollout sequence (approval-gated, ordered)

| Step | Item | Prep now (local, $0) | Cloud action (needs GO) |
|---|---|---|---|
| 1 | Cloud Tasks | `src/tasks/dispatch_tasks.ts` ready; queue flags tested in `test_env_up.sh` | Create `ora-dispatch` queue in prod (same settings as test but saner rates: max-dispatches ~50/s, max-concurrent ~50), set `TASKS_PROJECT_ID/TARGET_BASE_URL/OIDC_SERVICE_ACCOUNT/DISPATCH_TASKS_ENABLED=true` in prod deploy |
| 2 | Rules + indexes | `firestore.rules`, `firestore.indexes.json` ready; drop the duplicate `rides` composite entry | `firebase deploy --only firestore:rules,firestore:indexes --project oraapp-a9be5` |
| 3 | FCM real device | FCM sender wired; needs a real device token end-to-end on prod | Deploy → register device token → send test dispatch → confirm delivery; only then enable for all |
| 4 | App Check | Env-gated enforcement already coded; prod deploy sets `REQUIRE_APP_CHECK=true` | After real-device token flow verified → enforce in console for Firestore/RTDB/Storage |
| 5 | Android signing | `build.gradle.kts` fails closed without `key.properties` | Generate upload keystore locally, store `key.properties` out of repo, add to CI secrets later |
| 6 | Billing safeguards | none | Budget alert (e.g. $10/$25/$50 thresholds — informational only), uptime check on `/healthz`, log-based alert on `PRICING_UNAVAILABLE`/5xx rate |
| 7 | DNS cutover | frozen by policy | `api.ora.app` remap ONLY after 1–6 verified live |

Optional follow-on (not a blocker): `LOCATION_STREAMS_BACKEND=rtdb` moves the per-packet cursor tx off billed Firestore entirely (byte-identical semantics, code ready) — evaluate after prod is stable.

## Phase 6 — Cloud E2E pre-deployment spec (AWAITING EXPLICIT CLOUD GO)

### Exact resources to create (all on `oraapp-a9be5`, all scale-to-zero)
| Resource | Config | Worst-case cost |
|---|---|---|
| Cloud Run `ora-auth-service` | asia-south1, `--source`, min=0, max=2, 512Mi/1CPU, concurrency 50, `--clear-vpc-connector --remove-secrets=REDIS_URL`, `DRIVER_AUTO_APPROVE=false` | ~10k requests × seconds-billing ≈ **$0.01–0.05** |
| Cloud Tasks queue `ora-dispatch` | asia-south1, rate 10/s, 3 retry attempts | few hundred ops ≈ **$0.00** |
| Secret `ora-test-worker-token` | random 32-byte, single version | $0.00 (≤6 free) |
| Scheduler teardown job | one-shot deadline T+60min → calls teardown | $0.00 |
| AR image + run-sources blob | auto from `--source` | ~MBs, $0.00 |

APIs already enabled — nothing new to enable. **No Redis, no VPC, no paid resources.**

### Safety controls
- Synthetic-only data: `cloud-e2e-*` uid/doc prefixes; zero prod-user, wallet, ride, or financial doc writes
- `REQUIRE_APP_CHECK=false` for this isolated test only (App Check enforcement verified separately pre-prod)
- `GEO_BACKEND=firestore`, all three cost flags on — production-parity config
- `api.ora.app` untouched; old project untouched
- Routing = haversine fallback (no paid Google Routes calls during test)

### Test plan (≈30–45 min)
Auth → register → driver pending → admin-approve via new endpoint → online → presence → estimate → ride create → wave-1 invite (Cloud Tasks) → accept → select → assign → RTDB tracking → complete → commission ledger → marketplace listing+booking → invite expiry → teardown.

### Teardown (deadline + manual)
Dead-man Scheduler at T+60min deletes Cloud Run service; then manual verify-delete: service, queue, secret, AR images, Scheduler job. `test_env_down.sh` automates the list. **Estimated total: <$0.10; $1 budget alert = signal, not cap.**

## Consolidated P0/P1/P2 (final pass, 2026-11-18)

### GPS/location throttling verdict — KEEP CURRENT
Mobile already does: 15 m movement gate + 4 s min interval + 15/min cap (trip), adaptive 10 s/60 s cadence (idle), keepalive on GPS stall, background/app-close stops, foreground-only GPS. Server does: seq cursors (exactly-once per stream), merged cursor tx, trip-marker 45 s throttle, adaptive `freshUntilMs`. **Adding more client throttling buys nothing measurable — movement gating already cuts ~85% of idle packets; deeper cuts risk stale markers and missed invites. No changes recommended.**

### P0 — costs money or blocks launch
| Item | Status | Evidence | Action |
|---|---|---|---|
| Adaptive presence flags | **DONE — wired in all 5 build/deploy paths + code-level fail-safe** | `test_adaptive_presence.ts` 17/17 live-verified | none |
| Orphaned/old-project billing | **Resolved** — old project billing DISABLED; new project has no billable idle resources | gcloud inventory above | none — do not re-enable old billing |
| Firebase Auth migration + UID preservation | planned, not executed | — | approval-gated cutover |
| `api.ora.app` DNS | frozen correctly | — | last step, after validation |

### P1 — production-critical, ~$0
| Item | Status | Action |
|---|---|---|
| Cloud Tasks queue + envs in prod deploy | code ready, test-verified | add to prod rollout step 1 |
| `DRIVER_AUTO_APPROVE=false` in prod | **default ON everywhere today — decision needed** | set env in prod deploy once admin review exists |
| rules/indexes deploy (drop dup index) | files ready | firebase deploy at cutover |
| FCM real-device verification | code ready, unverified on device | post-deploy check |
| App Check enforcement | env-gated, fail-closed coded | console enforce after token verify |
| Android keystore | fails closed without `key.properties` | generate + store securely |
| Budget alert + uptime check | absent | cheap insurance at deploy |

### P2 — measured-optional
| Item | Status | Action |
|---|---|---|
| Firebase Storage for marketplace photos | data URLs verified working; Storage cheaper at browse scale (~$22→$4-8/mo @10k views/day) | migrate pre-launch or at first scale signal |
| `LOCATION_STREAMS_BACKEND=rtdb` | code ready; removes per-packet cursor Firestore tx | evaluate post-launch |
| `listOpenRides` 200-doc scan | bounded, rare | defer |
| token-query `.limit()` hygiene | unbounded but tiny | small patch when convenient |
| iOS | absent | defer until requirement exists |

## Backend module inventory (for next development phase)

**FULLY IMPLEMENTED AND VERIFIED** (unit + live emulator E2E):
Auth + registration + mode-switch; driver onboarding + **admin approval endpoint**; presence/location (adaptive heartbeat, merged cursor, trip throttle); progressive-radius geo matching; dispatch waves + invite TTL + accept/decline/idempotent; offer→select→assign; full ride lifecycle + courier OTP; ratings; shared wallet (atomic commission, ledger, topup, withdrawal gate); marketplace listings CRUD + bookings lifecycle + vendor approval gate; pricing estimates; FCM outbox projectors; internal sweeps + cleanup; App Check gate; rate limiting; idempotency everywhere.

**PARTIALLY IMPLEMENTED:**
- Admin ops — approval endpoint exists + verified, but **no admin UI/console** (approvals currently via internal endpoint or doc writes)
- Marketplace photos — data URLs work; Firebase Storage upload path deferred (cost analysis done)
- Observability — `logSafe` structured logs exist; no dashboards/alerting wired
- Auth data migration — cutover tooling (UID-preserving export/import) not yet built

**NOT STARTED:**
- Production Auth/Firestore/RTDB data migration execution + validation tooling
- Admin dashboard backend (role: admin surface for driver/vendor approvals, wallet resolve UI, ride monitoring)
- Scheduled production sweeps wiring (Scheduler jobs — endpoint exists, jobs not provisioned)
- Load-test harness beyond the geo benchmark (10k-driver E2E load needs dedicated project)
- Driver payout/settlement disbursement (cash model today — no payment gateway by design)

## Explicitly not claimed
Production performance, FCM delivery, and billing figures are **estimates/simulations**; live scale validation (10k drivers) requires a dedicated load project and your approval. Emulator results prove correctness, not production latency.
