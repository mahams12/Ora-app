# Ora Production Architecture Optimization & Cost Reduction Plan

Status: READ-ONLY audit + plan. No code or infrastructure changed.
Basis: previous cost audit + live GCP inventory (2026-11-04) + source inspection.

Finding labels: **[VC]** verified in code · **[VCL]** verified in cloud ·
**[CALC]** calculated from verified inputs · **[ASM]** assumed · **[RT]** requires testing.

Pricing inputs (us-central1, list prices — confirm against console SKUs):
Firestore read $0.036/100k · write $0.108/100k · delete $0.012/100k ·
free/day 50k read / 20k write / 20k delete · storage $0.18/GiB-mo.
Cloud Run $0.000024/vCPU-s · $0.0000025/GiB-s · $0.40/1M req ·
free/mo 180k vCPU-s / 360k GiB-s / 2M req.
RTDB $1/GiB download · $5/GiB stored · free 10 GiB/mo download + 1 GiB + 100 conns (Spark limits; project is Blaze — see §5 note).
Memorystore BASIC M1 $0.049/hr ≈ $35.70/mo.
Routes Compute ~$5/10k calls. Places (New) Autocomplete ~$2.83/1k, Details ~$5/1k, ~10k free/SKU/mo (Mar 2025+ model). FCM $0. Scheduler $0.10/job-mo (3 free).

---

## PHASE 1 — Current Architecture Audit

### GPS & presence pipeline [VC]

- `DriverPresencePublisher` — `POST /v1/location/update` every **10 s** while
  online + signed-in + foregrounded (`kPresencePublishInterval`).
  Heartbeat republishes the last fix only if younger than 12 s
  (`kPresenceFixFreshness`); fixes worse than 50 m accuracy are skipped client-side.
- `DriverTripLocationPublisher` — min **4 s** interval during trips +
  10 s heartbeat (`kTripLocationMinInterval`, `kTripLocationHeartbeat`).
- Server per update: ~0.5 eligibility read (15 s per-instance
  `DriverEligibilityCache`) + **1 `locationStreams` write + 1 `geoDrivers` write**
  (+ 1 RTDB write in trip mode when RTDB configured).
- Freshness: marker stale after **15 s** (`N3_FRESHNESS_MAX_AGE_MS`) — tightly
  coupled to the 10 s client interval (only ~5 s of slack).
- Offline detection: client stops publishing → marker ages out → driver
  vanishes from matching in ≤15 s. Correct but aggressive.

### Matching & dispatch [VC]

- `NearbyDriversService.findNearby`: `geoDrivers` bounding-box query on
  composite `(lat,lastLocationTs)` / `(lng,lastLocationTs)` indexes with
  server-side freshness filter → exact haversine sort → batched
  `getAll` users/drivers + chunked busy-ride prefetch.
  ~3× geoHits doc reads per search.
- Dispatch waves: 10→15→25 km, 5 s cadence, ≤3 waves, ≤30 invites, 20 s
  invite TTL capped at ride expiry; 5-min search TTL.
- **Passengers never receive other drivers' locations.** Matching is fully
  server-side. [VC]

### Client polling & notifications [VC]

- Zero Firestore listeners in the app. Bounded HTTP polling:
  offers inbox 2→3→5 s (6-min cap), active ride 3→5→8 s (4-h cap),
  driver job similar. FCM = poll-now hint only (non-authoritative).
- Ride-state FCM outbox → `RIDE_UPDATE` data messages; dispatch FCM outbox →
  `RIDE_DISPATCH_INVITE` per driver per wave.
- RTDB listener `tripLocations/{rideId}` only during active trips, gated by
  ride state.

### Cloud & fixed cost [VCL]

- Services: `ora-auth-service` (prod, maxScale 10, concurrency 80, 1 vCPU/512 Mi,
  minScale 0) · `ora-auth-service-staging` (maxScale 2). Scale-to-zero OK.
- 14 Cloud Run Jobs + 13 Cloud Scheduler jobs. **7 staging sched ENABLED —
  5 × every-minute** ≈ ~7,600 exec/day ≈ $2.5/day.
- 2× orphaned Memorystore BASIC 1 GB (`ora-{staging,production}-n3-redis`)
  = ~$72/mo — **cleanup NOT done** (verified 2026-11-04).
- Prod service lacks `FIREBASE_DATABASE_URL` → `NullTripLocationRtdb` →
  **live passenger trip tracking inactive in production** (dead code path).
- Prod still carries dead `REDIS_URL` env var.
- Global rate limit **60 req/min per uid+IP** — headroom note for §2.

### Unnecessary costs identified

| Item | Cost | Note |
|---|---|---|
| Orphaned Redis ×2 | ~$72/mo | code never uses Memorystore |
| Staging every-minute sweeps | ~$75/mo | same sweeps exist paused on prod |
| 10 s fixed heartbeat | dominant usage cost | ~86% of projected usage spend |
| Duplicate `locationStreams`+`geoDrivers` writes | ~½ presence write bill | merged-doc write possible |
| Every-minute prod sweeps when enabled | ~$30/mo floor | no traffic-aware cadence |
| Dead prod trip-tracking path | correctness | needs env or removal |

---

## PHASE 2 — Adaptive GPS Heartbeat Design

### Design (reuses existing publisher classes)

Policy inputs (all local, no new infra): last-acked fix, fix age, fix accuracy,
speed/distance since last publish, driver state, app foreground state.

| Driver state | Publish rule | Server effect |
|---|---|---|
| Online, **stationary** (Δ < ~50 m since last publish) | every **30 s** | marker stays fresh |
| Online, **moving** (Δ ≥ 50 m, or speed > ~1.5 m/s) | every **10–12 s** | current behavior |
| Online + **pending invite** (wave invite delivered, countdown active) | every **8–10 s** | tightest freshness during matching |
| **Active trip** (moving) | **4 s** | unchanged live tracking |
| **Active trip** (stopped at stop >30 s) | **10 s** | unchanged-ish |
| Fix accuracy > 50 m | skip publish | unchanged (server rejects anyway) |
| App backgrounded | stop; last fix expires naturally → offline | unchanged semantics |
| Post-error retry | exponential backoff 2→4→8→30 s cap | unchanged pattern |

**Synchronization:** server freshness must rise from 15 s → **45 s**
(`N3_FRESHNESS_MAX_AGE_MS`) so the 30 s stationary interval keeps ~15 s slack.
Marker write and freshness check are the only coupled constants.

**Correctness guard:** a driver who stops moving mid-trip keeps publishing —
policy keys on *state*, not just movement: any active-trip driver never drops
below 10 s. Offline detection degrades from ≤15 s to ≤45 s for *idle* drivers —
acceptable (offline drivers disappear anyway; matching only cares about
freshness at invite time, which revalidates via `isStillEligibleForInvite`).

### Policy comparison

| Policy | Idle writes/driver-day (6 h online) | Freshness bound | Risk |
|---|---|---|---|
| 10 s fixed (current) | 4,320 | ≤15 s | baseline |
| 20 s adaptive (stationary 20 s / moving 10 s) | ~2,800 (−35%) | ≤25 s | low |
| **30 s adaptive (recommended)** | ~1,900 (−56%) | ≤45 s idle, ≤15 s matching/trip | low-med |
| 60 s stationary | ~1,100 (−75%) | ≤75 s | invite-time freshness slack too thin at 20 s invite TTL |

**Recommendation:** 30 s stationary / 10 s moving / 8 s pending-invite /
4 s trip, with `N3_FRESHNESS_MAX_AGE_MS` 15 s → **45 s** and a **10 s**
freshness floor enforced inside `isStillEligibleForInvite` (invite-time
revalidation already exists — reuse it so matching stays strict while idle
freshness relaxes). **[RT]** the pending-invite tight-cadence path.

### Edge cases handled

