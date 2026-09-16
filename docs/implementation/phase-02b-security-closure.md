# Phase 2B — Security Closure + Production Readiness Gate

**Date:** 2026-08-20  
**Firebase project:** `ora-app-d8112`  
**Package / bundle:** `com.ora.ora`  
**Authoritative OTP path:** ADR-016 Path A — Firebase-native Phone Auth  

---

## Executive verdict

### PHASE 2B SECURITY GATE: **PASS WITH REQUIRED ACTIONS**

| Layer | Status |
|---|---|
| **CODE VERIFIED** | **YES** — auth, App Check wiring, rules versioning, HTTPS guard, error sanitization, secret hygiene, fail-closed production guards |
| **FIREBASE CONSOLE VERIFIED** | **NO** — cannot be proven from repo alone; checklist below |
| **LIVE E2E VERIFIED** | **PARTIAL** — Phase 2A phone OTP E2E on emulator succeeded; App Check Play Integrity / App Attest **not** live-proven |
| **PRODUCTION VERIFIED** | **NO** — do not call production “secure” until Console + staging App Check E2E + shared rate limits |

**Do not proceed to Maps / RTDB / Redis / rides / payments until the Manual Firebase Console Actions and production rate-limit plan are accepted.**

Next recommended phase after closure actions: **Phase 3 auth/onboarding polish only** (or design-system), **not** Maps.

---

## Current architecture (locked — unchanged)

| Concern | Owner |
|---|---|
| OTP issue / deliver / verify / Firebase throttle | **Firebase Phone Auth** |
| Firebase ID token verify (`checkRevoked=true`) | Ora auth-service |
| Register / `/me` / profile / bans | Ora auth-service |
| App Check token verify (when enabled) | Ora auth-service |
| API rate limit (auth routes) | Ora auth-service (**process-local today**) |
| Client UX resend cooldown (~30s) | Flutter client only |
| Ride / payment / driver authority | Backend + fail-closed Firestore rules (collections denied to clients) |

**Ora does not enforce `otpSessions` counters.** Path B is deferred. Stale “server OTP limits” text in `phase-02-authentication.md` was corrected in this closure.

---

## Security findings

### CRITICAL
| ID | Finding | Status |
|---|---|---|
| C1 | Production could previously start with `REQUIRE_APP_CHECK=false` | **MITIGATED in code** — `assertProductionSecurityConfig` refuses start when `ORA_ENV`/`NODE_ENV=production` and App Check off. **Ops must still set `REQUIRE_APP_CHECK=true`.** |
| C2 | Firebase Console App Check Enforce / provider registration | **OPEN** — Manual Console |

### HIGH
| ID | Finding | Status |
|---|---|---|
| H1 | Rate limiter is **in-memory / per-process** | **DOCUMENTED** — **LOCAL ONLY — NOT PRODUCTION READY** for multi-instance Cloud Run. Future: Redis/Memorystore or Cloud Armor (not implemented this phase). |
| H2 | Staging App Check end-to-end not proven | **OPEN** — Manual |

### MEDIUM
| ID | Finding | Status |
|---|---|---|
| M1 | Firestore rules only static-contract tested (no emulator suite locally) | **SUPERSEDED in Phase 2C** — emulator suite is `test/firestore.rules.test.mjs`; CI job `firestore-rules`. |
| M2 | Unused Google + Email/Password providers still enabled | **DECISION REQUIRED** — do not auto-disable |
| M3 | Missing `.dockerignore` | **FIXED** this closure |
| M4 | Absolute machine path in `run-local.sh` | **FIXED** — relative/`env` based |
| M5 | No `Retry-After` on 429 | **FIXED** this closure |

### LOW / INFO
| ID | Finding | Status |
|---|---|---|
| L1 | Client still sends body `uid` on register (ignored server-side) | INFO |
| L2 | `caller.disabled` hardcoded `false` (relies on `checkRevoked`) | INFO |
| I1 | Rate-limit extension point documented for future ride routers | INFO |

---

## Baseline verification (code inspection)

