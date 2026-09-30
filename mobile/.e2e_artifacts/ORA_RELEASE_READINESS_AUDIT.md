# Ora production / release readiness audit (read-only)

**Date:** 2026-09-30  
**Scope:** Repository + live `ora-auth-service-staging` (`ora-auth-service-staging-00022-bkc`)  
**No code, config, or deployment changes were made.**

N3 and D1 implementation areas remain **frozen** for this audit.

---

## Executive summary

Core ride marketplace, pricing, dispatch, FCM, and Firestore rule posture are **technically strong** and **well tested** on the backend. Staging has proven remote two-actor lifecycle and physical D1 FCM. **Controlled production** is **not** supported yet by infrastructure and ops: there is **no production Cloud Run service**, **worker automation is not wired**, the **latest staging revision lacks `ORA_INTERNAL_WORKER_TOKEN`**, and **server secrets are not consistently in Secret Manager**. Mobile **release** path exists in code guards but **staging APK script builds debug with App Check off**.

**ORA RELEASE READINESS AUDIT = RED**

**NEXT REQUIRED ACTION = Put `ORA_INTERNAL_WORKER_TOKEN` and `GOOGLE_MAPS_SERVER_KEY` in Secret Manager on Cloud Run, redeploy staging, and wire Cloud Scheduler (or equivalent) to internal sweep endpoints before treating any environment as production-capable.**

---

## 1. Security — **WARN** (staging gaps → **RED** for production)

| Check | Status | Evidence |
|-------|--------|----------|
| Firebase Admin on server only | PASS | `GOOGLE_APPLICATION_CREDENTIALS` in `.env.example`; Cloud Run uses `firebase-adminsdk-fbsvc@…` SA |
| `.env` / SA JSON not git-tracked | PASS | `git check-ignore` on `backend/auth-service/.env`; no tracked `service-account*.json` |
| Mobile dart-defines | PASS (design) | Docs + `build_staging_apk.sh` require client Places key only; server Maps key documented server-only |
| Server Maps key storage | **FAIL (prod)** | `deploy_staging_cloud_run.sh` sets `GOOGLE_MAPS_SERVER_KEY` as **plain `--set-env-vars`**; live revision exposes it as plain env (visible via `gcloud run revisions describe`) |
| `REDIS_URL` | PASS | Secret Manager `ora-staging-redis-url` on revision `00022-bkc` |
| `ORA_INTERNAL_WORKER_TOKEN` | **FAIL (ops)** | **Not present** on revision `00022-bkc`; `GET /v1/internal/…` without token → **503** “not configured” (live probe) |
| Local dev worker token default | WARN | `local-dev-worker-token-xx` in `run_local_device_backend.sh` / `launchd_entry.sh` — dev only |
| `REQUIRE_APP_CHECK` | WARN | Staging revision: `false`; production ADR expects `true` |
| Cloud Run ingress | WARN | `--allow-unauthenticated` (normal for Firebase JWT–protected API; relies on auth middleware) |
| Internal routes | PASS (when configured) | `X-Ora-Worker-Token` middleware; invalid/missing → 403/503 |
| Public API auth | PASS | `/v1/*` (except `/healthz`) uses Firebase bearer + optional App Check |

**Do not print secret values.** Rotate any server key that was ever deployed as plain env if console access is broader than intended.

---

## 2. Firestore security — **PASS**

- `firestore.rules`: fail-closed; `rides`, `rideOffers`, `drivers`, `outboxEvents`, `pricingSnapshots`, `idempotencyRecords`, `rideDispatchWaves`, `driverDeviceTokens`, `outboxDeliveries`, `ratings` → **deny all client read/write**.
- `users/{uid}`: self read only; **all writes denied** (profile via Admin SDK API).
- `savedPlaces`: owner-scoped only.
- Authoritative state transitions are **backend-only** (Admin SDK bypasses rules by design; clients must not rely on SDK for rides).

---

## 3. Authorization — **PASS** (with ops dependency on workers)