- **GPS jitter**: distance gate (>50 m) absorbs jitter; don't publish on noise.
- **Poor accuracy**: skip publish (already client + server enforced).
- **Network loss**: keep last-acked seq; retry with backoff; server `seq`
  ordering already enforced (`locationSeq` monotonic per stream).
- **Doze/background**: Android stops fixes → no republish → marker expires →
  offline. Same as today, just with a 45 s window instead of 15 s.
- **Rate limit**: 60 req/min/uid — worst case 4 s trip ≈ 15/min + ~10/min API
  chatter ≈ well under cap. **[CALC]**

---

## PHASE 3 — H3 / Geospatial Indexing Evaluation

### Options

| Option | Writes/update | Reads/search | Latency | Density behavior | Infra |
|---|---|---|---|---|---|
| **A. Current Firestore bbox** (lat/lng range + freshness) | 1 geoDrivers write | box docs (≈drivers-in-box; ≤5000 cap, ≤33 split queries) | ~100–300 ms | reads ∝ drivers in box — **linear in density** | none |
| **B. Firestore + H3** (h3 cell id per driver, query kRing) | 1 write (+cell field) | ~kRing cells × per-cell queries (≤~20 small queries) or `h3 IN` disjunction (≤30) | similar | reads ∝ **drivers in cells actually queried** — bounded, cleaner than bbox | none |
| **C. Firestore + geohash** (prefix query) | 1 write (+geohash) | 1–9 prefix range queries | similar | similar to B, simpler, coarser cells | none |
| **D. RTDB + geohash** | 1 RTDB write | prefix range read — download billed per byte | lower latency, but **Spark 100-conn limit** and download billing make it weak for server-side fan-in | — | none new |
| **E. Redis GEOSEARCH** | ~0 Firestore cost; Redis ops free-ish | O(log n) native | fastest | best at extreme density | **+$36/mo min always-on** (we just removed this) |

### Verdict

**Do NOT adopt H3 or Redis now.** Calculation: dominant cost is write
volume (presence), not search reads — geo search runs ≤3×/booking.
At 10k DAU, ~750 bookings/day × ~300 reads ≈ 225k reads/day ≈ **$0.08/day**.
Even a 10× search-read improvement saves < $3/mo — H3 adds code complexity
and a migration for near-zero gain. Bbox reads only become material at very
dense fleets (wave-3 25 km box in a dense metro → ~thousands of docs/search),
and even then cost ~$0.30/day at 750 bookings.

**When to revisit:** >~2,000 simultaneously-online drivers in one city
(box scans >500 fresh docs every search → geohash (C) is the cheapest
upgrade — single extra field, no new infra; H3 only if finer control needed).
Redis returns only if Firestore billed geo reads ever exceed ~$36/mo. **[CALC]**

---

## PHASE 4 — Database & Backend Optimizations

| # | Change | Effect | Effort |
|---|---|---|---|
| 4.1 | **Merge presence writes**: write only `geoDrivers` per update; move `locationStreams` accept to trip mode + coarse audit (every Nth idle update) | −50% presence write bill | S — `LocationUpdateService.update` idle path |
| 4.2 | Adaptive heartbeat (Phase 2) | −56% presence req+writes | S — client constants + 2 server constants |
| 4.3 | **Sweep coalescing**: run all 7 sweeps in ONE Cloud Run Job invocation/min (sequential calls inside one container) | ~7× fewer job executions: ~$30/mo floor → ~$5/mo | S — new job entrypoint script |
| 4.4 | Traffic-aware sweeps: skip dispatch/offer sweeps when 0 SEARCHING rides (cheap 1-doc probe before work) | up to −80% idle sweep cost | M — sweep guards |
| 4.5 | Prod `FIREBASE_DATABASE_URL` OR drop trip-tracking path | correctness (dead path) | XS — env var |
| 4.6 | Remove dead `REDIS_URL` env + secret | hygiene | XS |
| 4.7 | Estimate caching: pricing-rule doc is read per estimate — rules are static per city; cache 60 s in-process | −1 read/estimate | XS |
| 4.8 | Places: keep Nominatim primary; Google Places only if UX demands; debounce ≥3 chars already enforced **[RT]** | avoids ~$25–250/mo at scale | XS |
| 4.9 | Routes: `haversine` provider for compose-time estimates; Google Routes only for final price at booking confirm | −50–70% Routes calls | S — flag wiring per call-site |
| 4.10 | Client polling stays (bounded) — do NOT replace with Firestore listeners: listeners bill per-document-read fan-out and complicate auth; HTTP polling at current backoff is cheaper and already bounded | keeps current cost | none |
| 4.11 | Region: service + Firestore + RTDB all `us-central1`/asia-southeast1 — RTDB is in `asia-southeast1`; if prod users are PK-based, RTDB region is fine (near users); Cloud Run us-central1 adds ~150 ms latency — evaluate `asia-south1` deploy later | latency, not cost | M **[RT]** |

**Not recommended:** Firestore listeners to replace polling (fan-out read
billing + auth complexity); RTDB for geo index (conn cap + download billing);
Memorystore in any form.

---

## PHASE 5 — Cost Model

### Workload assumptions [ASM]

- Drivers = 15% of DAU; online 6 h/day (21,600 s); bookings = 25% of DAU/day.
- Ride distribution: 80% normal / 20% courier (courier ≈ +30% backend ops — minor).
- Presence: current 10 s fixed → 2,160 updates/driver-day → 4,320 writes.
  Adaptive (Phase A implemented): interval is state-dependent —
  `updates = 21600 × (statShare/30 + moveShare/10)` —
  stationary-heavy 70/30 → **1,152** · balanced 50/50 → **1,440** ·
  moving-heavy 30/70 → **1,728** (+ ~5% invite-boost).
  Expected case **1,440** (the earlier "1,350 vs 1,900" discrepancy was an
  unlabelled stationary-share assumption; range is now explicit).
- Booking ops ≈ 1,000 doc ops (incl. client polling).
- Cloud Run 120 ms avg request @1 vCPU/512 Mi.
- Sweep floor: current ~7,600 exec/day ≈ ~$30/mo; coalesced+guarded ≈ ~$5/mo.
- FCM $0. Networking/egress < $1/mo at these sizes.

### Formulas

```
presence_req/day  = drivers × 2160 (current) | drivers × 1440 (optimized, 50/50)
fs_writes/day     = presence_req × (2 current | 1 merged) + bookings × ~300
fs_reads/day      = presence_req × 0.5 + bookings × ~700
run_req/day       = presence_req + bookings × ~200 + sweeps
run_vcpus/mo      = run_req/day × 0.12 × 30
cost_run          = max(0, vcpus−180k)×2.4e-5 + max(0, gib−360k)×2.5e-6
                    + max(0, req_m−2M)/1e6 × 0.40
cost_fs           = max(0, reads−50k)/100k×0.036 + max(0, writes−20k)/100k×0.108
```

### Monthly totals

| Scale | A. Current (cleaned) | B. +Adaptive GPS | C. +Merged writes | E. Full optimized |
|---|---|---|---|---|
| 100 DAU | ~$35 (incl $30 sweep floor) | ~$20 | ~$15 | **~$8** |
| 1,000 DAU | ~$125 | ~$65 | ~$40 | **~$35** |
| 5,000 DAU | ~$520 | ~$270 | ~$170 | **~$150** |
| 10,000 DAU | ~$1,050 | ~$560 | ~$360 | **~$310** |

Range: ±40% [ASM sensitivity: driver share 10–20%, online 4–8 h].

### Simultaneous online drivers (presence-only, /mo)

| | 100 | 500 | 1,000 |
|---|---|---|---|
| Current 10 s | ~$15 | ~$70 | ~$140 |
| Optimized | ~$5 | ~$25 | **~$50** |

(6 h/day online assumption; 24/7 × 1,000 drivers ≈ $1,400/mo → ~$200/mo optimized.)

### Per-unit economics (optimized, 1k DAU)

