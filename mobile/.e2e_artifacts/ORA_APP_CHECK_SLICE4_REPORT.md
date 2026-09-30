# Ora production hardening — slice 4 (Firebase App Check + production pricing proof)

**Date/time:** 2026-09-30 (PKT)  
**Slices 1–3:** Not reopened.  
**Production revision (unchanged):** `ora-auth-service-00001-mwc`

---

## Phase 0 — Existing App Check inventory

| Area | Finding |
|------|---------|
| **Server enforcement** | `createAuthMiddleware` in `middleware/auth.ts`: when `REQUIRE_APP_CHECK=true`, requires header `X-Firebase-AppCheck`, verifies via `firebase-admin/app-check` `verifyToken()` |
| **Production startup** | `production_guards.ts`: refuses start if production without `REQUIRE_APP_CHECK=true` |
| **Where enforced** | All `/v1/*` routes using auth middleware (including `POST /v1/pricing/estimate`) |
| **Android provider (Flutter)** | Debug: `AndroidDebugProvider()` when `kDebugMode`; release: `AndroidPlayIntegrityProvider()` (`firebase_app_check_bootstrap.dart`) |
| **iOS provider (Flutter)** | Debug: `AppleDebugProvider()`; release: `AppleAppAttestWithDeviceCheckFallbackProvider()` |
| **Client header** | `api_client.dart` attaches `X-Firebase-AppCheck` from `AppCheckTokenProvider` (never logged) |
| **Flutter gating** | `AppConfig.appCheckEnabled` via `ORA_APP_CHECK` dart-define; release+production refuses start if App Check off |
| **Backend tests** | `security_phase2b.test.ts`: `APP_CHECK_REQUIRED`, `APP_CHECK_INVALID`, happy path |
| **Automated prod smoke** | `verify_production_smoke.ts` + new `app_check_exchange_debug.ts` (debug UUID → JWT via Firebase `exchangeDebugToken`) |
| **Staging Cloud Run** | `REQUIRE_APP_CHECK=false` (unchanged) |

---

## 1. Firebase project

**`ora-app-d8112`** (project number `498169438285`)

---

## 2. App Check providers / configuration

| Platform | Production-intended provider | Firebase registration (API) |
|----------|------------------------------|-----------------------------|
| Android `com.ora.ora` | Play Integrity | `playIntegrityConfig` present; `tokenTtl=3600s`; `minDeviceRecognitionLevel=NO_INTEGRITY` |
| Android debug (CI/smoke) | Debug provider | **1** registered debug token (display name: Ora prod smoke CI / local) — secret stored **only** in gitignored `.env` |
| iOS `com.ora.ora` | App Attest (+ DeviceCheck fallback) | Not reconfigured this slice (Flutter wiring already present) |

Firebase App Check API enabled on project for debug-token registration.

**App-specific vs project-wide:** Debug tokens are **per Android app** (`1:498169438285:android:3b100b1c7a7248f1ddbc04`). Staging Cloud Run remains App-Check-off; shared Firebase project does not force App Check on staging backend.

---

## 3. Android package / app configuration

| Item | Value |
|------|--------|
| Application ID | `com.ora.ora` |
| Firebase Android app ID | `1:498169438285:android:3b100b1c7a7248f1ddbc04` |
| SHA-256 (google-services) | `9ae7ebcb5767c90667f2367d09d44696d7db53d1` (debug cert hash in config) |
| Flutter App Check | Already integrated; no product UI changes this slice |

---

## 4. Debug-token mechanism (automated verification only)

| Step | Mechanism |
|------|-----------|
| Register | `scripts/register_production_app_check_debug.sh` → Firebase `debugTokens.create` (UUID v4) → append `PRODUCTION_APP_CHECK_DEBUG_SECRET` to local `.env` only |
| Exchange | `scripts/app_check_exchange_debug.ts` → `exchangeDebugToken` with Android API key from `google-services.json` (public client key) |
| Smoke | `verify_production_smoke.ts` exchanges secret per run; sends short-lived JWT as `X-Firebase-AppCheck` |

**Not used:** bypass headers, middleware changes, `REQUIRE_APP_CHECK=false`, committed tokens, Scheduler/Cloud Run env tokens.

---

## 5. Production `REQUIRE_APP_CHECK`

**`true`** on `ora-auth-service` (verified via `gcloud run services describe`).

---

## 6. Valid App Check + Auth + pricing

**PASS** — `npx tsx scripts/verify_production_smoke.ts` exit **0**

---

## 7. Missing App Check

| Request | HTTP | `error.code` |
|---------|------|----------------|
| `GET /v1/auth/me` (no headers) | 401 | `APP_CHECK_REQUIRED` |
| `POST /v1/pricing/estimate` (Firebase Auth only) | 401 | `APP_CHECK_REQUIRED` |

---

## 8. Invalid App Check

| Request | HTTP | `error.code` |
|---------|------|----------------|
| `POST /v1/pricing/estimate` + Auth + `X-Firebase-AppCheck: invalid-app-check-token-for-smoke` | 401 | `APP_CHECK_INVALID` |