| API family | Auth | Role / ownership |
|------------|------|------------------|
| `/v1/auth/*` | Firebase JWT | Profile PATCH for self |
| `/v1/rides/*` | Firebase JWT | `assertPassenger` / `assertDriverEligible`; ride participant checks in service |
| `/v1/pricing/estimate` | Firebase JWT | Stricter rate limit; server Routes |
| `/v1/drivers/*` | Firebase JWT | Go online/offline; D1 tokens — approved driver |
| `/v1/location/*` | Firebase JWT | Driver stream updates |
| `/v1/internal/*` | Worker token | No Firebase JWT; separate boundary |

Ride create loads **server** `pricingSnapshotId` via `loadPricingSnapshot` and `assertOfferWithinBounds` — client cannot supply authoritative distance/fare without valid snapshot (`ride_service.ts`).

Open discovery / offers: `assertDriverEligible` (approved driver).

**Weaker than intended if misconfigured:** internal routes when worker token unset return **503** (safe) but **disable all automation**.

---

## 4. Cloud Run (staging, live) — **PASS** (staging) / **FAIL** (production service)

| Item | Value |
|------|--------|
| Service | `ora-auth-service-staging` only (no `ora-auth-service` production in `us-central1`) |
| Revision | `ora-auth-service-staging-00022-bkc`, **100% traffic** |
| Health | `GET /healthz/` → 200 `{"ok":true,"service":"ora-auth-service"}` |
| Region | `us-central1` |
| SA | `firebase-adminsdk-fbsvc@ora-app-d8112.iam.gserviceaccount.com` |
| CPU / memory | 1 CPU, 512Mi |
| Timeout | 300s |
| Concurrency | 80 |
| Min / max instances | 0 / 3 (template); platform maxScale annotation 20 |
| VPC | `ora-staging-vpc`, egress `private-ranges-only` |
| Redis | Via secret `ora-staging-redis-url` |

---

## 5. Redis / Memorystore — **PASS** (design); **WARN** (availability)

| Concern | Authority |
|---------|-----------|
| `geo:drivers`, driver online markers | **Redis-authoritative** for N3/N4 discovery inputs |
| Ride/offer/assignment state | **Firestore-authoritative** |
| N3 | MGET + busy prefetch + users/drivers getAll on staging `00022-bkc` |
| N4 | Uses same nearby service + Firestore waves |
| Redis down | N3/N4 nearby → **503 DEPENDENCY_ERROR**; core auth/rides/pricing without Redis still work per ops docs |

---

## 6. Dispatch / FCM (D1) — **PASS** (code + physical proof); **WARN** (automation)

Path implemented: dispatch wave → outbox → `dispatch-fcm-sweep` → FCM → device → tap → Open Rides (physical proofs in `.e2e_artifacts/`).

**Gaps:**
- No in-repo Cloud Scheduler / Terraform for `dispatch-sweep`, `dispatch-fcm-sweep`, expire sweeps (documented only).
- Revision `00022-bkc` **without worker token** → sweeps cannot run **on** Cloud Run until token is set.
- D1 physical proofs used ops scripts (`staging_d1_dispatch_prep.ts`, gcloud token fetch when env was present).

Idempotency / invalid token handling covered in `delivery_d1.test.ts` and projector code (not re-run in this audit).

---

## 7. Ride state machine — **PASS**

- Centralized transitions in `state_machine.ts` + `ride_service.ts`; `requestVersion` on offers/select.
- **87** ride tests including 50-way concurrent select, expiry sweeper, terminal states.
- States listed in audit scope covered in tests/docs (`docs/ORA_STATE_MACHINE.md`).

---

## 8. Pricing — **PASS**

- Google Routes via server `GOOGLE_MAPS_SERVER_KEY` only.
- Snapshots stored server-side; create ride binds snapshot + bounds check on `passengerOfferMinor`.
- Client Places key is separate (`ORA_GOOGLE_PLACES_API_KEY`).

---

## 9. Cleanup / retention — **PASS** (scope)

- `ExpiresAtCleanupService`: **only** `idempotencyRecords`, `pricingSnapshots`, `locationStreams` with **past `expiresAt`**.
- Rides/offers/ratings/outbox **not** in cleanup lists.
- Requires worker token + scheduled invocation (same ops gap).

---