| Metric | Value |
|---|---|
| Cost per driver-hour | ~$0.005 |
| Cost per booking attempt | ~$0.004 |
| Cost per completed ride | **<$0.01** |
| Fixed idle at 0 users | **~$0.50/mo** — recalc [CALC]: Secret Manager
  ~3 secrets × $0.06 + ~5 active versions × $0.06 ≈ $0.48; Cloud Scheduler
  jobs PAUSED → $0; Cloud Run Jobs uninvoked → $0; services minScale=0 → $0;
  Firestore/RTDB under free allotments → $0 |

### Reconciliation with previous ~$125/mo @1k DAU estimate

Previous estimate ≈ Firestore ~$25 + Cloud Run ~$40 + Routes ~$6 + Places ~$25
+ sweep floor ~$30 ≈ $126 — matches. **Billing reality check:** the actual
$13.74 bill was ~all fixed idle (Redis $3.69 + job executions ~$10) — zero
usage at 3–4 devices sits *inside* Cloud Run free tier. The model is
consistent: fixed ≠ usage. **[CALC]**

---

## PHASE 6 — Reliability & Scalability Validation Plan

Benchmarks to run (emulator load scripts exist: `run_geo_benchmark.ts`) —
**all results [RT], none measured yet**:

| Metric | Acceptance criterion |
|---|---|
| Marker freshness at invite | p95 lastLocationTs age < 20 s during active dispatch |
| `findNearby` p95 latency | < 500 ms @1,000 online drivers/city |
| Invite delivery latency (booking → driver FCM) | p95 < 10 s |
| Dispatch wave billed reads | ≤ ~300 doc reads/wave @500 drivers in box |
| Cloud Run p95 latency | < 300 ms; < 5 instances sustained |
| Offline detection | driver vanishes from matching ≤ 45 s after kill |
| Presence publish success | ≥ 99% accepted (no seq violations, no 429s) |
| Cost per driver-hour | ≤ $0.01 |
| Trip tracking p95 end-to-end lag | < 8 s |

Method: seed N drivers via `seed_device_test_accounts.ts` + geo benchmark
script; drive presence updates through the real endpoint; sample freshness
at wave time; measure billed reads via N3 diagnostics counters (already
instrumented: `N3NearbyDiagnostics`).

---

## PHASE 7 — Deliverables

### Files that would change

| File | Change (implemented, flag-gated) |
|---|---|
| `mobile/…/driver_presence_publisher.dart` | `PresencePublishPolicy` — adaptive cadence, keepalive, backoff, seq-reset, trip-pause |
| `mobile/…/driver_availability_view_model.dart` | `ORA_ADAPTIVE_PRESENCE` flag + invite/trip signal wiring |
| `mobile/…/driver_invites_view_model.dart` | `driverInviteActivityProvider` (poll-path invite signal) |
| `mobile/…/dispatch_fcm_service.dart` | FCM nudge → invite-activity signal |
| `mobile/…/driver_location_session.dart` | `driverTripLocationActiveProvider` (trip suppresses idle) |
| `backend/…/redis/types.ts` | `publishIntervalMs`/`presenceKeepalive`/`freshUntilMs`/`idleCursor`/`minFreshUntilMs` types |
| `backend/…/redis/geo_projection.ts` | adaptive freshUntil computation + idleCursor passthrough |
| `backend/…/redis/firestore_geo_client.ts` | freshUntil twin write, `minFreshUntilMs` geo query, merged-cursor tx, geodesic lng box fix |
| `backend/…/drivers/nearby_service.ts` | freshUntil-aware `isFresh` + query switch |
| `backend/…/location/location_update_service.ts` | merged idle path (flag `LOCATION_IDLE_MERGED_CURSOR`) |
| `backend/…/location/{types,validation,routes}.ts` | publishIntervalMs/presenceKeepalive fields |
| `backend/…/routes/internal.ts` | coalesced `/v1/internal/sweeps/all` + SEARCHING guard |
| `backend/…/pricing/pricing_rules_repository.ts` | TTL cache (`PRICING_RULES_CACHE_TTL_MS`) |
| `backend/…/{app,index}.ts`, `.env.example` | flag plumbing |
| `firestore.indexes.json` | freshUntilMs composite variants |
| `backend/…/scripts/spatial/geohash.ts` + `run_spatial_benchmark.ts` | spatial prototype (h3-js devDep) |
| `backend/…/__tests__/adaptive_presence.test.ts` + pricing repo tests | new coverage |
| Cloud Scheduler (console) | **unchanged** — awaiting approval |
| Cloud Run env (prod) | **unchanged** — `FIREBASE_DATABASE_URL` fix documented |

### Roadmap (ranked by savings/risk)

1. **[+immediately, zero risk]** Delete orphaned Redis ×2, pause 7 staging schedulers — **−$100/mo**.
2. **[low risk]** Adaptive heartbeat + freshness raise — **−50–60% usage cost**.
3. **[low risk]** Merged presence write — **−50% of remaining write bill**.
4. **[low risk]** Coalesced sweep job + traffic guards — **~$25/mo floor → ~$5**.
5. **[xs]** Prod `FIREBASE_DATABASE_URL` fix; dead `REDIS_URL` removal.
6. **[med]** Haversine-first routing; Places stays Nominatim-primary.
7. **[defer]** Geohash index only when >2k concurrent drivers/city.
8. **[defer]** RTDB connection scaling only when >50 concurrent tracked trips.

### Rollback plan

All changes are constant-level or additive: revert env/flags, redeploy prior
revision, re-enable schedulers. No data migrations; `geoDrivers` docs keep
both fields. Freshness constant rollback needs a client heartbeat rollback
too (keep both behind the same release).

### Final answer — lowest realistic cost

| Scale | Optimized monthly | Optimized daily |
|---|---|---|
| 100 DAU | **~$8** | ~$0.27 |
| 1,000 DAU | **~$35** | ~$1.15 |
| 5,000 DAU | **~$150** | ~$5 |
| 10,000 DAU | **~$310** | ~$10 |
| Idle (0 users) | **~$0.50** | ~$0.017 |

While keeping: server-side matching, ≤10–15 s invite latency, 4 s live trip
tracking, all Courier v2 flows, zero always-on infrastructure, zero Redis.

**Cheapest reliable architecture = current Firestore-only stack + adaptive
GPS heartbeat + merged presence write + coalesced guarded sweeps + prod
RTDB env fix. No H3, no Redis, no new infra.**

---

## IMPLEMENTATION STATUS — controlled local phase (branch `cost-optimization-local`)

Local-only implementation of Phases A–E. **Nothing deployed; all production
behavior unchanged — every feature is behind a flag that defaults OFF.**

### Flags (all default OFF = legacy behavior bit-identical)

| Flag | Surface | Effect when ON |
|---|---|---|
| `ORA_ADAPTIVE_PRESENCE` (dart-define) | mobile | adaptive presence policy |
| `LOCATION_ADAPTIVE_FRESHNESS` (env) | backend | per-driver `freshUntilMs` windows + `minFreshUntilMs` geo queries |
| `LOCATION_IDLE_MERGED_CURSOR` (env) | backend | idle cursor fields merged into `geoDrivers` tx (1 write/update) |

### Phase A — adaptive presence (mobile) — IMPLEMENTED + TESTED

`driver_presence_publisher.dart` now takes a `PresencePublishPolicy`:
- stationary 30 s · moving 10 s (>50 m displacement since last publish **or**
  speed ≥ 8 km/h) · invite-boost 8 s (45 s window) · max interval 30 s.
- GPS-stall keepalive: republishes last accurate fix re-dated to `now`
  (truthful for a stationary driver) so the marker can't expire while the
  driver is verifiably online; fails closed after `keepaliveMaxFixAge`.
- `publishIntervalMs` + `presenceKeepalive` sent to the backend; server
  computes `freshUntilMs = acceptedAt + min(publishIntervalMs×1.5, cap)`
  — the marker carries its own freshness deadline, so a 30 s advertiser
  stays matchable for ~45 s while invite-time checks stay strict.