| Control | Result | Evidence |
|---|---|---|
| Firebase Phone Auth only | **PASS** | `firebase_auth_data_source.dart` — no Google/Email sign-in |
| `verifyIdToken(token, true)` | **PASS** | `middleware/auth.ts` — second arg `true`; unit asserts call shape |
| Server-derived UID | **PASS** | `routes/auth.ts` + `services/users.ts` |
| IDOR-safe `/me` | **PASS** | ignores `?userId=` |
| Transactional register | **PASS** | Firestore transaction + idempotency key bound to uid |
| App Check client | **PASS** | `activateOraAppCheck`; debug provider only if `kDebugMode` |
| `X-Firebase-AppCheck` | **PASS** | `api_client.dart` |
| `REQUIRE_APP_CHECK` | **PASS** (when true) | middleware + production guard |
| Rate limiting | **PASS (local)** | uid+IP after auth; **not** multi-instance ready |
| Firestore rules | **PASS (versioned)** | fail-closed + protected user fields |
| HTTPS / release HTTP reject | **PASS** | `api_base_url_guard.dart` |
| Error sanitization | **PASS** | generic 401/500; FailureMapper |
| Single-flight refresh | **PASS** | token provider + interceptor tests |
| Banned handling | **PASS** | 403 `ACCOUNT_DISABLED` + client logout |
| Secret/git hygiene | **PASS** | SA/`.env`/google-services untracked |
| Cleartext Android | **PASS** | debug manifest only |
| iOS ATS | **PASS** | no ATS HTTP exceptions in Info.plist |
| RELEASE + debug App Check | **PASS (blocked)** | `kDebugMode` gate |
| RELEASE + HTTP | **PASS (blocked)** | guard + release throw |
| PRODUCTION + App Check false | **PASS (blocked)** | backend + client fail-closed |

---

## Fail-closed configuration matrix

| Combination | Expected | Code behavior |
|---|---|---|
| DEV + HTTP + App Check off | Allowed | Yes |
| STAGING + HTTP without `ORA_ALLOW_HTTP_API` | Rejected | Yes |
| RELEASE + HTTP | Rejected | Yes |
| RELEASE + debug App Check provider | Forbidden | `kDebugMode` false in release |
| PRODUCTION backend + `REQUIRE_APP_CHECK=false` | Refuse start | `production_guards.ts` |
| PRODUCTION release client + `ORA_APP_CHECK=false` | Refuse start | `app_config.dart` |

---

## Rate limiting audit

| Item | Result |
|---|---|
| Per verified UID | Yes (key includes uid) |
| Per IP | Yes (`req.ip`, `trust proxy = 1`) |
| Protects `POST /register` + `GET /me` | Yes (mounted on `/v1/auth`) |
| 429 `RATE_LIMITED` | Yes |
| `Retry-After` | Yes (added this closure) |
| Spoofed body uid bypass | No (auth first) |
| Proxy spoofing | Mitigated by `trust proxy = 1` (single hop / Cloud Run) |
| **Production grade** | **NO — LOCAL ONLY — NOT PRODUCTION READY** |

**Future production mechanism (do not implement yet):** Redis/Memorystore sliding window or Cloud Armor edge rate limits keyed by verified Firebase uid (+ IP). Mount additional limiters on ride/payment routers later.

---

## Firestore rules matrix (architecture collections)

Legend: **D** = deny client; **O** = owner self; **B** = backend/Admin SDK only.

| Collection | READ | CREATE | UPDATE | DELETE | Notes |
|---|---|---|---|---|---|
| `users/{uid}` | O (self) | D | O (non-privileged fields only) | D | Blocks self-assign `role`, `banned`, phones, etc. |
| `savedPlaces/{id}` | O | O | O | O | Low-risk owner data |
| `drivers`, `vehicles`, `driverDocuments` | D | D | D | D | Server authority |
| `rides`, `rideOffers`, `rideEvents` | D | D | D | D | No client assignment |
| `outboxEvents`, `idempotencyRecords` | D | D | D | D | Backend only |
| `pricing*`, `feePolicies` | D | D | D | D | Backend only |
| `payment*`, `wallet*`, `refunds`, `driverPayouts`, `reconciliationRecords` | D | D | D | D | No client payment status |
| `ratings` | D | D | D | D | Backend mediated |
| `safetyEvents`, `reports`, `blocks`, `tripShareTokens` | D | D | D | D | Safety boundary |
| `supportTickets*` | D | D | D | D | Backend |
| `consentRecords` | D | D | D | D | Backend |
| `adminAuditLogs`, `moderationCases` | D | D | D | D | Admin only |
| `notificationReceipts` | D | D | D | D | Backend |
| `otpSessions` | D | D | D | D | Path B unused; deny if present |
| `/{document=**}` | D | D | D | D | Catch-all fail-closed |