## 10. Mobile release configuration — **WARN** / **RED** (production)

| Item | Finding |
|------|---------|
| Production API URL | Code default `https://api.ora.app/v1` — **no verified production deploy/DNS** in GCP |
| Staging URL | `build_staging_apk.sh` uses `.staging_api_url` from deploy (Cloud Run URL) — OK for staging |
| Localhost / adb reverse | Dev docs and older APK artifacts use `127.0.0.1:8081` — **not** in release guards |
| Release guards | `AppConfig`: release + production **requires** App Check; **blocks HTTP** in release |
| Staging APK script | **`flutter build apk --debug`**, `ORA_APP_CHECK=false` — appropriate for staging share, **not** production store |
| Places key | Required at build via dart-define; not embedded server key |
| Firebase / FCM | Standard Flutter Firebase setup (google-services not audited for prod project split) |
| Test OTP | Documented in `docs/implementation/dev-otp-test-numbers.md` — ops/Firebase console concern |

**Before production release:** production Cloud Run URL dart-define, **`ORA_ENV=production`**, **`ORA_APP_CHECK=true`**, **release** (not debug) build, production Firebase/FCM/Places projects and key restrictions.

---

## 11. Test coverage (this audit run)

| Suite | Result |
|-------|--------|
| Backend | **391/391** pass (`npm test -- --run`) |
| Backend build | PASS |
| Flutter | **453 pass, 2 fail** (`home_shell_driver_gate_test.dart` — widget test failures) |

Focused backend areas present: N3 (diagnostics, MGET, busy prefetch, getAll), D1 delivery, rides, pricing, auth, cleanup tests in `expires_at_cleanup.test.ts`, etc.

---

## 12. Physical E2E status

**Proven (artifacts):**
- Remote staging two-actor lifecycle (2026-09-29) — HTTPS Cloud Run, full state path to `RIDE_CLOSED`.
- D1 real FCM + notification tap + fresh ride on Open Rides (Samsung physical).
- Auth, server pricing, assignment, lifecycle transitions.

**Not proven / partial:**
- **Production** environment end-to-end (no prod service).
- **Release APK** (non-debug) with App Check enforced against prod backend.
- **Automated** dispatch/FCM without manual worker HTTP (scheduler + token on service).
- **iOS** physical parity (audit focused on Android evidence in repo).
- **Online payment / wallet** production PSP (payment method enum exists; phase-15 checklist not closed).
- **NO_SHOW** automated sweeper (documented server path; not in physical proof list).

---

## 13. Observability — **WARN**

**Present:** `requestId` middleware; `logSafe` on N3, dispatch, D1, sweeps; N3 batch/logical read diagnostics; domain error codes.

**Missing for production:** centralized metrics/SLO dashboards, alert policies on worker 503/503 dependency, trace propagation, FCM delivery SLIs, synthetic probes for internal workers (not implemented in repo).

---

## 14. Disaster / failure behavior (read-only)

| Failure | Expected | Current | Safe? | Blocker? |
|---------|----------|---------|-------|----------|
| Firestore down | 5xx on mutations | Admin SDK errors → 5xx | Yes | Degrades all |
| Redis down | N3/N4/discovery 503 | Implemented | Yes | Dispatch discovery blocked |
| FCM down | Outbox retry / failed delivery | Projector marks retryable | Yes | Drivers not notified |
| Routes down | Pricing 503 | `PRICING_UNAVAILABLE` | Yes | No new priced rides |
| Cloud Run cold start | Latency spike | min-instances=0 | Acceptable staging | YELLOW prod |
| Duplicate worker | Idempotent sweeps / leases | Partial — sweep design | Mostly | YELLOW |
| Duplicate HTTP | Idempotency keys on create | Implemented | Yes | — |
| Expired ride | Reject transitions | STATE_CONFLICT | Yes | — |
| Stale driver | N3/N4 filter | Redis + Firestore | Yes | — |
| Invalid FCM token | Remove / skip | D1 tests | Yes | — |

---

## 15. Findings table

