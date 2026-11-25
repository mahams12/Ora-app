# Ora Reliability, Security & Scalability Audit

Date: 2026-11-24 · Read-only code inspection. No secrets reproduced;
all credential references are by name only.

---

## 1. Reliability — failure-mode analysis

| Failure | Behavior today | Verdict |
|---|---|---|
| Network loss (client) | dio retries GETs ×3 exp-backoff; mutations NOT retried unless idempotent flag; presence publisher backoff 2→30 s; seq preserved, replay → 422 | **Good** |
| Poor network | 15/30/60 s HTTP timeouts; keepalive republishes last fix ≤90 s age; marker expires ≤75 s after last accepted packet → driver drops from matching | **Good** (bounded) |
| App termination / device restart | marker expiry = offline detection ≤75 s; session restore on relaunch (verified on-device); availability re-fetched on start | **Good** |
| Token expiry | 401 → single forced-refresh retry in interceptor; App Check token fetched per request | **Good** |
| Firebase outage | API returns 503 DEPENDENCY_ERROR for geo ops; auth fails closed; RTDB listener soft-closes on permission/error | **Acceptable** — ride creation blocked (Firestore down = everything down anyway) |
| Cloud Run failure | minScale 0 → cold starts (~seconds); maxScale 10; no multi-region | **Acceptable at launch**; cold-start latency noted |
| External API outage | Routes failure → 503 PRICING_UNAVAILABLE (fail-closed, no fare without route); Nominatim fallback chain exists | **Good** |
| Duplicate requests | Idempotency-Key + `idempotencyRecords` on all mutations; create-once wave docs; CAS outbox leases; seq monotonic per stream | **Strong** |
| Concurrent ride requests | createRide tx + idem doc; two rapid creates → second hits idem or creates second SEARCHING ride (no "one active ride per passenger" guard seen — see R-1) | **Check** |
| Simultaneous driver acceptance | invite accept → createOffer tx; multiple drivers can offer; passenger selects one; losing offers expire via sweep | **Good** |
| Scheduler overlap | sweeps idempotent + state-checked + batch-limited; coalesced endpoint isolates per-step failures → 503 | **Good** |
| Partial job failure | per-sweep try/catch in `/sweeps/all`; individual endpoints same pattern; `failed` counters in results | **Good** |
| DB contention | Firestore tx retries (merged cursor ≤2 → 429 CURSOR_CONFLICT); 20-way concurrency proof 28/28 | **Good** |
| Traffic spike | Cloud Run scales 0→10; concurrency 80; rate limit 60/min/uid+IP per instance | **Watch** — per-instance limiter multiplies by instance count (GAP-005) |

### R-1 — Multiple concurrent passenger rides — **DECIDED (DR-008)**

**Approved 2026-11-24:** one active ride per passenger, enforced in
the `createRide` transaction; active = `PASSENGER_BLOCK_STATES`
(8 non-terminal states), terminal states unblock rebooking. Full
enforcement design + tests in the decision register DR-008.
Recommended approach: per-passenger `passengerActiveRides/{uid}`
pointer document inside the create transaction (a query-only check
has a phantom-read hole and is insufficient alone). Implementation
pending — correctness must be proven by the concurrency tests listed
in DR-008 before enabling.

### R-2 — Invite discovery relies on FCM (GAP-001, P1)

See decision register DR-001. On devices where FCM high-priority
delivery is delayed beyond the 20 s invite TTL, drivers never see
invites unless they open Open Rides. Wave expansion mitigates
(passenger waits for next cohort), but in sparse fleets this directly
lengthens match time or exhausts waves → ride EXPIRED.

### R-3 — Prod operational state (GAP-004, P1)

- All 6 prod schedulers PAUSED → ride expiry, offer expiry, no-show,
  dispatch FCM, dispatch sweep, storage cleanup are **all OFF in
  production**. Fine only while prod has no real traffic.
- Prod `ora-auth-service` lacks `FIREBASE_DATABASE_URL` →
  `NullTripLocationRtdb` → passenger live tracking silently dead.
- Prod still wired to Redis secret + VPC connector until the
  Firestore-geo image deploys.
- Prod has NO ride-state-FCM worker/scheduler (staging does) — the
  coalesced `/sweeps/all` covers it once deployed.

### R-4 — Cold-start + scale-to-zero

minScale=0 means first request after idle pays Cloud Run cold start
(~1–5 s) plus Firebase Admin init. For a ride-hailing app the first
GPS packet of a driver going online may time out client-side (15 s —
usually OK). Acceptable; consider minScale=1 only if p95 startup
proves problematic [RT].

---

## 2. Security review

