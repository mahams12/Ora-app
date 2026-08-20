# Phase 2 — Authentication & Onboarding Foundation

**Status:** COMPLETE  
**Dependencies:** Phase 1 (Flutter Foundation + MVVM)  
**Architecture reference:** `docs/architecture-final/24-phase-1.6-condition-closure.md` (frozen contracts)

---

## Implementation Summary

Phase 2 implements the full phone-OTP authentication foundation for Ora: Firebase Auth integration, OTP state machine, secure token storage, token refresh with single-flight deduplication, auth-driven route guards, onboarding foundation, and comprehensive tests. No ride dispatch, payment, maps, or driver matching was implemented.

**OTP authority (amended 2026-08-20):** Firebase Phone Auth per [ADR-016](../architecture-final/ADRs/ADR-016-Firebase-Native-OTP.md). Ora does not implement custom `otpSessions` for MVP.

---

## Architecture Used

- **Pattern:** MVVM + Clean Architecture — View → ViewModel → UseCase → Repository → DataSource
- **DI:** Riverpod `NotifierProvider` / `Provider` graph in `app/di/providers.dart`
- **Router:** go_router with `AuthRouteGuard` reading `AuthStateNotifier` (Riverpod)
- **Auth identity:** Firebase Auth (phone OTP via `verifyPhoneNumber`)
- **Auth REST:** Ora Cloud Run API — `POST /v1/auth/register`, `GET /v1/auth/me`
- **Secure storage:** `flutter_secure_storage` (Keychain/Keystore) replacing Phase 1 in-memory placeholder

---

## Files Created

### Core
| File | Purpose |
|---|---|
| `mobile/lib/core/storage/secure_storage.dart` | `SecureStorage` interface + `FlutterSecureStorageImpl` + `InMemorySecureStorage` (tests) |
| `mobile/lib/core/storage/storage_keys.dart` | Centralised string key constants |
| `mobile/lib/core/network/auth_token_provider.dart` | `FirebaseAuthTokenProvider` with single-flight refresh |

### Auth Domain
| File | Purpose |
|---|---|
| `mobile/lib/features/auth/domain/entities/auth_user.dart` | Immutable auth user (server-authoritative role) |
| `mobile/lib/features/auth/domain/entities/otp_session.dart` | OTP session entity + `OtpState` enum |
| `mobile/lib/features/auth/domain/entities/user_profile.dart` | Minimal Firestore user profile entity |
| `mobile/lib/features/auth/domain/repositories/auth_repository.dart` | Domain contract |
| `mobile/lib/features/auth/domain/use_cases/request_otp_use_case.dart` | Phase 1.6 §4 |
| `mobile/lib/features/auth/domain/use_cases/verify_otp_use_case.dart` | |
| `mobile/lib/features/auth/domain/use_cases/resend_otp_use_case.dart` | |
| `mobile/lib/features/auth/domain/use_cases/restore_session_use_case.dart` | App restart recovery |
| `mobile/lib/features/auth/domain/use_cases/refresh_session_use_case.dart` | 401 recovery |
| `mobile/lib/features/auth/domain/use_cases/logout_use_case.dart` | |
| `mobile/lib/features/auth/domain/use_cases/get_current_user_use_case.dart` | |

### Auth Data
| File | Purpose |
|---|---|
| `mobile/lib/features/auth/data/data_sources/firebase_auth_data_source.dart` | Firebase Auth wrapper (all Firebase calls isolated here) |
| `mobile/lib/features/auth/data/data_sources/auth_remote_data_source.dart` | Cloud Run API: register + me |
| `mobile/lib/features/auth/data/models/user_profile_model.dart` | JSON DTO for `GET /v1/auth/me` |
| `mobile/lib/features/auth/data/repositories/auth_repository_impl.dart` | Repository implementation |

### Auth Presentation
| File | Purpose |
|---|---|
| `mobile/lib/features/auth/presentation/view_models/auth_view_state.dart` | `AuthStatus` enum + `AuthFlowState` sealed class hierarchy |
| `mobile/lib/features/auth/presentation/view_models/auth_view_model.dart` | OTP flow ViewModel with cooldown timer |
| `mobile/lib/features/auth/presentation/view_models/auth_state_notifier.dart` | Global auth status for route guards |
| `mobile/lib/features/auth/presentation/views/phone_entry_view.dart` | Phone number entry screen |
| `mobile/lib/features/auth/presentation/views/otp_entry_view.dart` | OTP code entry + resend countdown |

### Onboarding Foundation
| File | Purpose |
|---|---|
| `mobile/lib/features/onboarding/presentation/views/onboarding_placeholder_view.dart` | Phase 2 placeholder; full flow deferred |