- Invite-boost signals: FCM nudge **and** poll-discovered actionable
  invites (`driverInviteActivityProvider`) — FCM is never required.
- Idle publishes paused while the trip publisher owns the marker
  (`driverTripLocationActiveProvider`); trip path untouched.
- Exponential backoff (2→30 s) on rate-limit/network; `SEQUENCE_VIOLATION`
  resets the idle stream instead of failing every publish.

### Phase B — merged idle cursor (backend) — IMPLEMENTED + TESTED

`locationStreams` is the durable sequence validator (stream identity,
monotonic seq, replacement-stream history, closed rejection) — it cannot
be dropped. Instead, with `LOCATION_IDLE_MERGED_CURSOR` the idle cursor
(`lsActiveStreamId/lsLastAcceptedSeq/lsPreviousStreamIds/lsStreamState/
lsUpdatedAt/lsExpiresAt`) is validated **inside the existing `geoDrivers`
transaction** — one write per accepted idle update instead of two. Trip
streams (`{rideId}_{driverId}`) keep the original `locationStreams` doc —
trip path unchanged. Real-Firestore write conflict → `CURSOR_CONFLICT`
retries (≤2) then 429. Clients without `supportsIdleCursor` (RTDB geo)
fail closed to the legacy two-write path.

### Phase C — matching correctness — PRESERVED + TESTED

- `isStillEligibleForInvite` now honours `freshUntilMs` (adaptive) with
  the legacy `lastLocationTs + N3_FRESHNESS_MAX_AGE_MS` fallback — a stale
  driver still can't be invited.
- `minFreshUntilMs` query selects markers whose advertised window covers
  `now`; when the flag is off the query and freshness logic are unchanged.
- Radius expansion 10/15/25 km, nearest-first, busy/offline filters,
  offer TTL — untouched. Stale-marker tests all still pass.

### Phase D — coalesced sweeps (backend) — IMPLEMENTED + TESTED

`POST /v1/internal/sweeps/all?guards=false` runs every sweep in ONE
invocation: results keyed per sweep, one sweep's exception is captured
into `results.<name>.error` and does not stop the rest (no single point
of failure). `searchingActive` probe (any `SEARCHING` rides) guards the
dispatch sweep — skipped when nothing is searching. Existing per-sweep
endpoints are untouched; **cloud schedulers not changed** — coalescing is
a deploy-time choice of which URL each job calls.

### Phase E — prod tracking fix — DOCUMENTED, not applied

Prod `ora-auth-service` lacks `FIREBASE_DATABASE_URL` →
`NullTripLocationRtdb` → live passenger tracking silently inactive.
Safe fix (requires approval):
```
gcloud run services update ora-auth-service \
  --region us-central1 \
  --update-env-vars FIREBASE_DATABASE_URL=https://ora-app-d8112-default-rtdb.asia-southeast1.firebasedatabase.app
```
The RTDB instance already exists in `asia-southeast1` (staging uses it).
No code change needed — `index.ts` already wires `TripLocationRtdb`
when the env is present.

### Verification results (local, emulators where applicable)

- Backend: `tsc --noEmit` clean · vitest **686 tests** (1 flaky
  pre-existing 50-way concurrency timing test; passes standalone).
  New `adaptive_presence.test.ts`: 12/12 — adaptive freshness,
  merged-cursor seq/replay/replacement, coalesced sweep guards+isolation.
- Mobile: `flutter analyze` clean · **177 driver+notifications tests**.
  7 new adaptive publisher cases (cadence, keepalive, invite boost,
  seq-reset, trip pause, backoff, flag-off no-op). Also fixed a
  pre-existing `pumpAndSettle` hang in `slice_m_driver_test` caused by
  the offer sheet's `RideMapPreview` fetching map style in tests
  (provider override, unrelated to this work).
- One real bug found & fixed by the new tests: `_publish` was writing
  `_lastPublishedFix` before computing `publishIntervalMs`, so moving
  drivers advertised the 30 s interval → server would grant a 45 s
  window while the client published every 10 s. Ordering corrected.
- Replay protection verified end-to-end: replayed `locationSeq` → 422
  `SEQUENCE_VIOLATION`; replacement stream rotates `lsPreviousStreamIds`;
  closed stream rejected; trip streams unaffected.

### Revised optimized costs (unchanged conclusions)

Expected-case 1,440 presence updates/driver-day (50/50 stat/move), one
Firestore write each: at 1,000 DAU ≈ 216k req + 216k writes/day ≈ 38%
fewer requests and 69% fewer writes vs current. Monthly totals and the
final-answer table stand; idle floor corrected $0.10 → **$0.50/mo**.

### Rollback

All OFF by default — rollback = redeploy without the flags. Per-change:
`git revert` the branch; no data migrations (`geoDrivers` keeps `ls*`
fields harmlessly; freshUntilMs markers remain valid). If enabled then
rolled back server-side while clients still advertise 30 s intervals,
markers keep extended `freshUntilMs` until TTL — matches today's
30 s TTL semantics, so no stale-invite regression either direction.

---

## PHASE 8 — Extended Strategy Evaluation (Uber/Careem/inDrive principles)

Classification: **[IMPL]** implemented & tested locally · **[PROTO]** prototype
only, pending benchmarks · **[EVAL]** evaluated, decision below · **[DEFER]**
not justified at current scale · **[REJ]** rejected.

### 8.1 Adaptive GPS with movement-based uploads — [IMPL] ✅

**Current:** fixed 10 s idle heartbeat; 4 s min/10 s heartbeat in trips.
**Change:** `PresencePublishPolicy` — stationary 30 s · moving 10 s
(>50 m displacement or ≥8 km/h) · invite-boost 8 s (45 s window from
FCM nudge OR poll-discovered invite) · GPS-stall keepalive re-dating the
last accurate fix · per-packet `publishIntervalMs` → server `freshUntilMs`.
**Storage:** unchanged (`geoDrivers` merged marker).
**Cost:** 2,160 → ~1,440 updates/driver-day (−33%) + halved writes (8.2)
→ ~69% fewer presence writes.
**Risk:** keepalive masks GPS-hardware stalls ≤ `keepaliveMaxFixAge`;
bounded by invite-time freshness revalidation. Mitigated, tested.
**Verdict:** implemented, flag `ORA_ADAPTIVE_PRESENCE` (default OFF).

### 8.2 Single-write live location storage — [IMPL] ✅

**Current:** `locationStreams` tx (cursor/seq validation) + `geoDrivers`
marker write = 2 billed writes per accepted packet.
**Change:** `LOCATION_IDLE_MERGED_CURSOR` — cursor fields
(`lsActiveStreamId/lsLastAcceptedSeq/lsPreviousStreamIds/…`) validated
inside the existing `geoDrivers` transaction. Trip-mode streams keep the
dedicated `locationStreams` doc — trip path untouched.
**Why not delete `locationStreams`:** it is the durable sequence validator
(stream identity, monotonic seq, replacement history, closed-stream
rejection) — not audit history. Deleting it breaks replay protection.
**Cost:** −50% presence write volume. **Risk:** lose per-packet idle
cursor audit trail (accepted trade). **Verdict:** implemented, flag OFF.

### 8.3 Independent presence vs location freshness + RTDB onDisconnect — [EVAL]

**Current:** one merged marker serves both "is online" (TTL 30 s) and
"is location fresh" (freshUntilMs). Going offline cleanly deletes the
marker; an ungraceful kill is detected when the marker expires (~45 s).
**onDisconnect analysis:** an RTDB presence node cleared server-side on
socket close gives ~instant offline detection. **But** it requires a
persistent RTDB connection per online driver — Spark caps ~100 concurrent
connections → fails at >~100 drivers (Blaze required: $5/GB + conn costs,
and adds a second client SDK + reconnect storms on tunnel-mode networks).
**Verdict:** [REJ at current scale] — TTL-window detection (~45 s) is
already within N4 invite latency; revisit only if offline-detection
latency < 30 s becomes a product requirement AND RTDB moves to Blaze.
The freshness/presence *split* is still worth keeping in the data model:
`freshUntilMs` (Phase A) is exactly that — presence lifetime (TTL) and
location freshness are already independent fields.

