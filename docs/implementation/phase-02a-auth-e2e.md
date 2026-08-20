# Phase 2A — Real Firebase Auth + Session + Backend Contract Verification

**Status:** `PHASE 2A COMPLETE` (live OTP E2E verified 2026-08-20)  
**Date:** 2026-08-20  
**Firebase project:** `ora-app-d8112`  
**Depends on:** Phase 2 authentication client, Firebase native config  
**OTP authority:** **ADR-016 Path A — Firebase-native** (Ora does not run `otpSessions`)  
**Security gate:** see `phase-02a-s-security-gate.md` → `PASS WITH REQUIRED HARDENING`  
**Live OTP note (2026-08-20):** Test `+923012345678` / `123456` → register + `/me` → onboarding. PK allowlisted. Real SMS later (Blaze).

---

## 1. Firebase configuration

| Item | Status |
|---|---|
| Project `ora-app-d8112` | Verified |
| Android `com.ora.ora` + `google-services.json` | Present |
| iOS `com.ora.ora` + `GoogleService-Info.plist` | Present + Runner target + URL scheme |
| Phone / Google / Email providers (Console) | Enabled |
| `Firebase.initializeApp()` once in `main.dart` | Verified |
| Graceful init failure UI | **Added** — no raw Firebase exceptions to users |
| App Check on client | **Not wired** (deferred; backend flag `REQUIRE_APP_CHECK`) |

---

## 2. Phone authentication

| Item | Status |
|---|---|
| Client OTP state machine | Already implemented (Phase 2) |
| Firebase `verifyPhoneNumber` / credential verify | Implemented in `FirebaseAuthDataSource` |
| Fake/mock OTP in production path | None |
| Live device OTP smoke test this phase | **NOT RUN** (requires emulator/device + SMS or Firebase test numbers) |

---

## 3. Firebase identity

After OTP success the client obtains Firebase `User` → `AuthUser(uid, phoneNumber, …)`.

The backend **never** trusts a body/query `uid`. Identity is:

```text
Authorization: Bearer <Firebase ID token>
  → admin.auth().verifyIdToken(token, checkRevoked=true)
  → decoded.uid
```

---

## 4. Token lifecycle

| Step | Owner |
|---|---|
| Session persistence | Firebase Auth |
| ID token / refresh | Firebase Auth via `FirebaseAuthTokenProvider` |
| Bearer injection | `ApiClient` interceptor |
| 401 → single-flight refresh → one retry | Already verified (Phase 2 correction) |
| Secure storage | OTP handshake only — no token mirror |

Tokens / OTP / Authorization values are not logged (security tests retained).

---

## 5. Backend endpoint status (pre- vs post-Phase 2A)

### Before Phase 2A

| Endpoint | Server-side? |
|---|---|
| `POST /v1/auth/register` | **NO** — client-only stub calling `https://api-dev.ora.app/v1` |
| `GET /v1/auth/me` | **NO** — never invoked after sign-in |

### After Phase 2A (repository)

New service: `backend/auth-service/` (Cloud Run–ready Node/TypeScript + Firebase Admin).

| Endpoint | Implemented? | Auth | Idempotency | Notes |
|---|---|---|---|---|
| `POST /v1/auth/register` | **YES (code)** | Bearer Firebase JWT | Required `register_{uid}` bound to token uid | Ignores body `uid`/`role`; creates `users/{uid}` |
| `GET /v1/auth/me` | **YES (code)** | Bearer Firebase JWT | N/A | Ignores `?userId=`; returns frozen profile shape |
| `GET /healthz` | **YES** | none | N/A | Liveness |

| Question | Answer |
|---|---|
| Server URL (live) | **Not deployed.** Local default `:8080`. Client override: `--dart-define=ORA_API_BASE_URL=…` |
| Authentication requirement | Firebase ID token (App Check optional via `REQUIRE_APP_CHECK`) |
| Request schema (register) | Body ignored for identity; header `Idempotency-Key: register_{uid}` required |
| Response schema (/me) | Frozen `04-api-contracts.md` shape including server-derived `profileComplete` |
| Error schema | `{ error: { code, message } }` with 401/403/404/500 |
| Tests | **9/9 PASS** (`npm test` in `backend/auth-service`) |

**Blocking for live E2E:** service-account JSON, Firestore Native enabled in `ora-app-d8112`, process running or Cloud Run deploy, Flutter pointed at that base URL.

---

## 6. Registration bootstrap

```text
Firebase Auth success
  → AuthStateNotifier sets authenticated (splash hold)
  → ResolveAuthProfileUseCase
       → POST /v1/auth/register (always; idempotent)
       → GET  /v1/auth/me
  → profileComplete ? authenticatedReady : onboardingRequired
```

Concurrent register for the same Firebase uid creates at most one Firestore document (transaction).

OTP verify no longer gates register on `isNewUser` only (repairs prior failed bootstrap).

---

## 7. `GET /v1/auth/me`

- Implemented in auth-service.
- Client now **calls it** after every Firebase sign-in / session restore.
- Route guard no longer treats bare `authenticated` as home access.

`profileComplete` rule (Phase 2A server): active, not banned, non-empty `displayName`. New users therefore land on onboarding until real profile submission exists.

---

## 8. Session restoration

| Case | Expected | Client status |
|---|---|---|
| A New user → onboarding | `/me` → `profileComplete:false` | Wired |
| B Completed user → home | `/me` → `profileComplete:true` | Wired |
| C App kill → restore | Firebase session + `/me` | Wired |
| D Token expiry → refresh | Existing single-flight interceptor | Wired (prior) |
| E Refresh fails → login | `restoreSession` / logout paths | Wired |
| F Backend unavailable | Stay `authenticated` on splash (fail closed) | Wired |

