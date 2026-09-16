# Phase 2C — Auth & Onboarding Closure

**Status:** CLOSED (auth/onboarding foundation only)  
**Date:** 2026-09-08  
**Does not claim:** production-ready, Maps, rides, or Console-enforced App Check

This phase closes the authentication/onboarding loop so a new user can reach home through **server-authoritative** profile state, and an existing completed user can restore a session to home.

Do not start Maps or rides from this document.

---

## Unexpected differences vs the Phase 2C prompt (pre-implementation)

Confirmed from the repository before changing code:

1. Completeness already required a non-empty `displayName`, but register always wrote `displayName: null` — new users could not leave onboarding.
2. Firestore rules allowed client `update` of `users/{uid}` if some protected fields were unchanged; **`isActive` was not protected**.
3. Android `verificationCompleted` completed with a fabricated session id `"auto"` and dropped `PhoneAuthCredential`.
4. `SplashView` previously competed with `AuthRouteGuard` for `/home`.
5. Successful OTP verify **and** profile bootstrap both called register; register errors were swallowed on the client.
6. The client already sent `X-Request-Id`; the backend ignored it.
7. CI ran Flutter only.
8. `FailureMapper` treated HTTP 400 as a generic network failure (now validation).
9. `appRouterProvider` watched auth status and **recreated** `GoRouter` (now `refreshListenable`).
10. Durable local storage for ride idempotency is **not** required by this phase. `InMemoryLocalStorage` remains. **Ride mutation prerequisite — not yet implemented.**

---

## Locked architecture (unchanged)

| Concern | Owner |
|---|---|
| Identity | Firebase Auth uid (ID token) |
| Profile / `profileComplete` / bans | auth-service + Firestore Admin SDK |
| Client user document writes | **Denied** |
| OTP | Firebase Phone Auth (ADR-016) |
| Navigation destination | `AuthRouteGuard` only |

Flutter does not use the Firestore SDK. Flutter does not write `users/{uid}`.

---

## Profile API

`PATCH /v1/auth/profile`

- Identity: verified Firebase ID token → `caller.uid` only.
- Body: `{ "displayName": string }` only. Extra keys (including `uid`, `role`, `isActive`, `banned`, `profileComplete`) are **rejected**.
- Persistence: Admin SDK transaction updates **only** `displayName` and `updatedAt`, then derives `profileComplete`.
- Response: same public profile JSON as `GET /v1/auth/me`.
- Request correlation: valid `X-Request-Id` is echoed; otherwise a UUID is generated. Included on error bodies. Tokens/OTPs are not logged.

---

## Client flow

New user:

Phone → OTP (manual or Android auto-credential sign-in) → Firebase session → **one** `POST /register` during bootstrap → `/me` → onboarding → `PATCH /profile` → `/me` refresh → `authenticatedReady` → guard → home.

Existing complete user:

Restore Firebase session → register (idempotent) + `/me` → home.

Banned / inactive: bootstrap logs out; guard sends the user to phone entry.

Logout from home: `HomeShellView` → `HomeViewModel` → `LogoutUseCase` → Firebase sign-out. Guard reacts to `AuthStatus.unauthenticated`. No `context.go`.

---

## Android auto-verification

Option A: `verificationCompleted` signs in with the real `PhoneAuthCredential` via `PhoneVerificationCoordinator`. It never invents `"auto"`.

Manual SMS, resend, timeout, and error callbacks remain. A late auto-retrieval after `codeSent` still signs in (does not complete the coordinator future a second time).

**Physical Android device verification is still required** for Play Services instant verification. Unit tests cover coordinator logic only.

---

## Register calls

| Path | Register? |
|---|---|
| `verifyOtp` | No |
| Android auto-sign-in | No (bootstrap still registers once) |
| `ResolveAuthProfileUseCase` | Yes, once per bootstrap |
| After `PATCH /profile` | No — `refreshCanonicalProfile` is `/me` only |
| Duplicate / retry / old client | Server register remains idempotent (`Idempotency-Key: register_{uid}`) |

---

## CI

| Job | What it proves |
|---|---|
| `flutter` | `pub get`, build_runner, `analyze`, unit/widget tests, debug APK **if** `google-services.json` is in the checkout |
| `auth-service` | auth-service Vitest suite (profile, auth, request id, rules contract, production guards) |
| `firestore-rules` | Firebase emulator + Mocha rules tests (needs Node 20 + Java 21) |

If the emulator job cannot start, that is an environment failure — do not treat a skipped job as a pass.

---

## Durable storage

`InMemoryLocalStorage` is unchanged.

**Ride mutation prerequisite — not yet implemented.** In-memory keys cannot survive process death and must not be used for ride or payment idempotency.

Hive was not added.

---

## What this phase does not prove

- Physical Android auto-verification / Play Integrity
- Firebase Console App Check Enforce
- Staging/production deploy of auth-service
- Real SMS on a billed Firebase project
- Ride, maps, realtime, dispatch, pricing, or payments
