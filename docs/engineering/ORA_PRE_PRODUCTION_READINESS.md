# Ora Pre-Production Readiness Checklist

Date: 2026-11-24. This is the near-production gate document — use it
as the starting point when production deployment is planned.
**Nothing here authorizes autonomous action** — every infra/deploy
step requires explicit owner approval.

---

## Phase A — Immediate development fixes (code, local)

| # | Item | Gap | Complexity | Approval |
|---|---|---|---|---|
| A1 | ~~Fix avatar body-limit bug~~ **DONE 2026-11-24** — route-scoped `express.json({limit:'512kb'})` on `PATCH /v1/auth/profile` before the global 32kb parser; global limit unchanged; auth/rate-limit/validator preserved; tested (>32kb→200, >512kb→413, other routes→413) | GAP-003 P1 | XS | code review |
| A2 | Add bounded driver-invite poll while online+foregrounded (adaptive: ~15 s idle / ~4 s when actionable invites exist), reusing `driverInviteActivityProvider` | GAP-001/DR-001 P1 | S | DR-001 decision — **STILL PENDING** |
| A3 | ~~Decide driver approval model~~ **DECIDED: MANUAL APPROVAL (DR-002)** — implement via admin platform review workflow (approve/reject/request-info/resubmit), shared lifecycle module, `DRIVER_AUTO_APPROVE=false` only after review paths ship | GAP-002 | M | approved — schedule with admin P0+P1 |
| A4 | Add `expiresAt` to outboxEvents at write + include in `ExpiresAtCleanupService` | GAP-009 P3 | XS | DR-007 decision — **STILL PENDING** |
| A5 | Trip-authz short-TTL cache (10–15 s) in `LocationUpdateService` | GAP-011 P2 | S | DR-006 decision — **STILL PENDING** |
| A6 | ~~Sample per-packet logs~~ **DONE 2026-11-24** — `LogSampler` + `shouldEmitSteadyStateLog` (1st + every 10th, always on ≥1000 ms slow path); errors/skip/failure logs never sampled; behavior unchanged; tested | GAP-006 P2 | XS | none |
| A7 | ~~Multiple-active-ride guard~~ **DONE 2026-11-24** — `passengerActiveRides/{uid}` pointer acquired/released in-transaction across all 6 terminal writers + createRide (with legacy query fallback for pre-pointer rides); 17 unit tests + Firestore-emulator 20-way concurrency proof (1×201/19×409) + create/cancel boundary test; full suite 742/742 | R-1 | M | approved + verified |
| A8 | Regression tests for each fix | — | — | — |

## Phase B — Pre-production engineering (hardening, still local/staging-prep)

| # | Item | Gap | Complexity |
|---|---|---|---|
| B1 | Commit cost-optimization work to a reviewed branch (currently ~uncommitted in tree) | GAP-004 | S |
| B2 | Add cost-opt flags to deploy scripts' `ENV_VARS` (staged, default OFF until enabled) | GAP-004 | XS |
| B3 | Cost-per-unit rollup sweep (~60 lines in `/sweeps/all`) | cost plan §6.3 | S |
| B4 | Cloud Logging metric filters: SWEEPS_ALL failures, GEORADIUS_SCAN_CAPPED, N3 p95 | observability | S |
| B5 | Billing budget alerts at realistic thresholds ($25 staging / $100 prod) | cost plan §6.1 | XS — console |
| B6 | Load test: geo benchmark at 2k/5k/10k driver fleets on staging Firestore (real latency, not emulator) | perf | M |
| B7 | Failure drills: Firestore outage simulation, FCM sender failure, sweep fault injection → verify 503 + retry | reliability | M |
| B8 | Estimate-path cost check: confirm `computeRoute` path used with Google provider (multi-stop = 1 call not 9) | C-2 | XS [RT] |
| B9 | Avatar/KYC storage: **DR-003 conditionally approved** — Firebase Storage *conditionally feasible* at ~$0 (Blaze already active; us-central1 mandatory; quotas: 5 GB stored / 100 GB-mo download / 5k uploads / 50k download-ops). NOT guaranteed — egress-to-PK qualification and quota monitoring must be verified from billing data. Awaiting owner confirmation of option S (Storage) vs F1 (Firestore private docs). Bucket creation = infra change requiring approval | C-4/GAP-008 | M | conditional |
| B10 | Route-result geohash cache — only if Routes spend >$20/mo | deferred | M |

## Phase C — Staging validation (requires deploy approval)

Already executed once (Nov 5 window, 33/33 PASS) — repeat for the
final image:

- [ ] Deploy `firestore.indexes.json` first (freshUntilMs variants —
      already live per prior audit, re-verify)
- [ ] Staging deploy with `LOCATION_ADAPTIVE_FRESHNESS=true
      LOCATION_IDLE_MERGED_CURSOR=true PRICING_RULES_CACHE_TTL_MS=60000
      FIREBASE_DATABASE_URL=<staging-rtdb>`
- [ ] Verify `geo_init store=firestore adaptiveFreshness=true
      idleMergedCursor=true` + `rtdb_init configured=true`