### 8.4 Event-driven dispatch (FCM nudge) + reliable fallback — [EVAL → already implemented]

**Current:** dispatch writes invite docs; FCM `DISPATCH_INVITE` nudge
triggers the driver's invite-list refresh; bounded backoff polling
(2→3→5 s, 6-min cap) covers missed pushes; invite list is authoritative —
FCM is never required for correctness.
**Assessment:** this IS the Uber-style pattern (push as latency
optimization, poll as reliability floor). Alternatives evaluated:
- *Firestore listeners for invites:* real-time but +1 billed read per
  snapshot delivery × poll-equivalent traffic — comparable cost, higher
  SDK complexity. No net win.
- *RTDB invite channel:* same connection-limit problem as 8.3.
**Verdict:** keep current design; the only gap closed this phase was
surfacing poll-discovered invites as a presence-boost signal (8.1).

### 8.5 Spatial partitioning: bbox vs geohash vs H3 — [PROTO → benchmarked → REJ ≤5k fleet]

**Prototype:** `scripts/run_spatial_benchmark.ts` — models exact Firestore
query semantics (billed reads = docs returned by queried ranges/cells),
uniform + clustered (60% in 3 km core) driver layouts, fleets
100–5,000, radii 5/10/25 km, 40 query samples per cell.
Results: `docs/audits/SPATIAL_BENCH.csv`.

**Key measured results (clustered, 10 km dispatch radius):**

| Fleet | bbox reads (1 query) | geohash-p5 | geohash-p6 | h3-r8 | h3-r9 |
|---|---|---|---|---|---|
| 1,000 | 789 | 832 (25 q) | 762 (547 q) | 780 (16 q) | 756 (99 q) |
| 5,000 | 4,013 | 4,228 (26 q) | 3,902 (547 q) | 3,992 (16 q) | 3,889 (99 q) |

- Best case (h3-r9): **~4–15% fewer billed reads** — at the cost of
  16–99× query fan-out (IN-chunks of 30), +1 indexed field per marker,
  and a write-path migration.
- At 25 km (max expansion) every scheme reads the whole local fleet —
  partitioning gains nothing.
- geohash-p6 read savings are real but require per-cell range queries
  (fan-out 150–3,200) — latency-dominated, unusable.
- **Bug found while benchmarking:** the production bounding box computed
  lng-delta with `cos(centerLat)` — under-covers the circle's pole-ward
  arc (benchmark showed 1–4 edge misses / 40 queries at 5k fleet).
  FIXED: geodesic bound `asin(sin(δ)/cos(lat_edge))` + 1e-4° epsilon —
  benchmark now shows **0 misses in 8,400 queries**.

**Verdict:** [REJ at current scale] — geo reads ≈ ~$40–60/mo at 10k DAU;
a ~10% cut (~$5/mo) does not pay for fan-out latency + migration risk.
Revisit trigger: >2,000 concurrent drivers in one city AND dispatch-read
cost > $50/mo, at which point h3-r8 dual-write (additive field, bbox
fallback) is the migration path.

### 8.6 Smart caching — [IMPL (eligibility exists; pricing rules added)]

**Current:** `DriverEligibilityCache` (15 s per-instance TTL) already folds
`users`+`drivers` reads on the hot path.
**Added:** `PRICING_RULES_CACHE_TTL_MS` — in-process TTL cache inside
`PricingRulesRepository` (default 0 = off; rules are admin-seeded, and the
estimate snapshot already freezes the rule per booking). Saves 1 billed
read per estimate/create-adjacent call; ~1 read → ~0.02 at 60 s TTL under
estimation traffic. Tested: cache hit, TTL expiry, no negative caching.
**Cost:** −1 read/estimate ≈ trivial $ but removes a serial ~5–15 ms read.
**Verdict:** implemented, env `PRICING_RULES_CACHE_TTL_MS=60000` suggested.

### 8.7 Batched processing / consolidated sweeps — [IMPL] ✅

Coalesced `/v1/internal/sweeps/all` (per-sweep error isolation, SEARCHING
probe guard for the dispatch sweep). Per-sweep endpoints retained —
schedulers choose which URL to call at deploy time. ~$25–30/mo → ~$5/mo
idle floor.

### 8.8 Selective computation — [EVAL → mostly implemented]

| Avoided work | Status |
|---|---|
| Stale markers scanned in geo query | `minFreshUntilMs` query filter (flag) — server drops stale docs inside the index scan |
| Eligibility read per GPS packet | `DriverEligibilityCache` 15 s TTL ✅ already live |
| Busy-driver check per candidate | chunked `IN ≤5` rides prefetch ✅ already live |
| Route API per estimate | `ORA_ROUTING_PROVIDER=haversine` flag exists; Google only at confirm |
| Idle publish during active trip | presence publisher pauses on `driverTripLocationActiveProvider` ✅ |
| GPS publish while stationary | 30 s + keepalive ✅ 8.1 |

### 8.9 Routes/Places API optimization — [EVAL]

**Current:** `RoutingProvider` abstraction; Google Routes when key
present, haversine fallback flag; Nominatim for geocoding.
**Recommendations:** keep Nominatim-first for autocomplete (free,
self-hostable later); Google Routes ONLY at booking confirm (estimates on
haversine where tolerance allows); add a per-(origin-cell,dest-cell,
category) route cache (TTL ~6 h, keyed by ~500 m geohash-p5 cells) —
typical repeat-ride share can cut Routes calls 30–50% in mature markets.
Flag candidate, ~80 lines, no schema change.

### 8.10 Cloud Run tuning — [EVAL]

**Current [VCL]:** containerConcurrency=80, 1 vCPU/512 Mi, minScale=0,
maxScale=10 (prod) / 2 (staging). At ~120 ms/request, one instance
serves ~660 rps equivalent headroom — more than enough to ~10k DAU.
**Recommendations:** keep concurrency 80 (Firestore client is async);
CPU boost "only during startup" is already default on gen2; no dedicated
CPU allocation needed (no CPU-bound work between requests); region
us-central1 vs Firestore us-central1 — co-located ✅. Only knob left:
maxScale raise is a deploy decision under measured load, not a cost fix.

### 8.11 Indexing, read amplification, duplicate writes — [IMPL] ✅

- `freshUntilMs` composite indexes added (`firestore.indexes.json`) —
  deploy before enabling the flag.
- Pole-edge lng box fix (8.5) — rare candidate misses eliminated.
- Merged cursor halves writes (8.2); `geoDrivers` merged marker already
  avoids the old geo+marker double read on the match path.
- `locationStreams` NOT removed — required for seq protection (8.2).

### 8.12 Cost-per-driver-hour / per-ride monitoring — [EVAL → plan]

Existing structured logs already carry the raw data:
`REDIS_GEO_PROJECTED` (per-packet), `N3NearbyDiagnostics` (per-search
read breakdown), `DriverEligibilityCache.stats()`,
`PricingRulesRepository.cacheStats()` (new), sweep result JSON.
Plan: Cloud Logging metric `ora_presence_packets` + a daily
`internal/metrics` rollup sweep aggregating packets/driver-hour and
ops/ride — ~60 lines, added to the coalesced sweep as a no-cost job.
Until then, cost/driver-hour is derivable from benchmark op counts:
**~240 updates/h × (1R+1W) ≈ $0.005/driver-hour** (model, not billed).

### Revised optimization status table

