# Ora Master Engineering Gap Analysis

**Single source of truth** for audit findings, decisions, remediation
tasks, priorities and statuses.
Date: 2026-11-24 · Mode: ANALYSIS ONLY — no code/infra changed.
Branch: `devin/1794389046-orange-profile-merge` (working tree contains
uncommitted `cost-optimization-local` work).

Supporting documents:
- [Architecture audit](ORA_ARCHITECTURE_AUDIT.md)
- [Cost engineering plan](ORA_COST_ENGINEERING_PLAN.md)
- [Reliability/security/scalability audit](ORA_RELIABILITY_SECURITY_AUDIT.md)
- [Scalability & performance plan](ORA_SCALABILITY_PERFORMANCE_PLAN.md)
- [Pre-production readiness](ORA_PRE_PRODUCTION_READINESS.md)
- [Decision register](ORA_ENGINEERING_DECISION_REGISTER.md)
- Prior art (still authoritative for cost work):
  `docs/audits/ORA_COST_OPTIMIZATION_PLAN.md`,
  `docs/audits/SPATIAL_BENCH.csv`, `docs/ORA_CURRENT_STATE.md`

Classification: **Confirmed bug** · **Confirmed architectural
weakness** · **Potential risk [repro needed]** · **Optimization
opportunity** · **Future scale concern** · **Already solved** ·
**Not applicable**.

Severity: P0 critical · P1 high · P2 medium · P3 low.

---

## Findings summary

| Severity | Count | IDs |
|---|---|---|
| P0 | 0 | — |
| P1 | 4 | GAP-001, GAP-002, GAP-003, GAP-004 |
| P2 | 7 | GAP-005, GAP-006, GAP-007, GAP-008, GAP-011, GAP-012, R-1 |
| P3 | 5 | GAP-009, GAP-010, GAP-013, GAP-014, C-5 |
| N/A | — | chat/reels/media/payments-execution (not built) |

---

## P1 — High

### GAP-001 — Driver invite discovery is FCM-dependent on the home screen

- **Subsystem:** mobile notifications + dispatch
- **Files:** `mobile/lib/features/driver/presentation/view_models/driver_invites_view_model.dart`,
  `mobile/lib/features/driver/presentation/widgets/driver_invites_section.dart:133-141`,
  `mobile/lib/features/driver/presentation/views/driver_open_rides_view.dart:67`,
  `mobile/lib/core/notifications/dispatch_fcm_service.dart:214-236`,
  `backend/auth-service/src/rides/dispatch_types.ts:24` (`N4_INVITE_TTL_MS=20s`)
- **Current behavior:** `GET /v1/rides/invited` is fetched only on
  Open-Rides mount, invites-section mount (once), pull-refresh, or
  FCM-nudge-triggered refresh. No periodic invite poll exists for an
  online foregrounded driver.
- **Expected:** bounded poll fallback independent of FCM (the design
  claim "poll = reliability floor" only holds while the screen is open).
- **Evidence:** [VC] grep of all `Timer` usages — none polls invites;
  `_loadRequested` fires once per mount.
- **Root cause:** invite polling was scoped to the open-rides screen;
  home-screen driver has no invite channel except push.
- **User impact:** on devices with delayed/dropped FCM (OEM doze —
  common in target market), drivers never see invites within the 20 s
  TTL; waves advance without them → longer match times / EXPIRED rides
  in sparse fleets.
- **Cost impact:** fix adds ~240–360 reads/driver-day [CALC] ≈
  <$0.50/mo @1k DAU.
- **Security/reliability impact:** availability/reliability only.
- **Severity:** P1 · **Confidence:** confirmed by inspection [VC]
- **Recommended:** DR-001 option 1 — adaptive invite poll (15 s idle,
  ~4 s when actionable invites present), driven by existing
  `driverInviteActivityProvider`.
- **Alternatives:** FCM-only (status quo); RTDB invite channel
  (rejected — Spark 100-conn).
