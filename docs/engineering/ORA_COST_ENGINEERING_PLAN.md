# Ora Cost Engineering Plan

Date: 2026-11-24. All figures **[CALC]** — modeled from verified unit
prices and code-measured op counts, NOT billing data. Billing truth
requires Console → Billing → Reports (still pending per prior audit).

Price card used (us-central1 / asia-southeast1, list):
Firestore read $0.30/M · write $0.90/M · delete $0.12/M · storage
$0.18/GiB-mo · free/day 50k read / 20k write / 20k delete.
Cloud Run $0.000024/vCPU-s · $0.0000025/GiB-s · $0.40/M req ·
free/mo 180k vCPU-s / 360k GiB-s / 2M req.
RTDB Blaze $1/GiB download · $5/GiB stored (Spark: 100 conns,
10 GiB/mo download, 1 GiB stored free).
Scheduler $0.10/job-mo (3 free). Secret Manager ~$0.06/version-mo.
Cloud Logging ~$0.50/GiB ingest (first 50 GiB/mo free per project).
Routes ~$5/1k calls. Places (New) ~$2.83/1k autocomplete,
~$5/1k details (10k free/SKU/mo).

---

## 1. Cost driver inventory (code-verified op counts)

### 1.1 Driver presence — dominant usage cost

| Path | Ops per accepted packet | Source |
|---|---|---|
| Idle, flags OFF (legacy) | ~2R + 2W (eligibility cache miss amortized + streamStore tx + geo tx) | `location_update_service.ts`, `stream_store.ts` |
| Idle, merged cursor ON | **1R + 1W** measured on real Firestore emulator (28/28 proof) | prior audit §B |
| Trip mode | +1 ride-doc read per packet (authz) + streamStore tx + RTDB write + geo write | `location_update_service.ts:241-289,343-375` |

Cadence (mobile `PresencePublishPolicy`):
- Fixed (flag OFF): 10 s → 360 packets/driver-online-hour… correct:
  360/hr → 2,160 per 6 h day.
- Adaptive (flag ON): 30 s stationary / 10 s moving / 8 s invite-boost
  → expected ~1,440/driver-day (50/50 split) [CALC from code cadences].

Per-packet logging: `LOCATION_UPDATE` + `REDIS_GEO_PROJECTED` =
**2 structured log lines per packet** → at 1,440 packets/driver-day ×
216 drivers (1k DAU × 15%) ≈ 622k log lines/day ≈ ~0.3–0.6 GiB/mo
[CALC, ~400–800 B/line]. Inside free tier at 1k DAU; material at 10k.

### 1.2 Ride lifecycle (per booking ≈ 25% of DAU/day)

| Action | Firestore ops [VC] |
|---|---|
| createRide | tx: idem + ride + outbox ≈ 3W + reads |
| dispatch (per wave ≤3) | findNearby (~13 RPCs, ~54 geo hits @1k fleet) + revalidation ctx (~4 batched read sets) + wave doc + ride update + outbox ≈ ~300–800 reads/booking worst case, typical ~150–300 |
| offers inbox poll | 1 ride + ≤page offers per poll; 2→3→5 s backoff, 6-min cap ≈ ≤~80 polls/searching episode |
| active ride poll | GET /rides/:id = 1 read; 3→5→8 s, 4-h cap ≈ ≤~3,000 reads/4h ride worst case, typical ride ~30–60 min ≈ ~500–1,000 |
| lifecycle transitions | ~5–10 txs total per ride |
| ratings | 2 txs |

### 1.3 Sweeps (per minute when enabled)

8 sweeps coalesced → 1 invocation/min ≈ 43,200 invocations/mo.
Each: ~8–15 Firestore queries; empty-result queries bill **0 reads**
(Firestore charges per doc returned) but cost Cloud Run request time
(~3.4 s measured staging) → ~150 vCPU-s/day ≈ well inside free tier.
Per-sweep schedulers (legacy): ×7 executions → ~$5–30/mo floor [CALC].