| Optimization | Status | Savings |
|---|---|---|
| Adaptive GPS heartbeat | [IMPL] flag OFF | −33% presence req |
| Merged cursor write | [IMPL] flag OFF | −50% presence writes |
| Adaptive freshness window | [IMPL] flag OFF | enables the above |
| Coalesced sweeps | [IMPL] endpoint ready | ~$25/mo fixed |
| Pricing-rules cache | [IMPL] env-gated | −1 read/estimate |
| lng box geodesic fix | [IMPL] always-on | correctness, ~0 cost |
| H3/geohash indexing | [PROTO] benchmarked | REJ ≤5k fleet (~10% reads, 16–99× fan-out) |
| RTDB presence/onDisconnect | [REJ] | Spark 100-conn cap |
| Route-result cache | [EVAL] candidate | 30–50% Routes calls later |
| Firestore invite listeners | [REJ] | no win vs poll+FCM |

### Updated roadmap

1. Deploy `firestore.indexes.json` (freshUntilMs variants) — prerequisite.
2. Staging: enable `LOCATION_ADAPTIVE_FRESHNESS` + `LOCATION_IDLE_MERGED_CURSOR`
   + `PRICING_RULES_CACHE_TTL_MS=60000`; mobile `ORA_ADAPTIVE_PRESENCE=true` build.
3. Run Phase 6 benchmarks on staging (acceptance criteria above).
4. Prod flags on after staging soak; apply `FIREBASE_DATABASE_URL` fix.
5. Execute previously-approved cleanup: delete 2 orphaned Redis, pause 7
   staging schedulers (−~$100/mo), replace prod schedulers with coalesced.
6. Defer: spatial migration (benchmark trigger defined), route cache
   (when Routes spend > $20/mo), RTDB presence (never on Spark).

### Test results added this phase

- Spatial benchmark: 210 rows, **0 misses** post-fix; results in
  `docs/audits/SPATIAL_BENCH.csv`.
- `pricing_rules_repository.test.ts`: +4 cache cases (17/17 pass).
- Full backend suite: 690 tests (1 known memory-DB concurrency flake,
  passes standalone 89/89).
- New bug found & fixed: pole-edge lng under-coverage in
  `firestore_geo_client.georadius` (8.5) — correctness fix, always on.

---

## PRE-STAGING AUDIT RESULTS (branch `cost-optimization-local`, local-only)

All results below are from Firebase Emulator Suite + Vitest + measured
emulator benchmarks. **No staging/production inference** — emulator numbers
prove semantics and relative op counts, not production latency.

### A. Confirmed issues found & fixed during audit

| # | Issue | Fix | Proof |
|---|---|---|---|
| A1 | **Phantom-driver keepalive** — keepalive re-dated old fix to `now`; marker claimed stale position as fresh GPS, `freshUntilMs` extended from it (5-min bound) | Client sends ORIGINAL fix ts (no `withTimestamp`); `keepaliveMaxFixAge` 5 min→90 s; server derives presence from `acceptedAt`; `isFresh` caps real fix age at `N3_MAX_FIX_AGE_MS=120 s` for BOTH geo matching and invite revalidation | `adaptive_presence.test.ts` +5 keepalive cases; `driver_presence_publisher_test.dart` asserts original ts preserved + 90 s bound |
| A2 | **Silent sweep success** — `/sweeps/all` always returned 200; a permanently-failing sweep would show 100% green scheduler executions | Now returns **503** when `failures` non-empty (same diagnostic body). Idempotent sweeps → scheduler retry safe; failures now observable in job metrics | `step failure → 503` test (18/18 file) |
| A3 | Validation bound for keepalives — old 15 s cap would reject honest keepalives | Flagged keepalives accepted ≤130 s (cap+margin); unflagged timestamps keep strict 15 s | `keepalive with bounded-age fix accepted` test |

Layered staleness model after fix: client stops keepaliving at 90 s fix age →
server accepts flagged ≤130 s → matching eligibility caps at 120 s → marker
presence expires ≤ interval+grace (≤75 s) after last accepted packet.
A GPS-stalled driver stays *present* (honest) but stops being *invitable* once
the fix ages past 120 s; presence expires on its own without FCM.

### B. Merged Firestore cursor — REAL emulator transaction proof

`scripts/run_merged_cursor_emulator_proof.ts` — **28/28 PASS** on the real
Firestore emulator (java instance, port 8181):

- Sequential advance, replay/duplicate → 422 (cursor unchanged)
- 20-way concurrent packets: exactly 2 commits, 18 ordered 422s, final
  `lsLastAcceptedSeq=20` — Firestore tx retry ordering verified
- Stream replacement: new streamId resets seq, `lsPreviousStreamIds`
  populated, late old-stream packet → 422
- Old-client compatibility: no-`idleCursor` writes leave ls* absent; merge
  preserves ls* when legacy clients overwrite cursor docs and vice-versa
- Atomicity: seq-violation tx leaves coords/marker/cursor untouched
- Online→offline→online: doc delete clears cursor; re-online restarts
  cleanly (cursor durability bounded by geo-doc lifetime — same streamId
  reuse after offline is accepted, equivalent to legacy semantics since
  clients rotate streamId per session)
- External conflict mid-tx: both updates preserved
- `freshUntilMs` twin: real range query excludes expired presence
- Read accounting: tx body = **exactly 1 `tx.get` + 1 `tx.set`** → 1R+1W per
  accepted packet (was 2R+2W across two transactions). No ls* composite
  indexes exist; single-field index maintenance is inside the write cost —
  **zero additional billed reads/queries**.

### C. Coalesced sweep audit

- Coverage: all 8 periodic jobs coalesced (dispatch, expire, offerExpire,
  noShow, dispatchFcm, rideStateFcm, geoPresence, expiresAtCleanup). No
  separate settlement/cancellation sweep exists — settlement is synchronous
  at completion; courier rides flow through the same `rides` state machine.
- Per-sweep failure isolation: verified (one throwing step → others run).
- **Partial failure → 503** (fix A2) — cannot silently report success.
- Idempotency: all sweeps are state-checked + batch-limited
  (`DEFAULT_SWEEP_BATCH`, ≤20 passes for noShow) — retry and overlapping
  ticks repeat bounded work only.
- Timeout: each sweep internally bounded; coalesced total fits the 60 s
  tick at tested volumes; at backlog, passes cap and next tick continues.
- Monitoring contract: alert on non-2xx scheduler executions and
  `SWEEPS_ALL` logs with non-empty `failures`.
- Guard: `?guards=false` and SEARCHING-probe fail-open verified.

### D. RTDB validation (prepared, NOT applied)

- Backend path verified: `FIREBASE_DATABASE_URL` → Admin `databaseURL` →
  `AdminTripLocationRtdb`; unset → `NullTripLocationRtdb` **silently no-ops**
  trip-location writes → passengers lose live tracking (the reported prod gap).
- Correct prod value (matches `.env` / instance):
  `https://ora-app-d8112-default-rtdb.asia-southeast1.firebasedatabase.app`
  — RTDB region asia-southeast1 (near PK users; fine).
- Rules: `database.rules.json` — `tripLocations/{rideId}` read gated by
  `rideAccess/{rideId}/{uid}`; writes server-only; `geoPresence`/
  `locationStreams` deny-all client access. Correct for prod.
- Prepared change (NOT run):
  `gcloud run services update ora-auth-service --region=us-central1
   --update-env-vars FIREBASE_DATABASE_URL=https://ora-app-d8112-default-rtdb.asia-southeast1.firebasedatabase.app`
  (or add to `.env` for `deploy_production_cloud_run.sh`, which already
  forwards it when present). Admin SDK uses the service's runtime SA —
  needs `roles/firebasedatabase.admin` or default editor on the project
  (verify before applying).

### E. Cost recalculation — current SKUs (verified 2025 price cards)