- **Risks:** steady-state request volume (small); battery (mitigate
  via adaptive cadence + foreground-only).
- **Tests:** VM test for poll cadence; device test with FCM disabled.
- **Dependencies:** none. **Timing:** Phase A (pre-production).
- **Status:** `PENDING — USER REVIEW` (DR-001)

### GAP-002 — Driver self-approval with unverified KYC

> **DECIDED 2026-11-24 — MANUAL APPROVAL (DR-002 APPROVED).**
> Implementation is gated on the Ora Admin Platform review workflow;
> runtime `DRIVER_AUTO_APPROVE` stays unchanged until approve/reject
> paths ship. See DR-002 decision detail for states, RBAC linkage,
> backend enforcement and outstanding questions.

- **Subsystem:** driver onboarding / trust & safety
- **Files:** `backend/auth-service/src/config/driver_auto_approve.ts`,
  `.env.example:24`, `backend/auth-service/src/drivers/driver_onboarding_service.ts:67-153`
- **Current:** `DRIVER_AUTO_APPROVE` defaults true → any phone-verified
  user becomes `driverStatus='approved'` by submitting format-valid
  CNIC/license/plate. No document check, no admin review.
- **Expected:** production launch should gate real drivers (manual
  review or verified KYC).
- **Evidence:** [VC] env default + code path.
- **Root cause:** auto-approve was a launch convenience; no review
  console exists yet.
- **User impact:** fake-driver fraud, passenger safety exposure,
  chargeback/dispute risk once cash rides scale.
- **Cost impact:** ~$0 either way at launch volumes.
- **Severity:** P1 · **Confidence:** confirmed [VC]
- **Recommended:** ~~DR-002 decision before launch~~ **DECIDED:**
  manual approval via admin review workflow; flip
  `DRIVER_AUTO_APPROVE=false` only after approve/reject paths ship.
- **Alternatives:** post-hoc anomaly flagging (weaker).
- **Risks:** slower driver onboarding ops.
- **Tests:** onboarding→pending→approve flow test.
- **Dependencies:** admin surface (new, small). **Timing:** Phase B/D.
- **Status:** `DECIDED — MANUAL APPROVAL` (DR-002, 2026-11-24);
  implementation gated on admin review workflow

### GAP-003 — Avatar upload broken by global 32 kb JSON limit

- **Subsystem:** backend HTTP / profile
- **Files:** `backend/auth-service/src/app.ts:95` (`express.json
  {limit:'32kb'}`), `backend/auth-service/src/services/profile.ts:24`
  (`AVATAR_DATA_MAX_LENGTH=400_000`),
  `mobile/lib/features/auth/presentation/views/profile_view.dart:61-92`
- **Current:** any `PATCH /v1/auth/profile` body >32 kb → HTTP 413
  before validation. Client resizes avatars to 512 px JPEG q82 —
  typically 30–135 KB → base64 40–180 KB → **virtually all real
  avatars fail**.
- **Expected:** avatars up to the documented 400 KB cap succeed.
- **Evidence:** [VC] static inspection; reproduction = upload any
  normal photo.
- **Root cause:** global body limit set for API payloads; avatar
  feature added later without route-scoped limit.
- **User impact:** profile photo silently broken (error shown as
  generic failure).
- **Cost impact:** none (failures are cheap); fixing naively activates
  GAP-008 bandwidth cost — sequence with DR-003.
- **Severity:** P1 (broken shipped feature) · **Confidence:**
  confirmed [VC]
- **Recommended:** route-scoped body parser for `/v1/auth/profile`
  (e.g. `express.json({limit:'512kb'})` mounted only on that route
  before the global parser, or raw-body handling). Then decide
  avatar home per DR-003.
- **Alternatives:** move avatar to Firebase Storage now (bigger
  change, removes hot-doc cost too).