---

## 9. Production pricing HTTP status

**200** (with valid Firebase ID token + valid App Check JWT from debug exchange)

---

## 10. `pricingSnapshotId`

**`ps_5b45ecd0-4c8f-4b96-bbac-1a3d1e377b0b`** (server-generated `ps_` prefix; not client-supplied)

---

## 11. `recommendedFareMinor`

**109000** (PKR minor units)

---

## 12. `distanceKm`

**22.869** (> 0, Google Routes-backed)

---

## 13. `durationMin`

**35.75** (> 0)

---

## 14. Pricing rules version

**`2026-09-22:v5c-device`** (field: `pricingRulesVersion`)

---

## 15. Google Routes proof

| Check | Result |
|-------|--------|
| Non-zero distance/duration | PASS |
| Fare not a fixed stub | PASS (109000 PKR minor with bounds) |
| Snapshot TTL | `computedAt` + `expiresAt` present |
| Provider architecture unchanged | Routes → `calculateFare` → Firestore `pricingSnapshots` → API response |
| Client trust | Estimate body allows only `pickup`, `destination`, `city`, `category`, `serviceType` — no client `pricingSnapshotId`/fare/distance (see `pricing_estimate.test.ts`) |

**Offer bounds (server):** min **76300**, max **196200** minor.

**City/serviceType:** Required on request; persisted in snapshot `inputs` server-side (not duplicated on top-level API DTO).

---

## 16. Secret / log audit

| Item | Result |
|------|--------|
| Smoke scripts | No logging of App Check JWT, debug UUID, Firebase ID token, Maps key, worker token, Redis URL |
| `verify_production_smoke.ts` output | IDs and numeric pricing fields only |
| Error JSON | `requestId` only (no secrets in 401 bodies checked) |
| Backend `auth.ts` / `app_logger.dart` | No App Check token logging patterns found |

---

## 17. Staging regression

| Check | Result |
|-------|--------|
| `GET /healthz/` staging | **200** |
| Staging `REQUIRE_APP_CHECK` | **`false`** (unchanged) |
| Staging revision | **`ora-auth-service-staging-00024-4wv`** (unchanged) |

---

## 18. Backend tests

**391/391 PASS** — `npm test -- --run`

---

## 19. Flutter tests

**453 passed, 2 failed** (pre-existing, unrelated to App Check):

- `home_shell_driver_gate_test.dart` — Earn on ORA / driver shell
- `mvvm_layer_test.dart` — HomeShellView logout route

App Check unit test: `app_check_debug_provider_test.dart` **PASS**.

No new Flutter failures introduced by this slice (no Flutter product code changed).

---

## 20. Build

**PASS** — `npm run build`

---

## 21. Physical device result

| Class | Result |
|-------|--------|
| **DEBUG APP CHECK PROOF** | **PASS (automated)** — Firebase-registered debug UUID exchanged for JWT; production `POST /v1/pricing/estimate` **200** |
| **REAL PRODUCTION ATTESTATION (Play Integrity on device)** | **NOT RUN** — requires signed **release** build + Play Integrity path; intentionally **out of slice** (no production APK/AAB) |

Samsung device **RF8R40ZQ1JH** was attached; no release attestation test performed (would not be valid debug-token proof).

---

## 22. Blockers

None for automated **Auth + App Check + Routes + pricing** on production Cloud Run.

**Remaining (not blockers for this slice):**

- Play Integrity / release-build attestation proof on physical hardware
- Firebase Console **Enforce** for Firestore/Storage (optional product rollout; backend already enforces on API)

---

## 23. Next slice (out of scope here)

- Production **release** mobile build (`ORA_ENV=production`, HTTPS prod API, App Check on, Play Integrity)
- Custom domain / `api.ora.app`
- Flutter `production_api_url` wiring in release flavors
- Firestore project/database isolation
- Payment, wallet, maps UI, workers, Scheduler, pricing formula changes

---

## 24. Artifacts added/updated

| File | Purpose |
|------|---------|
| `backend/auth-service/scripts/app_check_exchange_debug.ts` | Safe debug-secret → App Check JWT exchange |
| `backend/auth-service/scripts/register_production_app_check_debug.sh` | One-time debug token registration |
| `backend/auth-service/scripts/verify_production_smoke.ts` | Health, negatives, pricing 200 proof |
| `backend/auth-service/.env.example` | Documents `PRODUCTION_APP_CHECK_DEBUG_SECRET` |
| `docs/operations/production-remote-backend.md` | Smoke instructions updated |

---

## Production safety checklist (Phase 11)

| Check | Status |
|-------|--------|
| `REQUIRE_APP_CHECK=true` | YES |
| No bypass header / middleware bypass | YES |
| No permanent debug token in Cloud Run / git | YES (local `.env` only) |
| No business-logic change for App Check | YES |
| Production smoke uses `mobile/.production_api_url` (not staging) | YES |

---

**APP CHECK + PRICING SLICE = GREEN**