| SKU | Price used | Source |
|---|---|---|
| Firestore reads | $0.03/100k ($0.30/M) | cloud.google.com/firestore/pricing — **halved** vs old $0.06 |
| Firestore writes | $0.09/100k ($0.90/M) | same — **halved** vs $0.18 |
| Cloud Run CPU (request-based) | $0.000024/vCPU-s | run/pricing |
| Cloud Run memory | $0.0000025/GiB-s | run/pricing |
| Cloud Run requests | $0.40/M (2M free/mo) | run/pricing |
| Cloud Scheduler | $0.10/job-mo (3 free) | scheduler/pricing |
| Secret Manager | $0.06/version-mo + $0.03/10k access | secretmanager/pricing |
| RTDB Blaze | $1/GiB download · $5/GiB stored | firebase pricing [ASM — region card] |
| Compute Routes | ~$5/1k | routes SKU [ASM] |
| Egress | < $1/mo at modelled sizes | inside 10 GiB free |

Measured per-packet ops (emulator): update = ~2.07R+2W merged-flag-OFF;
**1R+1W merged-ON** steady-state (eligibility cache absorbs user/driver reads).

**Firestore location storage vs managed Redis GEOSEARCH (realistic):**
Memorystore Basic M1 (1 GiB) ≈ $0.049/h ≈ **$36/mo always-on** + mandatory
Serverless VPC Access connector ≈ $0.032/h ≈ **$23/mo** + network/proxy
overhead ≈ **$59+/mo floor before a single op**, plus a second failure
domain. Firestore geo total at 1k DAU ≈ $8–15/mo all-in. Redis GEO loses
~5–7× at this scale; revisit only if geo writes exceed ~$30/mo (>15k DAU).

**Recalculated monthly totals** (Firestore halving lowers both columns;
assumptions unchanged: 15% drivers, 6 h online, 25% DAU bookings, 50/50
stationary split, `0.03/0.09` rates, sweep floor $5 coalesced):

| Scale | Current path (10 s, 2W) | Optimized (adaptive+merged+coalesced) |
|---|---|---|
| 100 DAU | ~$30 (sweep-floor dominated) | **~$6** |
| 1,000 DAU | ~$95 | **~$28** |
| 5,000 DAU | ~$420 | **~$120** |
| 10,000 DAU | ~$860 | **~$255** |

[CALC] label applies — formula outputs, not bills. ±40% sensitivity on
driver-share/hours assumptions. Cheaper Firestore narrows the savings
percentage but doesn't change the ordering or the architecture verdicts.

### F. Measured benchmarks (emulator, `run_geo_benchmark.ts`)

| Metric | 100 | 500 | 1,000 | 2,000 |
|---|---|---|---|---|
| findNearby p50 ms | 37 | 51 | 42 | 43 |
| geo hits / query | 23 | 54 | 54 | 54 |
| Firestore RPCs / query | 7 | 13 | 13 | 13 |
| candidates returned | 21 | 52 | 52 | 52 |

- findNearby latency **flat vs fleet size** (limit-bounded, radius-capped).
- `projectLocation` tx: p50 4.4 ms / p95 6.7 ms; full packet p50 10 ms.
- Nearest-first: georadius sorts haversine-asc — guaranteed in code.
- Matching accuracy: 0 spatial misses post geodesic fix (8,400-query proof).
- Offline detection: marker expires ≤ interval+grace (≤75 s) after last
  packet — verified by freshUntilMs range-filter test; force-kill covered
  by the same expiry (no client cleanup needed).
- Invite eligibility of stale-fix keepalive: blocked by 120 s fix-age cap.
- GPS updates/driver-hour: 360 fixed → **~240 adaptive** (code-verified
  cadences: 30 s stationary / 10 s moving / 8 s invite-boost).
- Firestore ops/driver-hour: 360R+720W → **~240R+240W merged** (measured).
- Sweep execution/failure: 18/18 adaptive_presence tests + emulator proof.

### G. Staging rollout plan (execute only after GO)

1. `firebase deploy --only firestore:indexes --project <staging>` —
   `freshUntilMs` index variants must exist BEFORE enabling the flag, else
   georadius range filters fail.
2. Backend staging deploy with env:
   `LOCATION_ADAPTIVE_FRESHNESS=true LOCATION_IDLE_MERGED_CURSOR=true
   PRICING_RULES_CACHE_TTL_MS=60000 FIREBASE_DATABASE_URL=<staging-rtdb-url>
   ORA_INTERNAL_WORKER_TOKEN=<set>`
   Roll out flags in order: adaptive freshness first, verify matching,
   then merged cursor (each independently revertable).
3. Mobile build with `ORA_ADAPTIVE_PRESENCE=true` → internal test APK.
4. Point one staging Cloud Scheduler job at `POST /v1/internal/sweeps/all`
   with `X-Ora-Worker-Token`; keep the 7 individual jobs running in
   parallel during soak (double-execution is idempotent), then disable
   them after acceptance.
5. Compatibility matrix: flags OFF = legacy behaviour bit-identical;
   old APK + new backend = works (no new fields sent); new APK + old
   backend = works (unknown fields ignored, keepalive flag off unless
   adaptive build). No data migration; ls*/freshUntilMs fields are
   additive and harmless if rolled back.
6. Smoke tests: go online stationary→publish 30 s; move→10 s; send invite
   →8 s boost; kill app→driver drops ≤75 s; stale-ts keepalive packet →
   marker keeps honest ts; replay seq → 422; force a sweep failure → 503.
7. Acceptance: match p50 < 300 ms staging; zero phantom invites on
   stalled-GPS driver; sweep job shows failed execution on injected fault;
   RTDB trip path visible in passenger UI.
8. Rollback: unset env vars + redeploy (no data migration). Indexes can
   stay (idle). Mobile rollback = flag off.
9. Staging test cost: ~$0 (inside free tiers at test volumes); budget
   control — set billing budget alert $20/mo on the staging project.

### GO/NO-GO recommendation → **GO (conditional)**

GO for staging, conditional on the rollout order above (indexes first,
flags one-at-a-time, sweeps run in parallel with existing jobs during
soak). NO-GO for production until: (a) 24–48 h staging soak with the
acceptance criteria green, (b) `FIREBASE_DATABASE_URL` applied and RTDB
trip tracking verified end-to-end on a real device, (c) real-APK drive
test confirming cadences under actual GPS/network conditions — emulator
results cannot prove device behaviour.

Evidence basis: 28/28 emulator tx proofs, 18/18 adaptive backend tests,
17/17 publisher tests, 694/696 full backend suite (2 known parallel-run
memory-DB flakes — pass standalone 89/89 + 18/18), flat findNearby latency
to 2,000-driver fleets, 3 real bugs found & fixed (phantom keepalive,
silent sweep success, merged-set ordering from earlier phase).

---

## CLOUD INVENTORY (read-only, 2026-11-04) — idle charges verified

| Resource | State | Monthly cost [CALC] | Dependency status |
|---|---|---|---|
| `ora-production-n3-redis` (BASIC 1GB) | READY | ~$36 | Prod service still has `REDIS_URL` secret + VPC connector annotation — **cannot delete until service unwired** |
| `ora-staging-n3-redis` (BASIC 1GB) | READY | ~$36 | Staging service has NO Redis ref → safe to delete |
| `ora-staging-vpc` connector (2×e2-micro) | READY, attached to **prod** | ~$23 | Attached to `ora-auth-service` (prod) — mislabeled; remove annotation first, then delete |
| 6 prod scheduler jobs | PAUSED | $0 exec | Paused; keep or delete — no charge either way |
| 7 staging scheduler jobs | ENABLED, firing every 1–15 min | ~$8–10 exec | Needed until coalesced sweep soak completes |
| 13 prod+staging worker Cloud Run Jobs | idle-capable | $0 uninvoked | Required by schedulers; keep |
| `ora-n3-staging-benchmark`, `ora-n3-staging-seed` jobs | last run Sep 30 | $0 | Orphaned — hygiene delete |
| `ora-auth-service` (prod) | maxScale 10 | usage-based | Missing `FIREBASE_DATABASE_URL` (RTDB gap); still Redis-wired |
| `ora-auth-service-staging` | maxScale 2–3 | ~$0 | Has `FIREBASE_DATABASE_URL` + worker token; Firestore geo |