- **Risks:** larger body limit slightly raises DoS surface on one
  route — mitigated by auth + rate limit.
- **Status:** **FIXED 2026-11-24 (A1)** — route-scoped 512kb parser on
  `PATCH /v1/auth/profile` before the global 32kb parser; tested
  (>32kb→200, >512kb→413, other routes→413). Avatar *home* still
  pending DR-003.
- **Tests:** backend test POSTing >32 kb avatar → 200; mobile widget
  test.
- **Dependencies:** DR-003 decision for long-term. **Timing:** Phase A.
- **Status:** `PENDING — USER REVIEW` (approach choice)

### GAP-004 — Production still on pre-optimization stack; standing waste + dead features

- **Subsystem:** cloud infrastructure / deployment
- **Files:** `backend/auth-service/scripts/deploy_production_cloud_run.sh`,
  `docs/audits/ORA_COST_OPTIMIZATION_PLAN.md` §PROD-ROLLOUT,
  `docs/ORA_CURRENT_STATE.md` §27
- **Current [VCL]:** prod runs old image (Redis geo path remnants),
  `REDIS_URL` secret + VPC connector attached (~$60–95/mo standing),
  all 6 prod schedulers PAUSED (expiry/dispatch/no-show/FCM sweeps
  OFF), no `FIREBASE_DATABASE_URL` (RTDB trip tracking silently
  dead), no ride-state-FCM scheduler, cost-opt code uncommitted in
  working tree.
- **Expected:** Firestore-geo prod image deployed, sweeps restored,
  RTDB tracking live, Redis/connector deleted after rollback window.
- **Evidence:** prior cloud inventory + deploy-script audit (Nov 4–5).
- **Root cause:** rollout gated on owner approvals; never executed.
- **User impact:** none today (no prod traffic); **blocker** before
  launch — rides would never expire/dispatch without sweeps.
- **Cost impact:** ~$60–95/mo standing waste; usage savings (~50–70%)
  unrealized.
- **Severity:** P1 · **Confidence:** confirmed [VCL]
- **Recommended:** DR-004 two-stage rollout exactly as preflighted.
- **Alternatives:** single-stage deploy (larger blast radius).
- **Risks:** documented rollback plan exists; sparse-matching window
  ~15 s at cutover.
- **Tests:** staging window already passed 33/33; repeat on final image.
- **Dependencies:** owner approval per step. **Timing:** Phase C/D.
- **Status:** `PENDING — USER REVIEW` (DR-004)

---

## P2 — Medium

### GAP-005 — Rate limiter is per-instance in-memory

- **Files:** `backend/auth-service/src/middleware/rate_limit.ts:4`
  (self-documented "LOCAL ONLY"), `app.ts:108-120`
- **Current:** 60 req/min per uid+IP **per Cloud Run instance**;
  maxScale 10 → effective ~600/min; cold starts reset buckets.
- **Expected:** documented production mechanism (code comment names
  Redis/Cloud Armor as future).
- **Impact:** abuse headroom ×instance count; not exploitable cheaply
  at launch scale.
- **Severity:** P2 · **Confidence:** confirmed [VC]
- **Recommended:** DR-005 — accept now, add Cloud Armor L7 rule at
  production hardening.
- **Status:** `PENDING — USER REVIEW`

### GAP-006 — Per-packet double logging

- **Files:** `backend/auth-service/src/location/routes.ts:43-50`,
  `backend/auth-service/src/redis/geo_projection.ts:252-258`
- **Current:** every accepted GPS packet emits `LOCATION_UPDATE` +
  `REDIS_GEO_PROJECTED` (2 JSON log lines). ~622k lines/day @1k DAU
  driver-heavy [CALC].
- **Impact:** Cloud Logging ingest ~0.3–0.6 GiB/mo @1k DAU; ×10 at 10k.
  Inside free tier early; material later.