**Undocumented client collections:** none discovered beyond rules + `savedPlaces` / `users`.

**Rules tests:** static contract **PASS**. Emulator evaluation: **REQUIRES LIVE ENVIRONMENT** (not run in this closure).

---

## Auth security test matrix

| # | Attack | Expected | Result |
|---|---|---|---|
| 1 | Missing Authorization | 401 UNAUTHENTICATED | **PASS** |
| 2 | Malformed Authorization | 401 | **PASS** |
| 3 | Expired token | SDK reject → 401 | **PASS (SDK)** |
| 4 | Wrong Firebase project | SDK reject | **PASS (SDK)** |
| 5 | Revoked token | 401 sanitized | **PASS** (unit) |
| 6 | Disabled Firebase account | reject via checkRevoked / user-disabled | **PASS (SDK + mapper)** |
| 7 | Deleted Firebase account | token verify fail | **PASS (SDK)** |
| 8 | Forged UID | ignored | **PASS** |
| 9 | Forged role | server sets passenger | **PASS** |
| 10 | Forged userId query | ignored | **PASS** |
| 11 | Cross-user `/me` | caller only | **PASS** |
| 12 | Duplicate register | idempotent | **PASS** |
| 13 | Concurrent register | transaction | **PASS / partial** (no true parallel stress) |
| 14 | Replay register | idempotent | **PASS** |
| 15 | Missing App Check (enforced) | APP_CHECK_REQUIRED | **PASS** |
| 16 | Invalid App Check | APP_CHECK_INVALID | **PASS** |
| 17 | Expired App Check | verify fail | **PASS (SDK)** |
| 18 | Rate limit exceeded | 429 + Retry-After | **PASS** |
| 19 | HTTP production API URL | throw / reject | **PASS** |
| 20 | Sensitive logging | no tokens/OTP | **PASS** |
| 21 | Token refresh race | single-flight | **PASS** |
| 22 | Logout / restore | clears / fail-closed splash | **PASS** |
| 23 | Banned user | 403 + logout | **PASS** |
| 24 | Malformed body | controlled error | **PASS (contract)** / express default |
| 25 | Oversized body | 32kb limit configured | **PASS (contract)** |

---

## PROVIDER DECISION REQUIRED

| Provider | Console (reported) | Used by Ora client | Recommendation |
|---|---|---|---|
| Phone | Enabled | **Yes** | Keep |
| Google | Enabled | **No** | **Disable before production** after explicit approval (reduces attack surface) |
| Email/Password | Enabled | **No** | **Disable before production** after explicit approval |

Do **not** disable automatically.

---

## Secret / supply-chain audit

| Check | Result |
|---|---|
| `service-account.json` tracked | **NO** |
| `.env` tracked | **NO** |
| google-services / GoogleService-Info tracked | **NO** (ignored; present on disk for local builds) |
| Private keys in source | **NO** |
| Admin SDK in Flutter | **NO** |
| `.dockerignore` | **ADDED** |
| Dockerfile copies secrets | **NO** (selective COPY) |

---

## Mobile security

| Item | Result |
|---|---|
| Android cleartext | Debug only |
| Release App Check debug provider | Impossible via `kDebugMode` |
| Signing secrets in repo | `key.properties` ignored |
| iOS ATS | Default secure (no production HTTP exception) |
| Firebase client config | Public client identifiers only |

---

## Auth UX security

Flow: splash → Firebase restore → ID token → register/`/me` → onboarding OR home.

| Failure | Behavior |
|---|---|
| Profile bootstrap fail | Hold splash (`authenticated` without ready) — fail closed |
| Banned | Logout → unauthenticated |
| API unavailable | Fail closed (no forged ready) |
| Logout | Clears local auth state |
| Token refresh | Single-flight; one retry |

---

## App Check modes