### 1.4 External APIs

| API | Trigger | Cost driver |
|---|---|---|
| Google Routes | every `/v1/pricing/estimate` (when `GOOGLE_MAPS_SERVER_KEY` set; haversine only if `ORA_ROUTING_PROVIDER=haversine`) | ~$5/1k; multi-stop without `computeRoute` → **up to 9 sequential calls/estimate** (`estimate_service.ts:227-246`) |
| Nominatim/Places | place search debounced ≥3 chars | Nominatim free/self-hostable; Google Places fallback paid |
| FCM | per dispatch wave per driver + ride-state events | free tier generous; data-only |
| RTDB | trip tracking: driver write ~4 s + passenger read mirror | $1/GiB download; ~200 B/packet → ~0.65 MB/driver-hour → **~$0.65/100 driver-hours** [CALC] — trivial; connection count is the real constraint (Spark 100) |

### 1.5 Fixed standing costs (cloud-verified Nov 4 [VCL])

| Resource | State | ~$/mo |
|---|---|---|
| `ora-production-n3-redis` BASIC 1GB | exists, prod unwired pending deploy | ~36 |
| `ora-staging-vpc` connector (misattached to prod) | exists | ~23 |
| `ora-production-redis-url` secret | exists | ~0.1 |
| Staging schedulers ×7 | paused after window | 0 |
| Prod schedulers ×6 | paused | 0 |
| Cloud Run services ×2 | minScale 0 | ~0 idle |
| Secret Manager ~5 versions | — | ~0.5 |

**Standing waste until prod rollout + cleanup: ~$60–95/mo.**

---

## 2. Monthly scenarios [CALC]

Assumptions: drivers = 15% DAU, 6 h online/day; bookings = 25% DAU/day;
50/50 stationary split; avg ride 45 min; presence merged+adaptive ON;
sweep floor coalesced ~$5; Routes on estimates; Places mostly Nominatim.

| Scale | Firestore | Cloud Run | Routes+Places | RTDB+FCM+misc | Sweeps+fixed | **Total/mo** |
|---|---|---|---|---|---|---|
| 100 DAU | ~$2 | ~$3 | ~$2 | <$1 | ~$6 | **~$13** |
| 1,000 DAU | ~$9 | ~$12 | ~$15 | ~$2 | ~$6 | **~$44** |
| 5,000 DAU | ~$45 | ~$55 | ~$70 | ~$8 | ~$8 | **~$185** |
| 10,000 DAU | ~$95 | ~$110 | ~$140 | ~$15 | ~$10 | **~$370** |

Sensitivity ±40% (driver share 10–20%, online 4–8 h). Consistent with
prior model ($28–35 @1k optimized) — this table is slightly more
conservative on Routes/Places.

### Driver-heavy vs passenger-heavy

| Workload | Dominant cost | Why |
|---|---|---|
| Driver-heavy (e.g. 50% DAU drivers, 8 h online) | presence writes+requests ≈ 60–70% of bill | 1R+1W × ~1,900 packets/driver-day |
| Passenger-heavy (5% drivers) | ride lifecycle reads (polling) + estimates/Routes | active-ride poll ~1 read/3–8 s + offers inbox |

At 10k DAU all-driver fleet (extreme): presence ≈ $280/mo alone —
still inside model; geo reads stay flat (benchmark-verified to 10k
fleet, 0 misses).

---

## 3. Optimization ledger (status)