- **Severity:** P2 · **Confidence:** confirmed [VC]
- **Recommended:** sample (1-in-N steady-state, always log errors +
  slow >p95) — keep `N3NearbyDiagnostics` aggregates for observability.
- **Status:** **FIXED 2026-11-24 (A6)** — `LogSampler`/`shouldEmitSteadyStateLog`
  in `http/log_sampling.ts`; steady-state success logs emit 1st +
  every 10th or always when ≥1000 ms; error/skip/failure paths
  unsampled; tested.

### GAP-007 — Estimate cost: snapshot write + Routes call per estimate

- **Files:** `backend/auth-service/src/pricing/estimate_service.ts:216-338`
- **Current:** every estimate (a) calls routing provider — Google
  Routes when key present — and (b) writes a `pricingSnapshots` doc
  (10-min TTL, cleanup exists). Pin-dragging produces 3–8 estimates
  per booking; multi-stop fallback can issue up to 9 sequential
  `computeDriveRoute` calls when `computeRoute` is unavailable
  (`estimate_service.ts:227-246`).
- **Impact:** Routes spend is the #2 cost driver after presence;
  snapshot writes ~4× booking count.
- **Severity:** P2 · **Confidence:** confirmed [VC]; provider path
  [RT]
- **Recommended:** verify prod uses `computeRoute` (B8); route-result
  geohash cache when spend >$20/mo (defined trigger); consider
  snapshot-write dedup/reuse within TTL.
- **Status:** deferred-by-trigger + Phase B verification.

### GAP-008 — avatarData ≤400 KB inside hot `users/{uid}` doc

- **Files:** `backend/auth-service/src/services/profile.ts:24-57`,
  `backend/auth-service/src/rides/eligibility.ts:21`,
  `backend/auth-service/src/drivers/nearby_service.ts:704-748`
- **Current:** base64 avatar stored in users doc; read by `loadActor`
  on most endpoints and by N3 `getAll` batches (full doc billed per
  read regardless of fields accessed).
- **Impact:** once GAP-003 is fixed, up to ~400 KB egress per users-doc
  read in matching batches. Masked today only because uploads fail.
- **Severity:** P2 · **Confidence:** confirmed [VC]
- **Recommended:** DR-003 — Firebase Storage + `avatarPath`, or
  strip avatar from hot reads via separate doc.
- **Status:** `CONDITIONALLY APPROVED` (DR-003, 2026-11-24) — Firebase
  Storage is *conditionally feasible* at ~$0 within Blaze no-cost
  quotas (us-central1 mandatory); NOT guaranteed — egress geography
  and quota monitoring unverified; final option confirmation pending

### GAP-011 — Trip-mode authz read on every 4 s packet

- **Files:** `backend/auth-service/src/location/location_update_service.ts:188-191,343-375`
- **Current:** `assertTripPublishAuthorization` does `rides/{id}.get()`
  per trip packet → ~900 extra reads/driver-hour of trip.
- **Impact:** ~25% of trip-mode read volume; latency + cost.
- **Severity:** P2 · **Confidence:** confirmed [VC]
- **Recommended:** DR-006 — 10–15 s authz cache; passenger RTDB
  listener already ride-state-gated so bounded staleness is safe.
- **Status:** `PENDING — USER REVIEW` (DR-006)

### GAP-012 — N3 dense-radius read amplification (watch item)

- **Files:** `backend/auth-service/src/drivers/nearby_service.ts`,
  `backend/auth-service/src/redis/firestore_geo_client.ts:57-65`
- **Current:** wave-3 25 km box in dense metro → up to ~100 geo hits ×
  (users+drivers getAll + busy chunks) ≈ ~300–500 reads/wave. Bounded
  by `limit=100` and scan caps; benchmark-verified flat to 10k fleet.
- **Impact:** cost grows with fleet density; trigger defined
  (>2k drivers/city AND >$50/mo geo reads → partitioning).