- [ ] Adaptive APK (`ORA_ADAPTIVE_PRESENCE=true`) on physical device:
      stationary 30 s / moving 10 s (real travel) / invite boost 8 s /
      keepalive honest-ts / killed-app drop ≤75 s
- [ ] Invite poll (A2) cadence verification on device
- [ ] RTDB trip tracking visible passenger-side on real device
- [ ] FCM delivery proof (real device token, not just poll fallback)
- [ ] Sweep fault injection → `/sweeps/all` returns 503
- [ ] N3_NEARBY p95 re-measure post-hardening
- [ ] 24–48 h soak; billing stays ~$0
- [ ] Rollback drill: unset flags + redeploy; verify legacy behavior

## Phase D — Near-production readiness (each step = explicit approval)

Ordered per `ORA_COST_OPTIMIZATION_PLAN.md` §PROD-ROLLOUT:

1. [ ] `git worktree` clean checkout of approved commit — NEVER
       `--source=.` on dirty tree
2. [ ] Verify `.env`: `FIREBASE_DATABASE_URL`, Maps key, worker token
3. [ ] Deploy prod image (Firestore-geo, Redis-free) → assert
       `geo_init;store=firestore` cold-start log
4. [ ] Smoke: healthz + driver online→nearby + synthetic ride→invite
5. [ ] Resume 6 paused prod schedulers (or single coalesced job if
       cost-opt image ships first)
6. [ ] **Rollback window hold** — keep prod Redis + connector + secret
7. [ ] After window: delete `ora-production-n3-redis`,
       `ora-staging-vpc`, `ora-production-redis-url` secret,
       orphan N3 jobs (~$60–95/mo realized)
8. [ ] Enable cost-opt flags on prod + coalesced scheduler + adaptive
       APK rollout (staged: internal track → % rollout)
9. [ ] Billing budget alerts live; monitoring dashboards wired
10. [ ] `DRIVER_AUTO_APPROVE` decision applied (DR-002)
11. [ ] App Check production enforcement verified on real release build
       (not debug provider)

## Phase E — Post-launch (data-driven, do not pre-build)

- [ ] First billing reconciliation vs model (±40% band expected)
- [ ] Cost-per-driver-hour / per-ride metrics from rollup sweep
- [ ] N3 latency at real fleet density; geo-read cost vs $50/mo trigger
- [ ] Routes/Places actual spend vs $20/mo trigger
- [ ] RTDB concurrent-trip count vs Spark 100-conn cap
- [ ] Invite accept rate / time-to-first-offer (validates GAP-001 fix)
- [ ] Presence packets/driver-hour anomaly alert

---

## Mandatory pre-production sequence (owner-directed, 2026-11-24)

**This checklist MUST be completed in order before any production
release. Do not skip or reorder steps. Cost optimizations stay intact;
no paid infrastructure or deployment without explicit approval.**

1. [ ] **Review and commit A1, A6, A7 safely** — reviewed branch/commit
       only; preserve the existing dirty tree; no `--source=.` deploys
2. [ ] **Complete remaining approved critical fixes (A2–A5)** —
       A2 invite poll (needs DR-001), A4 outbox expiry (needs DR-007),
       A5 authz cache (needs DR-006); A3 manual-approval enforcement
       ships with the admin review workflow
3. [ ] **Deploy the final committed build to staging**
4. [ ] **Repeat regression tests** — avatar upload, location updates,
       rides and courier flows on the final image
5. [ ] **Verify on real infrastructure** — real FCM delivery, physical
       GPS movement cadence, invite flow, failure drills
6. [ ] **Complete 24–48 hour staging soak** — billing stays ~$0
7. [ ] **Verify secrets, environment, App Check, schedulers and
       rollback plan**
8. [ ] **Obtain explicit owner approval before production deployment**

---

## Hard blockers before any real-user traffic

1. **GAP-002/DR-002** — driver self-approval. **Approved target
   policy: MANUAL driver approval** (decided 2026-11-24). **Current
   runtime behavior: unchanged — `DRIVER_AUTO_APPROVE` still
   auto-approves; this is NOT a corrected state.** **Production risk:
   UNRESOLVED** — it remains until the backend enforcement and Admin
   review workflows (approve/reject/request-info/resubmit, shared
   lifecycle module, audit logging) are implemented AND verified, and
   `DRIVER_AUTO_APPROVE=false` is set for production. Auto-approval
   must not ship to real users as an accepted exception — treat it
   as an open P1 blocker, not a waived risk.
2. **GAP-004** — prod deploy + scheduler restoration + RTDB env
3. ~~**GAP-003**~~ — avatar upload fix **DONE 2026-11-24** (A1)
4. **DR-001** — invite discovery reliability decision (still pending)
5. Release build must have App Check enforced (guard exists; verify
   the shipped APK uses production provider, not debug)
6. ~~**DR-008**~~ — one-active-ride guard **DONE + emulator-verified
   2026-11-24** (A7); still requires commit + staging re-verification

## Explicit non-goals for this phase

- No Redis/Memorystore reintroduction
- No Firestore listeners for ride state
- No chat/reels/media features (not built; would be new scope)
- No payments execution (schema stubs only — product decision needed)
- No multi-region / always-on infrastructure