| Area | Finding | Severity |
|---|---|---|
| AuthN | Firebase ID token verified per request (`verifyIdToken(..., true)` — revocation checked); App Check enforced when `REQUIRE_APP_CHECK=true`; prod startup REFUSES without it (`production_guards.ts`) | **Strong** |
| AuthZ | Every route re-derives identity from token uid; `body.driverId` never trusted; ride read restricted to passenger/assigned driver; invite accept verifies wave membership + expiry + ride state in tx | **Strong** |
| Firestore rules | Fail-closed catch-all; only `users` self-read + `savedPlaces` owner writes allowed to clients; all authoritative collections denied | **Strong** |
| RTDB rules | `tripLocations` read gated by `rideAccess/{rideId}/{uid}` written server-side; `geoPresence`/`locationStreams` deny-all | **Strong** |
| Internal endpoints | `X-Ora-Worker-Token` required, ≥16 chars, 403 on mismatch, 503 when unconfigured | **Good** — token compare is `!==` (not constant-time; low risk for a high-entropy token, note only) |
| Secrets | Secret Manager for Maps key + worker token + (legacy) Redis URL; deploy script never prints values; `.env` gitignored? — **verify** | check |
| App Check | Debug provider only when `kDebugMode`/explicit flag; prod enforced server-side | **Good** |
| Rate limiting | 60/min global + 10/min estimate, per uid+IP, Retry-After header sent | **Gap** — in-memory per instance (GAP-005) |
| Replay attacks | locationSeq monotonic per stream + `lsPreviousStreamIds`; idempotency records; invite TTL server-side | **Strong** |
| User/device identity | uid = Firebase auth uid everywhere; device tokens stored per uid with role gating; token cleared on sign-out | **Good** |
| Private chat isolation | n/a — no chat exists | n/a |
| Trip-location privacy | passengers read only their own ride's `latest` via rideAccess ACL; drivers' idle geo markers are server-only (rules deny `geoDrivers` via catch-all) | **Strong** |
| PII | CNIC/license/plate plaintext in `drivers/{uid}`; phone in `users/{uid}`; avatar base64 in users doc | **P2** — acceptable pre-KYC; encrypt/hash CNIC when review flow lands (DR-002) |
| ~~Driver self-approval~~ | **DECIDED 2026-11-24 (DR-002): manual approval** — implementation via admin review workflow; runtime unchanged until review paths ship | **P1 → decided** |
| Avatar upload | `express.json` 32 kb global limit vs 400 KB avatar cap → uploads >~24 KB fail 413 | **P1 bug** (GAP-003) — broken feature, not a vulnerability |
| Input validation | Strict allowlist keys everywhere checked (`rejectUnknownKeys`, `parseNearbyQuery` forbidden-param rejection); numeric ranges enforced; express 32 kb body cap | **Strong** |
| Error leakage | `sendApiError` returns code+message only; internal errors → generic INTERNAL; `logSafe` never logs tokens/OTP/secrets | **Good** |

### Security positives worth keeping

- `assertFirebaseTargetConfig` — local runs CANNOT silently hit prod
  Firebase, real FCM, or paid Routes (emulator hosts + `ORA_FCM_SENDER=none`
  + `ORA_ROUTING_PROVIDER=haversine` enforced).
- `assertProductionSecurityConfig` — prod refuses to boot without App Check.
- `REFUSING_START` guards on unknown `GEO_BACKEND`/`LOCATION_STREAMS_BACKEND`.
- Worker endpoints fail closed (503) when token unset — can't be
  accidentally exposed.

---

## 3. Scalability assessment

| Dimension | Current ceiling [CALC/RT] | Evidence |
|---|---|---|
| Concurrent online drivers | geo reads flat to 10k fleet (benchmark, 0 misses); partitioning rejected until >2k drivers/city AND >$50/mo geo reads | `SPATIAL_BENCH.csv` |
| findNearby latency | ~280 ms empty / ~1.1 s candidate-bearing staging; hardened to est. ~500–700 ms (local, unverified on staging) | prior audit §N3 |
| Cloud Run | 1 instance ≈ 660 rps headroom @120 ms; maxScale 10 → ~6k rps theoretical; presence traffic @10k DAU ≈ ~45 rps avg, ~200 rps peak | model |
| Firestore | hottest doc = `geoDrivers/{driverId}` per-driver (no hot doc); `rides/{id}` tx per transition; outbox PENDING scans bounded | code |
| RTDB connections | **Spark 100 concurrent** — >~100 simultaneous tracked trips requires Blaze or alternative | rules/pricing note |
| Sweeps | coalesced ~3.4 s/min typical, 13.4 s peak — fits 60 s tick to high volume | staging window |
| Firestore tx contention | merged cursor 20-way proof: 2 commits/18 ordered 422s — graceful | emulator proof |

### Scale triggers already defined (do not act early)

- >2,000 concurrent drivers/city AND geo reads >$50/mo → geohash/h3
- >~50–100 concurrent tracked trips → RTDB Blaze or alternative
- Routes spend >$20/mo → route-result cache
- Geo writes >$30/mo → re-evaluate Redis GEOSEARCH

---

## 4. Not-applicable / already-solved ledger

- Chat/messaging encryption, delivery acks, ordering — **n/a**
- Reels/media caching, thumbnails, orphaned media — **n/a**
- Firestore listeners replacing polling — **evaluated & rejected**
  (fan-out read billing, no win) — already solved decision
- Redis/Memorystore — **removed from code path**; cloud deletion pending
- H3/geohash indexing — **benchmarked & rejected** at current scale
- RTDB presence/onDisconnect — **rejected** (conn cap)