Live verification of A–F against a running backend: **NOT RUN**.

---

## 9. Token refresh

Unchanged single-flight behaviour; interceptor tests still pass.

---

## 10. Security

| Control | Status |
|---|---|
| No service account in Flutter | Confirmed; gitignored under `backend/**/secrets/` |
| No Admin SDK in Flutter | Confirmed |
| No tokens/OTP in logs | Security tests pass |
| No client-controlled roles | Backend ignores body role; `AuthUser.copyWith` still blocks role mutation |
| Server verifies Firebase JWT | auth-service middleware |
| `/me` authenticated | Yes |
| Forged `uid` / `?userId=` | Rejected / ignored (backend tests) |
| Disabled / banned | Logout + unauthenticated |
| App Check mandatory | **Not yet** — env-flagged for Phase 3 |

---

## 11. Tests

### Flutter (`flutter test`)

**Result: PASS — 134/131→134**

Added/updated:

- `resolve_auth_profile_use_case_test.dart`
- `auth_state_notifier_test.dart` (profile bootstrap / fail-closed / banned)
- `route_guards_test.dart` (`authenticated` holds splash)
- `onboarding_view_model_test.dart` (re-resolve, no forge)
- `auth_repository_impl_test.dart` (always register)

### Backend (`npm test` in `backend/auth-service`)

**Result: PASS — 9/9**

Covers missing/invalid token, forged uid, wrong idempotency key, `?userId=` ignore, duplicate register.

### Live device / integration against Firebase + running API

**Result: NOT RUN**

---

## 12. Build verification

| Command | Result |
|---|---|
| `flutter pub get` | PASS |
| `dart run build_runner build --delete-conflicting-outputs` | **PASS** — wrote 0 outputs |
| `flutter analyze` | **PASS** — No issues found |
| `flutter test` | **PASS** — 134/134 |
| `flutter build apk --debug` | **PASS** — `app-debug.apk` |
| `flutter build ios --no-codesign` | **NOT RUN** |

---

## 13. Remaining blockers

| Item | Status (2026-08-20) |
|---|---|
| Auth service running locally `:8080` | **DONE** (`/healthz` OK; `appCheck=false`) |
| Service account at `backend/auth-service/secrets/` | **DONE** (gitignored; not in APK) |
| Firestore enabled (production deny-all) | **DONE** (Console) |
| ADR-016 OTP Path A locked | **DONE** |
| Flutter → local API | **READY** — debug APK on emulator; phone-entry UI verified |
| **Live phone OTP E2E** | **PASS (2026-08-20)** — test `+923012345678` / `123456`; register+`/me` → onboarding |
| SMS region PK allowlist | **DONE** via Identity Toolkit (`allowedRegions: ["PK"]`) |
| Debug cleartext for local API | **DONE** — `android/app/src/debug/AndroidManifest.xml` |
| Debug reCAPTCHA skip | **DONE** — `kDebugMode` `appVerificationDisabledForTesting` |

### 13a. Firebase SMS error (2026-08-20)

App showed:

> SMS unable to be sent until this region enabled by the app developer

**Cause:** Firebase SMS region policy (not Ora code). New projects default to **no regions allowed**.

**Fix (pick one path):**

1. **Real SMS to Pakistan**  
   - Firebase Console → **Authentication** → **Settings** → **SMS region policy**  
   - Choose **Allow** / allowlist → enable **Pakistan (PK)**  
   - Also: Phone Auth requires **Blaze** billing for real SMS (Spark cannot send SMS since Sept 2024)

2. **E2E without SMS (recommended for now)**  
   - Authentication → **Sign-in method** → **Phone** → **Phone numbers for testing**  
   - Add e.g. `+92 300 0000000` with fixed code `123456`  
   - Use that number in the app — no SMS, no region, no Blaze required for the test path

```bash
cd mobile
flutter emulators --launch Pixel_9_Pro
# cold boot if stuck: emulator -avd Pixel_9_Pro -no-snapshot-load
flutter run -d emulator-5554 --dart-define=ORA_API_BASE_URL=http://10.0.2.2:8080/v1
```

Auth-service must still be on `:8080`.

---

## 14. Exact next phase

After unblocking (service account + Firestore + run/deploy auth-service + point client + device OTP):

1. Re-run Phase 2A live checklist → flip status to `PHASE 2A COMPLETE`.
2. Then **Phase 3**: App Check + passenger home shell (still no Maps / dispatch / payments).

Do **not** start Maps, RTDB, Redis, dispatch, assignment, or payments from this phase.

---

## Files changed / added (summary)

### Backend (new)

- `backend/auth-service/**` — Express + Firebase Admin auth API, Dockerfile, tests, README

### Flutter

- `lib/main.dart` — graceful Firebase init failure
- `lib/app/config/app_config.dart` — `ORA_API_BASE_URL` dart-define
- `lib/app/di/providers.dart` — resolve-profile use case; network uses AppConfig base URL
- `lib/app/router/route_guards.dart` — `authenticated` holds splash
- `lib/features/auth/.../auth_state_notifier.dart` — register + `/me` bootstrap
- `lib/features/auth/.../resolve_auth_profile_use_case.dart` — new
- `lib/features/auth/.../auth_repository_impl.dart` — always idempotent register
- `lib/features/onboarding/.../onboarding_view_model.dart` — re-fetch `/me`, no forge
- Related tests updated/added

---

## Final status

```text
PHASE 2A COMPLETE
```

Live E2E proven: Firebase test OTP → ID token → `POST /v1/auth/register` → `GET /v1/auth/me` → onboarding. Remaining: App Check + hardening before public users; real SMS near deploy (Blaze).