| Area | Status | Evidence | Risk | Required action |
|------|--------|----------|------|-----------------|
| Firestore rules | GREEN | `firestore.rules` deny authoritative collections | Low | Deploy rules to prod project with release |
| Backend domain logic | GREEN | 391 tests; physical E2E reports | Low | None before prod infra |
| N3 performance (staging) | GREEN | `00022-bkc`, benchmark GETALL artifact | Low | Frozen — no changes |
| D1 FCM path | GREEN | Physical + unit tests | Low | Frozen — no changes |
| Secret hygiene (Maps key) | **RED** | Plain env on Cloud Run; deploy script | Key leakage, abuse | Secret Manager + restrict key |
| Worker token on Cloud Run | **RED** | Absent on `00022-bkc`; internal 503 | No expire/dispatch/cleanup on service | Set secret + redeploy |
| Cloud Scheduler / workers | **RED** | Not in repo | Stale rides, no dispatch automation | Ops wiring + monitoring |
| Production Cloud Run | **RED** | Only staging service listed | No prod target | Create prod service + domain |
| App Check (staging) | YELLOW | `REQUIRE_APP_CHECK=false` | Bot abuse on staging | Enable before prod |
| App Check + release mobile | YELLOW | Staging debug APK | Prod client bypass if mis-built | Release build + enforce |
| Mobile Flutter CI | YELLOW | 2 failing widget tests | Regressions slip | Fix tests pre-release |
| Payments / wallet | YELLOW | Enum + docs phase-15 open | Non-cash flows incomplete | Product decision |
| Observability | YELLOW | Logs only | Slow incident response | Metrics/alerts |
| min-instances=0 | YELLOW | Cold starts | Latency | Tune for prod |

---

## 16. Final decision

### RED blockers
1. **No production Cloud Run (or verified `api.ora.app`) deployment.**
2. **`ORA_INTERNAL_WORKER_TOKEN` not configured on current staging revision** — internal automation disabled (503).
3. **Server Maps API key in plain Cloud Run env** — not production-grade secret handling.
4. **No Cloud Scheduler (or equivalent) wired** for expire, dispatch, FCM, cleanup workers.

### YELLOW items
- App Check off on staging; production mobile must ship with App Check on.
- Staging APK is **debug** with App Check false.
- Flutter **2** failing tests.
- Cold starts, log-only observability, payment/wallet production readiness.

### GREEN areas
- Firestore client rule matrix (fail-closed).
- Ride state machine, concurrency, idempotency (backend tests + remote E2E).
- Server-authoritative pricing snapshots and offer bounds.
- Redis-backed N3/N4 discovery (staging proven).
- D1 FCM delivery path (physically proven on Android staging).
- Git secret hygiene for local `.env` / SA files.

### Minimum required work before controlled production
1. Production GCP project or service boundary: **prod Cloud Run**, DNS, Firebase prod config.
2. **Secret Manager** for `GOOGLE_MAPS_SERVER_KEY` and `ORA_INTERNAL_WORKER_TOKEN`; remove plain env values.
3. **Configure worker token** on every revision that runs workers; verify internal routes return 403 (not 503) when token wrong.
4. **Cloud Scheduler** → internal POSTs (expire, offer-expire, dispatch-sweep, dispatch-fcm-sweep, expires-at cleanup) with monitoring.
5. **`REQUIRE_APP_CHECK=true`** on production backend after client App Check validated.
6. **Release mobile build**: `ORA_ENV=production`, HTTPS API, App Check true, Places key restricted.
7. Fix **2** Flutter test failures; run full regression on release candidate.

### Optional post-release improvements
- min-instances > 0, RED metrics, synthetic N3/D1 probes, iOS physical D1 proof, rate limit env wiring (documented but hardcoded defaults).

---

**N3 remains frozen.**  
**D1 remains frozen.**  
**No implementation was performed by this audit.**

---

**ORA RELEASE READINESS AUDIT = RED**

**NEXT REQUIRED ACTION = Configure `ORA_INTERNAL_WORKER_TOKEN` and `GOOGLE_MAPS_SERVER_KEY` via Secret Manager on Cloud Run and redeploy; then wire Cloud Scheduler to internal worker endpoints and verify 200 sweep/dispatch responses.**