### Router / DI / Entry
| File | Purpose |
|---|---|
| `mobile/lib/app/router/routes.dart` | Added `/auth/phone`, `/auth/otp`, `/onboarding` routes |
| `mobile/lib/app/router/route_guards.dart` | `AuthRouteGuard` with 5-state auth guard logic |
| `mobile/lib/app/router/app_router.dart` | Wired guard into `createAppRouter` |
| `mobile/lib/app/app.dart` | `appRouterProvider` now watches `authStateNotifierProvider` |
| `mobile/lib/app/di/providers.dart` | Full Phase 2 provider graph |
| `mobile/lib/main.dart` | `Firebase.initializeApp()` before `runApp` |

### Tests
| File | Type |
|---|---|
| `test/features/auth/domain/otp_session_test.dart` | Unit — state, cooldown, lock |
| `test/features/auth/domain/auth_failure_mapping_test.dart` | Unit — all Firebase + HTTP error codes |
| `test/features/auth/domain/auth_token_provider_test.dart` | Unit — single-flight refresh |
| `test/features/auth/domain/auth_user_test.dart` | Unit — entity equality, role helpers |
| `test/features/auth/presentation/auth_view_model_test.dart` | Unit — OTP flow state transitions |
| `test/features/auth/security/auth_security_test.dart` | Security — MVVM boundaries, no token logging, read-only role |
| `test/app/auth_router_test.dart` | Routing — all required routes registered |

---

## Files Modified

| File | Change |
|---|---|
| `mobile/pubspec.yaml` | Added `firebase_core`, `firebase_auth`, `flutter_secure_storage` |
| `mobile/lib/core/errors/app_failure.dart` | Added 8 auth-specific failure variants |
| `mobile/lib/core/errors/failure_mapper.dart` | Added `fromFirebaseAuthException()` + HTTP auth error code mapping |
| `mobile/lib/core/network/api_client.dart` | 401 single-flight refresh → single retry interceptor |
| `mobile/lib/core/network/auth_token_provider.dart` | Replaced placeholder with `FirebaseAuthTokenProvider` |
| `mobile/lib/core/storage/secure_storage.dart` | Replaced `InMemorySecureStorage` placeholder with `FlutterSecureStorageImpl` |
| `mobile/lib/core/storage/storage.dart` | Export `storage_keys.dart` |
| `mobile/test/features/mvvm_layer_test.dart` | Extended view list to include Phase 2 views |

---

## API Contracts Used

Per `docs/architecture-final/04-api-contracts.md`:
- `POST /v1/auth/register` — first-time user document creation; idempotent; idempotency key = `register_{uid}`
- `GET /v1/auth/me` — load user profile after sign-in

Firebase Auth contracts:
- `verifyPhoneNumber` — initiates SMS OTP
- `signInWithCredential(PhoneAuthProvider.credential(...))` — verify code
- `User.getIdToken(forceRefresh)` — token refresh

---

## OTP State Machine (Phase 1.6 §4)

```
phoneEntry
  → requestingOtp (request in flight)
  → otpSent       (SMS delivered)
  → verifyingOtp  (verify in flight)
  → authenticated (server confirmed)
  → error         (any failure; previous state preserved for retry)

resend:
  otpSent → resendingOtp → otpSent (new session, 30s cooldown starts)
  otpSent → resendCooldown (if cooldown active)

cooldown countdown: 1s tick timer in ViewModel; drives resend button disable + "Xs" label

Server limits (authoritative; not enforced by client):
  maxAttempts  = 5    | lock duration  = 15 min
  maxResends   = 3    | resend cooldown = 30 s
  OTP expiry   = 5 min
  per-IP       = 10 OTP req/hr, 3 concurrent open sessions
```

Client actions on server error codes:
- `INVALID_OTP` / `invalid-verification-code` → `InvalidOtpFailure` → error state (session remains)
- `code-expired` / `OTP_EXPIRED` → `OtpExpiredFailure` → error state
- `too-many-requests` → `TooManyAttemptsFailure` → error state  
- `user-disabled` → `AccountDisabledFailure` → error state with disabled banner
- `network-request-failed` → `NetworkFailure` → error state (retryable)

---

## Security Controls