| # | Item | Status | Est. savings |
|---|---|---|---|
| O1 | Adaptive presence heartbeat | implemented, flag OFF | −33% presence req |
| O2 | Merged idle cursor (1W/packet) | implemented, flag OFF | −50% presence writes |
| O3 | Adaptive freshness `freshUntilMs` | implemented, flag OFF | enables O1/O2 |
| O4 | Coalesced `/sweeps/all` + SEARCHING guard + 503 | implemented | ~$25/mo floor → ~$5 |
| O5 | Pricing-rules TTL cache | implemented, env-gated | −1 read/estimate |
| O6 | N3 latency hardening (parallel reads, batched revalidation) | implemented local | latency, not $ |
| O7 | Geodesic lng-box fix | implemented, always-on | correctness |
| O8 | Prod Redis+connector+secret deletion | **pending deploy+approval** | **~$60–95/mo** |
| O9 | Prod schedulers → coalesced endpoint | pending | ~$5–25/mo |
| O10 | Route-result geohash cache | deferred (trigger: Routes >$20/mo) | 30–50% Routes calls |
| O11 | H3/geohash geo partitioning | rejected ≤5k fleet (benchmarked) | ≤15% reads, 16–99× fan-out |
| O12 | RTDB geo/onDisconnect presence | rejected (Spark 100-conn) | — |
| O13 | Memorystore GEOSEARCH | rejected ($59+/mo floor) | — |
| O14 | Per-packet log sampling | **gap — not implemented** | log ingest at scale |
| O15 | Trip-authz cache (GAP-011) | proposed | −1 read/trip packet (~25% trip reads) |
| O16 | Estimate snapshot write reduction | proposed (see §4) | −1 write/estimate |
| O17 | avatarData out of users doc | DR-003 conditionally approved — Storage *conditionally feasible*; $0 NOT guaranteed (billing exposure possible); option S vs F1 awaiting owner selection; no bucket creation authorized (see §4a) | egress on hot reads |

---

## 4. New cost findings from this audit