- **Severity:** P2 (scale watch) · **Confidence:** confirmed [VC]+[CALC]
- **Recommended:** no action until trigger; monitor `N3_NEARBY`
  diagnostics.
- **Status:** monitored, deferred by design.

### R-1 — No guard against multiple concurrent passenger rides

> **DECIDED 2026-11-24 — ONE ACTIVE RIDE PER PASSENGER (DR-008
> APPROVED).** Backend-transaction enforcement via per-passenger
> `passengerActiveRides/{uid}` pointer doc (query-only check rejected
> — phantom-read hole); active states = `PASSENGER_BLOCK_STATES` set;
> terminal transitions release the pointer in the same tx.
> **IMPLEMENTED + VERIFIED 2026-11-24 (A7)** — 17 unit tests +
> Firestore-emulator 20-way concurrency proof (1×201/19×409) +
> create/cancel boundary test; full suite 742/742. Pending commit +
> staging re-verification — see DR-008.

- **Files:** `backend/auth-service/src/rides/ride_service.ts:1190+`
  (`createRide`), `backend/auth-service/src/services/users.ts:21-30`
  (PASSENGER_BLOCK_STATES exists for mode-switch only)
- **Current:** nothing observed preventing a second `POST /v1/rides`
  while one is SEARCHING/active.
- **Expected:** either one-active-ride enforcement or explicit product
  support for multiples.
- **Evidence:** [VC] code inspection; **[RT] reproduction test owed**.
- **Impact:** double dispatch, confused state, support load.
- **Severity:** P2 · **Confidence:** potential risk [repro needed]
- **Recommended:** ~~tx pre-check `passengerId==uid AND state in ACTIVE`
  limit 1~~ — **superseded:** query-only checking is NOT sufficient
  (phantom-read hole). Approved design = per-passenger
  `passengerActiveRides/{uid}` pointer doc inside the create
  transaction (DR-008) — **implemented 2026-11-24**; verified by
  emulator concurrency proof.
- **Status:** `APPROVED` + **IMPLEMENTED 2026-11-24 (A7)** —
  `rides/active_ride_pointer.ts` + 6 terminal-writer clears in
  `ride_service.ts`; pending commit + staging re-verification

---

## P3 — Low

### GAP-009 — outboxEvents terminal docs never deleted

- **Files:** `backend/auth-service/src/delivery/dispatch_fcm_projector.ts`,
  `ride_state_fcm_projector.ts`, `maintenance/expires_at_cleanup_service.ts`
- **Current:** DELIVERED/DEAD_LETTER docs accumulate forever; sweeps
  filter by publishState so no read amplification — storage only.
- **Fix:** `expiresAt` at write + cleanup coverage (DR-007). P3.

### GAP-010 — geoDrivers expired docs linger

- **Files:** `backend/auth-service/src/redis/firestore_geo_client.ts:186-196`
- **Current:** `expiresAt` Timestamp twin exists for a TTL policy, but
  cleanup service doesn't cover `geoDrivers`; expired docs persist
  (bounded: 1 doc per distinct driver ever online).
- **Fix:** optional — Firestore TTL policy on `expiresAt` (console) or
  add to cleanup. Cost negligible. P3.

### GAP-013 — RTDB passenger listener connection ceiling

- **Files:** `mobile/lib/features/ride/data/location/rtdb_trip_location_data_source.dart`,
  `database.rules.json`
- **Current:** one persistent RTDB connection per passenger during
  active trip; Spark tier caps ~100 concurrent connections.
- **Impact:** >~100 simultaneous tracked trips → connection failures
  (tracking silently stops; polling still works).
- **Severity:** P3 now → scale trigger documented (>50 concurrent
  trips → Blaze/alternative decision).
- **Status:** deferred by trigger.

### GAP-014 — `listOpenRides` bounded scan

- **Files:** `backend/auth-service/src/rides/ride_service.ts:1746-1759`,
  `open_discovery_query.ts:14` (cap 200)