- Firebase client config contains only public API keys — no server secrets, no service account, no Admin SDK.
- OTP codes, tokens, and auth headers are **never logged**. `AppLogger` calls carry only `op` and `result` metadata.
- Custom claims (`role`, `driverStatus`) are server-set. `AuthUser` fields are `final`, there is no client setter, **and they are not `copyWith` parameters** — so no client code path can mint a user with an elevated role.
- `profileComplete` is read verbatim from `GET /v1/auth/me` and is never recomputed on the client. An absent flag fails closed to `false`, routing the user to onboarding.
- Firebase Auth owns the authenticated session and the ID/refresh token lifecycle. `FlutterSecureStorage` (Keychain/Keystore) holds **only the in-flight OTP handshake**, because Firebase does not retain the `verificationId` across a process kill. No token, uid, or session mirror is stored, so there is no second copy that can go stale or outlive sign-out.
- Single-flight refresh guard prevents 401-storm token refresh races.
- Route guards block unauthenticated and onboarding-incomplete users from reaching protected routes.
- `mvvm_layer_test.dart` and `auth_security_test.dart` enforce layer boundaries automatically in CI.

---

## Token Lifecycle

```
Sign-in:
  verifyPhoneNumber → codeSent → verificationId (stored in OtpSession)
  signInWithCredential → UserCredential
  getIdToken(false) → bearer token (Firebase SDK caches, auto-refreshes)

Authenticated request:
  ApiClient interceptor → getAccessToken() → Bearer token injected

401 received:
  interceptor → FirebaseAuthTokenProvider.forceRefresh() (single-flight)
  → getIdToken(true) → new token
  → retry original request once (_retried flag prevents loop)
  → the retry carries the freshly refreshed token: onRequest deliberately
    skips re-injecting the cached token when _retried is set, otherwise the
    retry would resend the stale token and fail identically
  → if refresh fails → propagate error → caller clears session

Concurrency:
  N simultaneous 401s → exactly ONE getIdToken(true) call; every other
  caller awaits the same in-flight Future and then retries. Verified at the
  interceptor level, not only on the token provider.

Logout:
  Firebase.signOut() + SecureStorage.deleteAll()
  → authStateChanges emits null → AuthStatus.unauthenticated → guard sends
    the user to /auth/phone. No stale credential survives, because the only
    persisted auth artefact is the OTP handshake and deleteAll() clears it.
```

---

## Routing Behaviour

```
AuthStatus.unknown        → stay on /  (splash, session check in progress)
AuthStatus.unauthenticated → /auth/phone
AuthStatus.authenticated   → /home (profile fetch determines onboarding; see below)
AuthStatus.onboardingRequired → /onboarding
AuthStatus.authenticatedReady → /home

Authenticated user on /auth/* → redirected to /home
App restart with valid session → restoreSession() → authStateChanges fires → home
App restart with expired token → refreshToken() fails → logout() → unauthenticated

/auth/otp requires an in-flight OTP session:
  no session (deep link, or a back-stack entry restored after a process kill)
    → /auth/phone
  session present (OtpSent / Verifying / Resending / ResendCooldown)
    → allowed
  rejected code (AuthFlowError wrapping an OTP-bearing state)
    → allowed, so the error is readable instead of bouncing to phone entry
  already signed in
    → /home

Onboarding completion is a state transition, not a navigation call. The
placeholder View reports intent to OnboardingViewModel, which promotes
AuthStatus; the guard then chooses the destination. The View cannot move the
user to /home while the auth state still says onboarding is required.
```

---

## Tests

Counts below include the Phase 2 correction pass (see
`## Phase 2 Correction Pass` at the end of this document).

| Category | Count | Result |
|---|---|---|
| OTP session unit | 7 | ✅ |
| Auth failure mapping | 14 | ✅ |
| Token provider (single-flight, unit) | 5 | ✅ |
| 401 refresh + retry + concurrency (interceptor integration) | 6 | ✅ |
| AuthUser entity | 6 | ✅ |
| AuthViewModel flow | 7 | ✅ |
| AuthStateNotifier (startup + transitions) | 9 | ✅ |
| AuthRepositoryImpl (verify, storage, logout, restore, registration) | 17 | ✅ |
| AuthRouteGuard (all statuses + OTP deep-link block) | 22 | ✅ |
| UserProfileModel (`profileComplete` contract) | 6 | ✅ |
| OnboardingViewModel | 3 | ✅ |
| Security (MVVM boundaries, no token log, immutable claims) | 12 | ✅ |
| Auth router registration | 1 | ✅ |
| Phase 1 retained tests | 16 | ✅ |
| **Total** | **131** | **✅ All pass** |

---

## Build Verification

| Check | Result |
|---|---|
| `flutter pub get` | ✅ |
| `dart run build_runner build --delete-conflicting-outputs` | ✅ (3 outputs) |
| `flutter analyze` | ✅ No issues found (exit 0) |
| `flutter test` | ✅ 131/131 passed |
| `flutter build apk --debug` | Not verified (no google-services.json; requires Firebase project) |
| `flutter build ios --no-codesign` | Not verified (no GoogleService-Info.plist) |