| ID | Finding | Ops/cost | Sev |
|---|---|---|---|
| C-1 | `pricingSnapshots` doc written on **every** estimate, incl. abandoned ones (`estimate_service.ts:327-338`). Estimates per booking ≈ 3–8 (pin drags) → ~4× writes vs bookings. Bounded by 10/min rate limit. | +~3–7 writes/booking ≈ trivial $ but nonzero; snapshot TTL cleanup exists | P2 |
| C-2 | Multi-stop estimate fallback = up to **9 sequential `computeDriveRoute` calls** when provider lacks `computeRoute` (`estimate_service.ts:227-246`). With Google provider `computeRoute` exists — check which path prod takes [RT]. | Routes spend multiplier on courier v2 estimates | P2 |
| C-3 | Per-packet double logging (§1.1) — no sampling anywhere (`logSafe` → console.log always). | ~0.3–0.6 GiB/mo @1k DAU driver-heavy; ×10 at 10k | P2 |
| C-4 | `avatarData` ≤400 KB in `users/{uid}` — read by `loadActor` + N3 `getAll` batches. Currently masked by GAP-003 (uploads fail >32 kb) — fixing the bug naively activates the cost. | up to ~400 KB × every users-doc read | P2 |
| C-5 | `outboxEvents` terminal docs never deleted (GAP-009). | storage growth only; sweeps unaffected | P3 |
| C-6 | `listOpenRides` scans ≤200 ride docs per refresh (`OPEN_DISCOVERY_SCAN_CAP`); pull-to-refresh only — no auto-poll. Bounded. | ≤200 reads/driver refresh | P3 |
| C-7 | `geoDrivers` expired docs linger (no TTL policy confirmed; cleanup service doesn't cover collection). Bounded to 1 doc/driver-ever. | negligible | P3 |

## 4a. DR-003 storage feasibility (decided 2026-11-24 — conditional)

Owner constraint: Firebase-based storage preferred, **zero additional
cost**, no paid service activation without approval.

Verified against firebase.google.com/pricing (re-verified 2026-11-24
second pass):

- **Prerequisite:** Cloud Storage for Firebase requires **Blaze** —
  `ora-app-d8112` is already Blaze → no upgrade needed, **but Blaze
  has no hard spend cap**: anything beyond no-cost quotas bills
  automatically.
- **No-cost quota (`*.firebasestorage.app` + additional buckets):**
  5 GB-months stored · 100 GB/mo downloaded · **5K upload ops/mo ·
  50K download ops/mo** — **only in `us-central1`, `us-west1`,
  `us-east1`** → bucket MUST be `us-central1`. Quotas are
  project-level; no-cost usage calculated daily.
- **Egress caveat:** the 100 GB/mo free download is documented for
  qualifying (largely North-America) destinations — Pakistan-user
  downloads may not qualify → verify from actual billing data before
  claiming $0. Absolute exposure is small (single-digit $/mo worst
  case at launch) but it IS billable.
- **Modeled usage [CALC]:** avatars ~50 KB × ~30% of 1k DAU ≈ 20 MB;
  KYC ~1 MB/application × even 500/mo ≈ 0.5 GB; uploads few hundred/mo
  ≪ 5k/mo. Comfortably inside quotas — **storage/ops side**.
- **Beyond-quota rates:** GCS Standard storage ~$0.02–0.026/GB-mo,
  egress ~$0.12/GB first tier (asia may differ), ops ~$0.05/10K
  uploads / ~$0.004/10K downloads.
- **Conclusion:** $0 is *conditionally* achievable — requires
  us-central1 bucket + quota/budget alerts + monthly billing
  verification. Not guaranteed by the free tier alone. Fallback F1
  (Firestore private docs) has zero new billing surface.

**Access model:** avatars = app-scoped (download token / rules-gated);
KYC = strictly private prefix, Admin-SDK signed URLs only after
`drivers.review.pii` + audit-logged read. No binaries in Firestore.

## 5. Cost risk register

| Risk | Mechanism | Guard today | Residual |
|---|---|---|---|
| Retry storm | dio retries GETs ×3 exp-backoff; presence publisher backoff 2→30 s | good | low |
| Polling storm | all polls bounded with caps | good | low |
| Duplicate schedulers | staging had 7 individual + 1 coalesced during soak window (idempotent) | window closed | ensure prod uses ONE coalesced job |
| Unbounded listeners | only RTDB trip listener, ride-state gated | good | Spark 100-conn cap at >~100 concurrent tracked trips → Blaze decision (DR pending) |
| Unbounded queries | all sweeps `limit`-bounded; geo scan capped 5000 + 33-query split bound | good | low |
| Expensive logging | per-packet logs (C-3) | none | medium at scale |
| Maps API misuse | haversine flag exists; estimate rate-limited 10/min | partial | route cache deferred by design |
| Media re-download | no media features | n/a | n/a |
| Runaway background | presence stops on background; trip publisher heartbeat-bounded | good | low |
| Avatar body-limit bug (GAP-003) | ironically *prevents* C-4 cost today | — | fix carefully (DR-003) |

## 6. Budget protection recommendations (do NOT configure now)

1. Billing budget alerts already exist ($1 budgets on both projects
   per Oct-21 state doc) — raise to realistic thresholds ($25 staging /
   $100 prod) with email+pubsub before launch.
2. Cloud Monitoring metric filters on `SWEEPS_ALL` failures,
   `GEORADIUS_SCAN_CAPPED`, `REDIS_GEO_PROJECT_FAILED` rate,
   `N3_NEARBY` p95 — feed the Phase-6 acceptance suite.
3. Cost-per-unit rollup: add ~60-line daily aggregation to the
   coalesced sweep (packets/driver-hour, ops/ride) — defined in prior
   audit §8.12, not yet implemented.
4. Log-based metric on `LOCATION_UPDATE` count → alert if
   packets/driver-hour deviates >2× model (catches client regression).

## 7. Bottom line

The cost architecture is close to optimal for this stack: zero
always-on infra after cleanup, per-packet cost minimized to 1R+1W,
matching reads proven flat to 10k fleet. **Realized** savings still
require the prod rollout + Redis/connector deletion (~$60–95/mo) and
flag enablement (~50–70% of future usage cost). Remaining gaps are
small, bounded, and mostly P2/P3 — no architectural cost problem left.