- **Current:** `assignedDriverId==null AND state in EXPIRABLE` scan ≤200
  docs per refresh; pull-to-refresh only.
- **Impact:** ≤200 reads/driver refresh — fine now; grows if drivers
  refresh habitually or expired rides accumulate between sweeps.
- **Severity:** P3 · **Status:** monitor.

### C-5 — (merged into GAP-009) outbox retention — see above.

---

## Potential risks requiring reproduction

| ID | Item | Needed test |
|---|---|---|
| R-1 | multiple concurrent passenger rides | API test: 2× POST /v1/rides same passenger |
| R-2 | invite latency under real FCM doze conditions | device test with FCM disabled/doze |
| R-3 | prod cold-start p95 under scale-to-zero | staging load test after idle |
| R-4 | `verifyIdToken` revocation-check latency under load | staging latency breakdown |

## Already solved (verified this audit — do not re-open)

- Adaptive presence heartbeat + keepalive honesty (A1 fix verified)
- Merged idle cursor (28/28 emulator tx proofs)
- Coalesced sweeps with 503 semantics + SEARCHING guard
- Geodesic lng-box fix (0 misses / 8,400 queries)
- N3 batched invite revalidation (local, 699/699 backend tests)
- Pricing-rules TTL cache
- Bounded polling everywhere it exists
- Retry policy (no non-idempotent retries)
- Fail-closed rules/startup guards/worker auth
- Spatial partitioning / Redis / RTDB-presence rejections (benchmarked)
- Emulator-mode paid-service guards

## Not applicable (confirmed absent — do not audit as gaps)

- Chat/messaging systems, encryption, delivery acks — **not built**
- Reels/media feed, video/image upload, thumbnails, media caching —
  **not built** (avatar picker only, see GAP-003/008)
- Firebase Storage, buckets, media lifecycle — **not used**
- Payments/wallets/payouts execution — schema stubs only
- Cloud Tasks/Pub-Sub — not used (Scheduler→Jobs→HTTP instead)
- Redis/Memorystore runtime — removed from code; cloud deletion pending

---

## Execution policy for future Devin sessions

This section is the persistent policy — re-read before any
implementation work on Ora.

1. **Re-read this document first.** Check the finding's status —
   don't duplicate completed work.
2. **Verify current code/infra before acting** — the tree is dirty
   (~2,557 uncommitted files); confirm the file state you assume.
3. **Apply only approved decisions** — items marked
   `PENDING — USER REVIEW` stop at the decision gate; present options
   with evidence, do not pick silently.
4. **Add regression tests** for every fix; update this document's
   status + evidence after implementation.
5. **Production-readiness triggers** — automatically invoke
   `ORA_PRE_PRODUCTION_READINESS.md` Phase C/D checklist when:
   production deployment is planned, staging acceptance passes, a
   release candidate is prepared, or an infra/migration change needs
   production approval.
6. **Never autonomously:** deploy, change prod traffic, enable prod
   flags, resume prod schedulers, delete infrastructure, or incur new
   paid costs.
7. **Honesty rule:** label estimates [CALC], emulator results [RT],
   cloud state [VCL]; never present modeled cost as billing.

## remediation roadmap (summary — details in readiness doc)

- **Phase A (now, local):** GAP-003 fix, GAP-001 poll (post-DR-001),
  GAP-009 cleanup, R-1 guard decision, A6 log sampling.
- **Phase B (pre-prod):** commit cost-opt work, deploy-script flags,
  cost rollup sweep, monitoring metrics, budget alerts, load tests.
- **Phase C (staging):** full re-validation window on final image.
- **Phase D (prod, per-step approval):** two-stage rollout → sweeps →
  rollback window → Redis/connector/secret deletion → flags +
  coalesced scheduler → adaptive APK staged rollout.
- **Phase E (post-launch):** billing reconciliation, cost-per-unit
  metrics, trigger-based scaling decisions only.