**Notable findings:**
1. Production ride-state-FCM has **no worker job and no scheduler** (staging has both) — when prod sweeps resume they should go through `/sweeps/all` which covers it.
2. `ora-staging-vpc` name is misleading — it is the connector attached to the PROD service revision.
3. Prod schedulers paused + last worker run Oct 21 → prod sweep work is currently OFF entirely (fine while idle; must be re-enabled — preferably via the coalesced endpoint — before real traffic).

**Safe cleanup order (each step needs explicit approval):**
1. Redeploy/update `ora-auth-service` WITHOUT `REDIS_URL` and WITHOUT `--vpc-connector` (behavior change: geo already Firestore-path by default — `GEO_BACKEND` unset defaults to firestore; verify before removing).
2. Delete `ora-production-n3-redis`, `ora-staging-n3-redis` (−~$72/mo).
3. Delete `ora-staging-vpc` connector (−~$23/mo).
4. After coalesced-sweep staging soak: point 1 staging scheduler at `/sweeps/all`, pause the 7 per-sweep staging schedulers (−~$8–10/mo exec).
5. Hygiene (any time): delete 2 orphan N3 jobs, review Artifact Registry image retention.

## REMAINING STRATEGIES ROADMAP (status board)

| Strategy | Status | Evidence / trigger |
|---|---|---|
| Adaptive GPS + heartbeat | DONE (flag off) | 18/18 tests; phantom-keepalive fixed in audit |
| Single-write presence (merged cursor) | DONE (flag off) | 28/28 emulator tx proofs |
| Independent presence/location freshness | DONE | `freshUntilMs` + `N3_MAX_FIX_AGE_MS` layered model |
| Coalesced sweeps | DONE (endpoint + 503 semantics) | failure-isolation test |
| Smart caching: pricing rules | DONE (env-gated TTL) | 17/17 tests |
| Smart caching: city/app config | NOT NEEDED | catalog is import tooling, not a hot path |
| Selective computation | DONE where profitable | server-side freshness filter, chunked busy-prefetch, haversine-first routing, trip-suppressed idle, SEARCHING probe |
| Event-driven dispatch | ALREADY OPTIMAL | FCM = latency hint, poll = reliability floor; Firestore listeners REJ (no win) |
| Polling optimization | DONE (bounded) | invite-boost cadence; further backoff gains marginal |
| Google Routes/Places | PARTIAL | Nominatim-first + haversine fallback; route-result geohash cache DEFER until Routes spend > $20/mo |
| H3/geohash partitioning | REJECTED ≤5k fleet | SPATIAL_BENCH.csv: ≤15% reads saved, 16–99× fan-out; trigger >2k drivers/city AND >$50/mo geo reads |
| RTDB onDisconnect presence | REJECTED | Spark 100-conn cap; Blaze conn billing; TTL expiry already < invite latency |
| Redis GEOSEARCH | REJECTED at scale | $59+/mo floor vs Firestore ~$8–15/mo @1k DAU; revisit >$30/mo geo writes |
| Cost-per-unit monitoring | DEFINED | metric rollup inside coalesced sweep (zero-cost); derive from op counts until then |
| Prod RTDB wiring | PREPARED | one env var — command documented, needs approval |

**Implementable low-risk items remaining locally: essentially none** — every
strategy is either shipped behind flags, rejected with evidence, or deferred
behind a cost trigger. Next value is staging validation, not more code.

---

## NEXT-PHASE VERIFICATION (2026-11-04, read-only complete)

### Staging Redis — safe-delete readiness

All checks pass — `ora-staging-n3-redis` has **zero live references**:

- Staging service: no `REDIS_URL`, no VPC connector; logs `geo_init;store=firestore` + `locstreams_init;store=firestore` + `rtdb_init configured=true`
- All 13 worker jobs share `staging_worker_http_invoke.mjs` — pure HTTPS POST to `/v1/internal/*`; no Redis/VPC/DB access possible (verified script + prod job spec)
- Data in instance: geo presence only — ephemeral, self-rebuilds; no backup needed
- Rollback: if staging ever reverted to a pre-Firestore image, recreate BASIC instance (~10 min) — low risk, low likelihood

Exact command (AWAITING APPROVAL — not run):
`gcloud redis instances delete ora-staging-n3-redis --region=us-central1 --project=ora-app-d8112`
Expected: −~$36/mo. Zero functional risk.

### Production deploy script audit — everything `deploy_production_cloud_run.sh` ships

⚠ **`--source=.` builds the whole working tree** — currently ~276 uncommitted
files, not just vetted cost-opt work. Do NOT run it from a dirty tree.

From a clean checkout of HEAD (`7449cc7`), it ships vs live prod image:
1. Firestore-geo migration (redis_geo → geoDrivers) — removes Redis dep
2. RTDB geo + locationStreams backends (opt-in; `GEO_BACKEND` unset → firestore)
3. `--clear-vpc-connector` + `--remove-secrets=REDIS_URL` (infra unwiring)
4. `FIREBASE_DATABASE_URL` if set in .env (it IS set → enables prod RTDB trip tracking — desired, but flag it as a behavior change)
5. Secrets upserts (maps key, worker token), env resets (REQUIRE_APP_CHECK=true)
6. Writes `mobile/.production_api_url`; healthz curl
7. Everything in commits `f821d8d..7449cc7` incl. physical-device-verified stabilization (7cd8194: real device E2E passed Oct 30)

From the dirty tree it would ADDITIONALLY ship all uncommitted work
(cost-opt flags OFF by default = safe, but also unrelated prior-session edits).

**Recommended prod path:** deploy clean checkout of `7449cc7` first
(Redis-free, device-verified, zero uncommitted risk) → delete prod Redis +
connector → later deploy cost-opt branch after staging soak.

### Prod periodic sweep restoration (all schedulers paused)

- Prod worker jobs still exist and point at `/v1/internal/*` endpoints that
  exist on ANY image — **no code dependency on the new coalesced endpoint**.
- Restore anytime: `gcloud scheduler jobs resume <6 prod jobs> --location=us-central1`
  → per-sweep workers resume hitting the service (idempotent).
- Missing coverage: prod has NO ride-state-fcm worker/scheduler — when the
  cost-opt image deploys, replace all 6 with ONE scheduler → `POST /v1/internal/sweeps/all`
  (covers all 8 sweeps incl. ride-state-FCM + geoPresence; 503 on failure).
- Order: redeploy prod (new image) FIRST, then resume schedulers — avoids
  sweep ticks hitting the old Redis-geo revision mid-migration.

### Staging validation sequence (testing window — needs approval to run)

1. `firebase deploy --only firestore:indexes` (freshUntilMs variants first)
2. `deploy_staging_cloud_run.sh` with `LOCATION_ADAPTIVE_FRESHNESS=true
   LOCATION_IDLE_MERGED_CURSOR=true PRICING_RULES_CACHE_TTL_MS=60000`
   (script now forwards all three — verified)
3. Verify logs: `geo_init;store=firestore adaptiveFreshness=true idleMergedCursor=true`
4. Adaptive APK (`ORA_ADAPTIVE_PRESENCE=true`) — internal test track
5. During window ONLY: create+enable ONE staging scheduler → `/v1/internal/sweeps/all`
   with worker token; individual staging schedulers stay PAUSED
6. Acceptance: stationary 30 s / moving 10 s cadence; stale keepalive not
   invitable; nearest-first matching; offer delivery+expiry; FCM-down
   fallback via poll; RTDB tracking visible passenger-side; sweep 503 on
   injected fault; offline driver drops ≤75 s
7. Window rollback: pause coalesced scheduler; unset flags + redeploy;
   Redis deletion is independent (staging never used it)
8. Cost: ~$0 inside free tiers; keep the $20/mo budget alert