> **Note:** Android/iOS builds require a real Firebase project configuration (`google-services.json` / `GoogleService-Info.plist`). These files are gitignored per security policy and must be placed in `mobile/android/app/` and `mobile/ios/Runner/` respectively before running a device build. The code compiles and analyzes cleanly against the SDK; the build step fails only at the Firebase plugin's resource merge step when config files are absent.

---

## Known Limitations

1. **Firebase config files absent** — device builds require real Firebase project setup (Phase 3 ops task).
2. **App Check not initialized** — Phase 1.6 §2 specifies App Check (`DeviceCheck`/`Play Integrity`). Integrated in post-Phase 2 ops step when firebase config is present.
3. **Google/Apple Sign-In deferred** — architecture defines them; Phase 2 implements only phone OTP per scope.
4. **Full onboarding flow deferred** — `OnboardingPlaceholderView` holds the route. Full passenger/driver onboarding (CNIC, vehicle docs) is Phase 4.
5. **`GET /v1/auth/me` profile fetch** — not yet called automatically after sign-in. `AuthStateNotifier` stays at `authenticated`; caller must promote to `authenticatedReady` / `onboardingRequired`. This will be wired in Phase 3 when the home shell profile loader is implemented.

---

## Architecture Deviations

None. The implementation strictly follows the frozen Phase 1.6 contracts and Phase 1 MVVM/Clean Architecture patterns. No new patterns were introduced.

---

## Phase 2 Correction Pass

The Phase 2 verification gate returned **PASS WITH FIXES**. The findings below
were closed. No feature scope was added.

### Closed findings

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 1 | HIGH | `AuthUser.copyWith` exposed writable `role` / `driverStatus`, giving client code a way to mint an elevated role | Both removed from the parameter list; they now carry over from the constructor only. A security test asserts they can never reappear. |
| 2 | MEDIUM | `/auth/otp` was reachable by deep link with no OTP session, leaving a dead-end screen | `AuthRouteGuard` now requires an in-flight OTP session for that route and matches on `uri.path`, so query strings cannot slip past. |
| 3 | MEDIUM | `StorageKeys.authUid` was written on every sign-in and never read | Key and write removed. Firebase Auth is the single owner of session persistence. |
| 4 | MEDIUM | `OnboardingPlaceholderView` called `context.go(home)`, bypassing the auth state machine and risking a redirect loop | Added `OnboardingViewModel`, which promotes `AuthStatus`; the guard performs navigation. The View no longer imports `go_router`. |
| 5 | LOW | `profileComplete` was inferred client-side from `role`/`isActive`/`banned` | `GET /v1/auth/me` response contract frozen with an explicit `profileComplete`; the DTO reads it verbatim and fails closed to `false`. |
| 6 | LOW | `flutter analyze` exited non-zero on an unused test import | Import removed; analyzer is clean at exit 0. |

### Defect found while adding the required 401 test

Writing the interceptor integration test required by the gate exposed a defect
that no existing test could have caught:

- **`api_client.dart`** — the 401 retry re-entered `onRequest`, which
  overwrote the freshly refreshed bearer token with the cached one. The retry
  therefore resent the stale token and failed with the same 401. The explicit
  `Authorization` header set on the retry options was dead code.
- The retry now keeps the refreshed token: `onRequest` skips token injection
  when `extra['_retried']` is set and an `Authorization` header is already
  present.
- This would have masked itself in production, because Firebase updates its
  own token cache during `getIdToken(true)` — so recovery depended on an
  undocumented SDK side effect rather than on the token just fetched.

### Token ownership (re-verified, unchanged by design)

| Concern | Owner |
|---|---|
| Identity, session persistence, ID/refresh token lifecycle | Firebase Auth |
| Business/application authority, roles, profile completeness | Ora backend (Firestore durable truth) |
| `flutter_secure_storage` | In-flight OTP handshake only (`otpSessionId`, `otpPhoneE164`) |

Firebase's token lifecycle is **not** duplicated. The client never stores an ID
token or refresh token, and `refreshToken()` delegates to
`getIdToken(forceRefresh: true)` rather than managing a refresh token itself.

### Verification after the correction pass

- `flutter analyze` — no issues, exit 0
- `flutter test` — 131/131 passed (65 before, +66 added)
- `mvvm_layer_test.dart` and `auth_security_test.dart` still pass, so no layer
  boundary regressed.

---

## Next Phase

**Phase 3 — Firebase Project Setup + App Check + Passenger Home Shell**  
(per `docs/ORA_MASTER_PLAN.md` and `docs/architecture-final/02-feature-inventory.md`)

Do not begin Phase 3 until Phase 2 is reviewed and accepted.