| Mode | Client | Backend | Console Enforce |
|---|---|---|---|
| Dev | Often off / debug provider OK | `REQUIRE_APP_CHECK=false` | Off |
| Staging | Real providers + tokens | Prefer `true` after client green | Monitor first |
| Production | Play Integrity / App Attest | **Must** `true` (startup enforced) | Only after staging E2E |

---

## Manual Firebase Console Actions

| # | Console location | Setting | Current (assumed) | Desired | Safe now? | Needs staging E2E first? | Verify after |
|---|---|---|---|---|---|---|---|
| 1 | App Check → Apps | Register Android `com.ora.ora` + Play Integrity | Unknown | Registered | Yes | No | Client obtains token in staging build |
| 2 | App Check → Apps | Register iOS `com.ora.ora` + App Attest (+ DeviceCheck fallback) | Unknown | Registered | Yes | No | Same |
| 3 | App Check → APIs | Enforcement | Off / Monitor | Monitor → Enforce later | Monitor yes; Enforce **no** until staging green | **Yes** | API rejects missing/invalid tokens with prod backend flag |
| 4 | Cloud Run / secrets | `REQUIRE_APP_CHECK` | Often false in local | `true` for staging/prod | Staging when client ready | Staging E2E | Hit API without header → `APP_CHECK_REQUIRED` |
| 5 | Firestore | Deploy `firestore.rules` | May be default | Deploy versioned rules | After review | Prefer emulator first | Unauthorized client write denied |
| 6 | Firestore | Indexes | Empty file | Deploy when queries need | N/A now | N/A | — |
| 7 | Authentication → Sign-in method | Google | Enabled unused | **Disable after approval** | **No** without approval | N/A | Confirm Phone-only still works |
| 8 | Authentication → Sign-in method | Email/Password | Enabled unused | **Disable after approval** | **No** without approval | N/A | Same |
| 9 | Project settings | Android SHA-1/256 | Dev keystore likely | Release + debug SHA registered | Yes for debug; release before store | N/A | Phone auth / Play Integrity |
| 10 | SMS regions | PK allowlist | Configured for 2A | Keep for PK launch | Yes | N/A | Test number / real SMS on Blaze |

---

## Exact next phase recommendation

1. Complete Manual Firebase actions 1–6 (and 9).  
2. Staging E2E: OTP → register → `/me` **with real App Check tokens** + `REQUIRE_APP_CHECK=true`.  
3. Decision on Google/Email disable (7–8).  
4. Plan Redis/Cloud Armor rate limits **before** public load (do not implement ride stack yet).  
5. Only then open **Maps / location** (Phase 4) — not before this gate’s REQUIRED ACTIONS are done.

**Stop condition honored:** no Maps, RTDB, Redis, fare, dispatch, payments, or ride business logic in this closure.

---

## Code changes in this closure

- `backend/auth-service/.dockerignore`
- `backend/auth-service/src/config/production_guards.ts` (+ tests)
- `backend/auth-service/src/index.ts` — startup guard
- `backend/auth-service/src/middleware/rate_limit.ts` — `evaluate` + Retry-After support; LOCAL ONLY note
- `backend/auth-service/src/middleware/rate_limit_middleware.ts` — `Retry-After` header
- `backend/auth-service/scripts/run-local.sh` — no absolute machine path
- `backend/auth-service/vitest.config.ts`
- `backend/auth-service/src/__tests__/security_phase2b.test.ts` — checkRevoked + Retry-After
- `mobile/lib/app/config/app_config.dart` — production release App Check fail-closed
- `mobile/test/core/security/app_check_debug_provider_test.dart`
- Docs: `phase-02-authentication.md`, `phase-02a-auth-e2e.md`, this file

---

## Confirmation checklist

- [x] No Admin credential in Flutter  
- [x] No Admin credential in Git  
- [x] Firebase ID token verification secure  
- [x] `checkRevoked=true`  
- [x] App Check architecture implemented  
- [x] API App Check verification implemented  
- [x] API rate limiting implemented (**local only**)  
- [x] Firestore rules versioned  
- [x] Production HTTP guard  
- [x] Error sanitization  
- [x] Sensitive logging protection  
- [x] Auth IDOR protection  
- [x] Session security  
- [x] Security tests (code)  
- [x] No architecture regression  
- [ ] Firebase Console fully verified  
- [ ] Live App Check E2E  
- [ ] Production multi-instance rate limits  
