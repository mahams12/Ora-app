# Ora Complete Architecture Audit

**Audit type:** Read-only snapshot (source, configuration, tests, documentation)  
**Date:** 2026-09-08  
**Status:** Historical snapshot from before Phase 2C. Current auth/onboarding closure is documented in `docs/implementation/phase-02c-auth-onboarding-closure.md`. Do not treat this file as live implementation status.  
**Repository:** `/Users/jazimsaeed/Desktop/Ora App`  
**Firebase project (from env example / tests):** `ora-app-d8112`  
**Android / iOS application id:** `com.ora.ora`  
**Live E2E executed during this audit:** **NO**  
**Firebase Console inspected during this audit:** **NO**  
**Tests re-run during this audit:** **NO** (inventory from files only)

Evidence rule: conclusions cite file path, class/function, or configuration. Architecture documents are treated as **reference**, not truth.

---

## 1. Executive Summary

Ora is **not** a ride-hailing product yet. It is a **Phase 1–2B authentication and security foundation** with an unusually complete *paper* architecture for a future P2P offered-fare marketplace.

What actually exists in code:

1. A Flutter app (`mobile/`) with MVVM + Riverpod + go_router, design-system primitives, phone OTP via Firebase Auth, App Check wiring, and two REST calls: `POST /auth/register` and `GET /auth/me`.
2. One backend service (`backend/auth-service/`): Node 20 + Express on port 8080, Firebase Admin, Firestore `users/{uid}` only.
3. Fail-closed Firestore security rules plus an empty index file.
4. CI that builds/tests **Flutter only**.

What does **not** exist in code (despite extensive documentation):

- Ride engine, pricing service, location service, notification service
- Cloud Functions directory
- Redis / Memorystore
- RTDB (no rules file, no SDK usage)
- Pub/Sub
- FCM
- Cloud Storage
- Maps / Geolocator / Places / Routes
- Fare calculation
- Dispatch / matching
- Ride assignment transactions
- Payments, wallets, payouts
- Driver onboarding, documents, online/offline
- Passenger ride UI beyond a home placeholder

**Production readiness:** **NOT READY.** The auth path is the only implementable product slice, and even that cannot complete onboarding without a server-writable `displayName` (users stay on a placeholder that cannot promote them to home).

**Highest-confidence one-line status:** *Ora today is a well-structured phone-auth app sitting in front of a documented-but-unbuilt ride marketplace.*

---

## 2. Actual Project Status

| Layer | Actual status | Confidence |
| ----- | ------------- | ---------- |
| Architecture documentation | Extensive, frozen Phase 0–1.6 + ADRs | HIGH |
| Flutter foundation (MVVM, theme, router, Dio) | Implemented | HIGH |
| Phone OTP + session restore + `/register` + `/me` | Implemented | HIGH |
| App Check client + optional server verify + production start guards | Partial (wired; Console Enforce unproven) | HIGH (code) / LOW (Console) |
| Onboarding (name, CNIC, vehicle, docs) | Placeholder only; completeness rule blocks home | HIGH |
| Passenger ride product | Not implemented | HIGH |
| Driver product | Not implemented | HIGH |
| Maps / GPS | Interface stubs only; packages not in `pubspec.yaml` | HIGH |
| Fare / dispatch / assignment / payments / safety | Not implemented | HIGH |
| Redis / RTDB / Pub/Sub / Functions / FCM / Storage | Not implemented | HIGH |

### Repository layout (actual)

```
/
├── mobile/                 Flutter app (only client)
├── backend/auth-service/   Only backend service
├── docs/                   Architecture + implementation reports (dominant by volume)
├── test/firestore.rules.test.mjs
├── firebase.json           Firestore rules + emulator only
├── firestore.rules
├── firestore.indexes.json  empty
├── .github/workflows/ci.yml  Flutter CI only
├── package.json            Firestore rules test runner
└── (NO functions/, NO ride-engine/, NO RTDB rules, NO storage.rules)
```

`docs/ORA_MASTER_PLAN.md` still describes `backend/ride-engine`, `location-service`, `pricing-service`, `notification-service`, and `functions/`. None of those directories exist.

---

## 3. Actual Technology Stack

### Flutter (declared in `mobile/pubspec.yaml`)

| Package | Declared | Purpose in *this* repo |
| ------- | -------- | ---------------------- |
| Flutter SDK | SDK | UI |
| Dart SDK | `^3.9.2` | Language |
| `flutter_riverpod` `^2.6.1` | Used | DI + ViewModels |
| `go_router` `^14.6.2` | Used | Navigation + auth guards |
| `dio` `^5.7.0` | Used | HTTP to auth-service |
| `freezed_annotation` `^2.4.4` | Used | `AppFailure`, splash/view states |
| `firebase_core` `^4.13.0` | Used | Init in `main.dart` |
| `firebase_auth` `^6.5.7` | Used | Phone OTP, session |
| `firebase_app_check` `^0.4.1+4` | Used | Optional App Check |
| `flutter_secure_storage` `^10.3.1` | Used | OTP handshake keys only |
| `uuid` `^4.5.1` | Used | Request IDs |
| `riverpod_annotation` / `riverpod_generator` | **Declared, unused** | No `@riverpod` codegen |
| `geolocator` / `google_maps_flutter` / `cloud_firestore` / `firebase_database` / `firebase_messaging` / `firebase_storage` / `hive` | **Absent** | — |

### Backend (`backend/auth-service/package.json`)

| Package | Purpose |
| ------- | ------- |
| Node `>=20` | Runtime |
| `express` `^4.21.2` | HTTP |
| `firebase-admin` `^13.0.2` | Auth verify + Firestore Admin |
| `uuid` `^11.0.5` | Declared; **no usage in `src/`** |
| `vitest` + `supertest` | Unit/HTTP tests |

### Firebase (repo config)

| Service | Repo evidence |
| ------- | ------------- |
| Authentication | Mobile SDK + Admin `verifyIdToken` |
| App Check | Client activate + optional Admin verify |
| Cloud Firestore | Admin writes `users/{uid}`; `firestore.rules` deployed-from-repo |
| Firestore emulator | `firebase.json` port **8181** |
| RTDB | **No `database.rules.json`; not in `firebase.json`** |
| Storage | **No `storage.rules`** |
| Cloud Functions | **No `functions/`** |
| FCM / Crashlytics / Analytics | **Not in mobile pubspec** |
| Secret Manager | **Not used**; local `GOOGLE_APPLICATION_CREDENTIALS` file |

### CI / Docker

- `.github/workflows/ci.yml`: `flutter pub get` → `build_runner` → `analyze` → `test` → `apk --debug`. **Does not run auth-service tests or Firestore rules tests.**
- `backend/auth-service/Dockerfile`: multi-stage Node 20, non-root `USER node`, `EXPOSE 8080`. No compose, no Cloud Run IaC, no deploy workflow.

---

## 4. Actual Repository Architecture

```
Flutter (Android/iOS)
  Firebase Auth (phone OTP) + optional App Check
        │  Authorization: Bearer <ID token>
        │  X-Firebase-AppCheck (when enabled)
        ▼
  auth-service :8080  (Express, Cloud Run–shaped)
        │  Admin SDK
        ▼
  Firestore  users/{uid}
```

That is the **entire implemented system**. Everything else in `docs/ORA_MASTER_PLAN.md` (Ride Engine, Redis GEO, RTDB, Pub/Sub, FCM, Maps) is **planned documentation**, not running software.

**Confidence: HIGH**

---

## 5. Frontend Architecture

### Pattern actually used

**Clean Architecture + MVVM + Riverpod (manual providers), not codegen.**

Actual dependency flow for the only real feature (auth):

```
View (ConsumerWidget)
  → Notifier / ViewModel
    → UseCase (thin delegate)
      → AuthRepository (interface)
        → AuthRepositoryImpl
          → FirebaseAuthDataSource   (Firebase Auth SDK)
          → AuthRemoteDataSource     (Dio → /auth/register, /auth/me)
          → SecureStorage            (OTP session keys)
```

Evidence:

- Composition root: `mobile/lib/app/di/providers.dart`
- Views must not import Dio/Firebase: `mobile/test/features/mvvm_layer_test.dart`, `mobile/test/features/auth/security/auth_security_test.dart`
- Use cases are one-line wrappers except `ResolveAuthProfileUseCase` (`register` then `/me`)

### Feature inventory (code, not docs)

| Feature folder | Reality |
| -------------- | ------- |
| `features/auth/` | Full stack: 3 screens, OTP VM, global `AuthStateNotifier`, 9 use cases, Firebase + REST data sources |
| `features/onboarding/` | `OnboardingPlaceholderView` + VM that only re-calls `/me` |
| `features/passenger/` | `HomeShellView` — design-system demo, **no ride logic** |
| `features/driver/driver.dart` | `library;` stub (“Phase 6+”) |
| `features/ride/ride.dart` | `library;` stub (“Phase 7+”) |
| `features/maps/maps.dart` | `library;` stub (“Phase 4+”) |
| `features/payments/payments.dart` | `library;` stub (“Phase 11+”) |
| `features/safety/safety.dart` | `library;` stub (“Phase 12+”) |

### Navigation

Five routes in `mobile/lib/app/router/app_router.dart`:

| Path | Screen |
| ---- | ------ |
| `/` | `SplashView` |
| `/auth/phone` | `PhoneEntryView` |
| `/auth/otp` | `OtpEntryView` |
| `/onboarding` | `OnboardingPlaceholderView` |
| `/home` | `HomeShellView` |

`AuthRouteGuard` (`route_guards.dart`) is real and fail-closed: home is granted only for `AuthStatus.authenticatedReady`.

### Local persistence

| Store | Implementation in DI | Used for |
| ----- | -------------------- | -------- |
| Secure storage | `FlutterSecureStorageImpl` | `otp_session_id`, `otp_phone_e164` |
| Local storage | **`InMemoryLocalStorage`** | Nothing durable; comment says Hive in “Phase 3+” |
| Firebase Auth | SDK | Session / ID token / refresh |

Tokens are **not** mirrored to secure storage (`storage_keys.dart` comments + security tests).

### Architecture violations (actual)

1. **`providers.dart` calls `FirebaseAuth.instance.currentUser?.getIdToken()` directly** — bypasses `FirebaseAuthDataSource` (the stated isolation boundary in `firebase_auth_data_source.dart`).
2. **`main.dart` calls `FirebaseAuth.instance.setSettings(...)`** in debug — acceptable as bootstrap, still outside the data source.
3. **`SplashView` navigates to `/home` on local bootstrap load** (`splash_view.dart`) while the guard simultaneously owns destination. Dual navigation authority.
4. **`PhoneEntryView` pushes OTP** (view-owned navigation). Onboarding view correctly does *not* navigate.
5. **Stale comments:** `router.dart` still says guards land in Phase 3; `auth_token_provider.dart` still says “no auth yet”.
6. **`AuthUser` comments claim Firebase custom claims for `role` / `driverStatus`.** Mapping in `_mapFirebaseUser` never sets them. Role lives on the Firestore user doc via `/me`, not JWT claims. No Admin `setCustomUserClaims` exists in auth-service.

### What is good and should be kept

- View → ViewModel → UseCase → Repository layering for auth
- Guard reads server-derived `profileComplete`, not local flags
- `AuthUser.copyWith` cannot set `role` / `driverStatus`
- Fail-closed splash when `/me` fails (`AuthStatus.authenticated` holds splash)
- Banned / inactive accounts force logout in `AuthStateNotifier._bootstrapProfile`

**Frontend confidence: HIGH**

---

## 6. Backend Architecture

### Services that exist

**One:** `ora-auth-service`.

| Attribute | Value | Evidence |
| --------- | ----- | -------- |
| Runtime | Node ≥ 20 | `package.json` `engines` |
| Language | TypeScript → CommonJS | `tsconfig.json` |
| Framework | Express 4 | `src/app.ts` |
| Entry | `src/index.ts` | `main()` |
| Port | `PORT` or **8080** | `index.ts`, Dockerfile |
| Deployment model | Dockerfile present; **no deploy pipeline in repo** | `backend/auth-service/Dockerfile` |
| Auth | Bearer Firebase ID token, `verifyIdToken(token, true)` | `middleware/auth.ts` |
| App Check | Optional `X-Firebase-AppCheck`; production start refuses if off | `auth.ts`, `production_guards.ts` |
| Database | Firestore Admin, collection `users` | `services/users.ts` |
| Logging | `console.log` / `console.error` only | `index.ts` |
| CORS / Helmet | **Not configured** | `app.ts` |
| Request IDs | Client sends `X-Request-Id`; **backend ignores it** | mobile `ApiClient` vs `app.ts` |

### Implemented routes

| Method | Path | Auth | Behavior |
| ------ | ---- | ---- | -------- |
| GET | `/healthz` | none | `{ ok, service: "ora-auth-service" }` |
| POST | `/v1/auth/register` | Bearer + optional App Check | Transactional create `users/{uid}`; identity from token |
| GET | `/v1/auth/me` | Bearer + optional App Check | Read own user; derive `profileComplete` |

**404** for every other path (`app.ts` catch-all).

### Documented vs implemented backend

| Planned component | Status |
| ----------------- | ------ |
| Auth API | **IMPLEMENTED** (2 endpoints) |
| Ride Engine (`POST /v1/rides`, offers, select, start, …) | **NOT IMPLEMENTED** |
| Pricing Service | **NOT IMPLEMENTED** |
| Location Service | **NOT IMPLEMENTED** |
| Notification Dispatcher | **NOT IMPLEMENTED** |
| Admin API (`/v1/admin/*`) | **NOT IMPLEMENTED** |
| Outbox projector | **NOT IMPLEMENTED** |
| Redis GEO | **NOT IMPLEMENTED** — comment only in `rate_limit.ts` |
| Pub/Sub | **NOT IMPLEMENTED** — no `@google-cloud/pubsub` |
| Cloud Functions | **NOT IMPLEMENTED** — no `functions/` |
| FCM | **NOT IMPLEMENTED** |

**Backend confidence: HIGH**

---

## 7. Database Architecture

### ACTUAL DATABASE SCHEMA (from code)

#### `users/{uid}` — the only collection written by application code

| Field | Set by | Client-writable via API? | Client-writable via Firestore rules? |
| ----- | ------ | ------------------------ | ------------------------------------ |
| `uid` | Server register | No (token) | Update **denied** (protected) |
| `phoneNumber` | Server from token | No | Update **denied** |
| `displayName` | Server `null` on create | **No API to set it** | Update **allowed** |
| `role` | Server `'passenger'` | No | Update **denied** |
| `driverStatus` | Server `'none'` | No | Update **denied** |
| `isActive` | Server `true` | No API | Update **ALLOWED** (not in protected list) |
| `banned` | Server `false` | No | Update **denied** |
| `createdAt` / `updatedAt` | Server ISO strings | No | `createdAt` denied; `updatedAt` not protected |
| `profileComplete` | **Not stored** — derived in `deriveProfileComplete()` | n/a | n/a |

**Who reads:** auth-service `getMe`; Flutter via REST only (no Firestore SDK).  
**Who writes:** auth-service `registerUser` transaction.  
**Who deletes:** nobody in code; rules deny client delete.  
**Indexes:** none (`firestore.indexes.json` is `{ "indexes": [], "fieldOverrides": [] }`).  
**TTL:** none.

#### `savedPlaces/{placeId}`

Present **only in security rules**. No Flutter or backend code reads/writes it. Rules allow owner CRUD if `ownerUid` matches.

#### Collections named in rules but unused by any service

`drivers`, `vehicles`, `driverDocuments`, `rides`, `rideOffers`, `rideEvents`, `outboxEvents`, `idempotencyRecords`, `pricingRules`, `pricingSnapshots`, `feePolicies`, `paymentIntents`, `paymentAttempts`, `paymentProviderCallbacks`, `walletAccounts`, `walletLedgerEntries`, `driverPayouts`, `refunds`, `reconciliationRecords`, `ratings`, `safetyEvents`, `supportTickets`, `supportTicketMessages`, `reports`, `blocks`, `tripShareTokens`, `consentRecords`, `adminAuditLogs`, `moderationCases`, `notificationReceipts`, `otpSessions`.

These are **deny-all placeholders**, not a live schema.

### Schema vs documentation

| Issue | Severity |
| ----- | -------- |
| `docs/database/firestore-schema.md` describes 20+ collections that **no code uses** | HIGH (doc drift) |
| Rules protect `accountStatus`; backend writes `isActive` / `banned` — field name mismatch | MEDIUM |
| `isActive` is **not** in `userProtectedFieldsUnchanged()` — a Firestore SDK client could flip it | HIGH (latent) |
| `displayName` client-updatable in rules, but the app has **no** Firestore SDK and **no** PATCH profile API — onboarding cannot complete | HIGH (product) |
| Custom claims documented; never written | MEDIUM |

**Database confidence: HIGH** for actual schema; **HIGH** that documented collections are unused.

---

## 8. Authentication

### Real flow (source)

```
main.dart
  Firebase.initializeApp()
  kDebugMode → appVerificationDisabledForTesting = true
  optional activateOraAppCheck()
  ProviderScope → OraApp → GoRouter `/`

AuthStateNotifier.build()
  subscribe AuthRepository.authStateChanges
  RestoreSessionUseCase
    FirebaseAuth.currentUser
    getIdToken(true)
    on failure → logout()

Unauthenticated → AuthRouteGuard → /auth/phone
PhoneEntryView → AuthViewModel.requestOtp
  PakistanPhoneNumber normalize E.164
  FirebaseAuthDataSource.verifyPhoneNumber
  persist verificationId + phone in SecureStorage
  push /auth/otp

OtpEntryView → verifyOtp
  PhoneAuthProvider.credential + signInWithCredential
  AuthRepositoryImpl._registerUser  POST /auth/register
  AuthStateNotifier → AuthStatus.authenticated
  ResolveAuthProfileUseCase
    POST /auth/register (again, idempotent)
    GET /auth/me
  if !isActive || banned → logout
  if profileComplete → authenticatedReady → /home
  else → onboardingRequired → /onboarding

Restart: Firebase session restore + same /me gate
401 API: ApiClient interceptor forceRefresh + one retry
Logout: FirebaseAuth.signOut + SecureStorage.deleteAll
```

Key files:

- `mobile/lib/main.dart`
- `mobile/lib/features/auth/presentation/view_models/auth_state_notifier.dart`
- `mobile/lib/features/auth/data/data_sources/firebase_auth_data_source.dart`
- `mobile/lib/features/auth/data/repositories/auth_repository_impl.dart`
- `mobile/lib/features/auth/domain/use_cases/resolve_auth_profile_use_case.dart`
- `backend/auth-service/src/middleware/auth.ts`
- `backend/auth-service/src/routes/auth.ts`
- `backend/auth-service/src/services/users.ts`
- `backend/auth-service/src/services/profile.ts`

### Completeness rule (blocks the product)

`deriveProfileComplete` requires `isActive && !banned && non-empty displayName`.  
Register always sets `displayName: null`.  
There is **no** `PATCH /v1/auth/me` or profile-update endpoint.  
`OnboardingViewModel.completePlaceholder()` only calls `retryProfileBootstrap()` — it **cannot** set a name.  
UI copy (“Tap below to proceed to the home shell”) is **false** for every new user.

**Status: PARTIAL / BROKEN for leaving onboarding.**

### Threat cases (code inspection, not live)

| Case | Current behavior | Confidence |
| ---- | ---------------- | ---------- |
| Body `uid` spoof on register | Ignored; token uid used (`routes/auth.ts`) | HIGH |
| `?userId=` on `/me` | Explicitly ignored | HIGH |
| Role spoof via API | Server writes `passenger`; no client write path | HIGH |
| Role spoof via Firestore client | Denied by rules | HIGH |
| Token expiry | 401 → client refresh once | HIGH (unit tested) |
| Token revocation | `verifyIdToken(_, true)` | HIGH (code + unit test) |
| Firebase-disabled user | Relies on `checkRevoked`; `caller.disabled` hardcoded `false` | MEDIUM |
| Firestore `banned` / `isActive` | Checked on register/me; client logs out | HIGH |
| Account deletion | **NOT IMPLEMENTED** | HIGH |
| Duplicate register | Firestore transaction skip-if-exists | HIGH |
| Concurrent register | Same transaction; **not load-tested against real Firestore** (in-memory mock in unit tests) | MEDIUM |
| API unavailable | Stay `authenticated` on splash (fail closed) | HIGH |
| Register HTTP error swallowed | `_registerUser` catches and logs; `/me` then 404 | MEDIUM |

### Android auto-verify defect

`FirebaseAuthDataSource.startPhoneVerification` `verificationCompleted` completes the completer with `'auto'` and **discards** the `PhoneAuthCredential`. `verifyOtpCode` later builds a credential from that fake verificationId. Instant Android SMS auto-retrieval can therefore fail.

**Status: BROKEN (path-specific).** Confidence: HIGH on code; **not live-reproduced** in this audit.

### Debug bypasses

- `appVerificationDisabledForTesting: true` when `kDebugMode` (`main.dart`)
- App Check debug providers when `kDebugMode` (`firebase_app_check_bootstrap.dart`)
- Debug Android cleartext HTTP (`android/app/src/debug/AndroidManifest.xml`)

These are gated to debug; release App Check / HTTPS guards exist in `AppConfig.fromEnvironment`.

**Auth confidence: HIGH** for the implemented path; **HIGH** that onboarding cannot complete.

---

## 9. Security

This is an implementation audit, not a re-score of the Phase 2B 30/30 matrix. Console state is **UNKNOWN**.

### CRITICAL

| ID | Finding | Evidence |
| -- | ------- | -------- |
| C1 | Firebase Console App Check **Enforce** / provider registration cannot be proven from the repo | `phase-02b-firebase-console-checklist.md`; no Console access this audit |
| C2 | Production App Check is a **process env contract**, not a deployed proof | `assertProductionSecurityConfig` only runs if `ORA_ENV`/`NODE_ENV=production` **and** the process actually starts with that env in Cloud Run |

### HIGH

| ID | Finding | Evidence |
| -- | ------- | -------- |
| H1 | Rate limiter is **in-memory `Map`**, explicitly “LOCAL ONLY — NOT PRODUCTION READY” for multi-instance Cloud Run | `backend/auth-service/src/middleware/rate_limit.ts` |
| H2 | Firestore rules allow client `update` of `isActive` (not in protected keys) | `firestore.rules` `userProtectedFieldsUnchanged` vs `users.ts` field |
| H3 | Onboarding completeness is `displayName`, but no authorized API writes it — users stuck **or** a raw Firestore client can set `displayName` and skip product onboarding | `profile.ts` + rules `displayName` allowed + no PATCH |
| H4 | Release Android signing still uses **debug keys** | `mobile/android/app/build.gradle.kts` |
| H5 | CI does not run backend or rules tests — regressions can ship on the security-critical service | `.github/workflows/ci.yml` |

### MEDIUM

| ID | Finding |
| -- | ------- |
| M1 | Unused Auth providers (Google, Email) documented as still enabled in Console — not in the Flutter app | Checklist; Console unverified here |
| M2 | No CORS/Helmet; acceptable for native-only, unsafe if a web client is added |
| M3 | Client still sends body `{ uid }` on register (ignored) | `auth_remote_data_source.dart` |
| M4 | `RATE_LIMIT_*` documented in `.env.example` but **not read** by `app.ts` (hardcoded 60/60s) |
| M5 | iOS Info.plist contains Firebase OAuth reversed client id (expected for phone auth; not a Maps key) |
| M6 | Native Firebase config files gitignored and absent from git — correct for hygiene, but CI `flutter build apk --debug` will fail without secrets injection |

### LOW / INFO

| ID | Finding |
| -- | ------- |
| L1 | No structured logging / request-id correlation on the server |
| L2 | `uuid` unused in auth-service |
| L3 | `caller.disabled = false` after successful verify |
| L4 | Firestore emulator tests exist at repo root but are not in CI |

### Client secrets

- No Maps API key in source (no Maps SDK).
- `google-services.json` / `GoogleService-Info.plist` gitignored (`.gitignore`).
- Service account JSON gitignored; local file may exist on disk (this audit does not print values).
- Tokens not logged (security tests scan auth domain).

### IDOR

Auth routes bind all reads/writes to `req.caller.uid` from the verified token. **No IDOR on implemented endpoints.** Confidence: HIGH.

There is **no** ride/payment API to IDOR yet.

**Security confidence: HIGH for implemented auth-service; LOW for Firebase Console / production deploy.**

---

## 10. Realtime Architecture

### What exists

| Mechanism | Present? |
| --------- | -------- |
| Firestore listeners (`snapshots()`) | **NO** — `cloud_firestore` not in pubspec; no Admin listeners |
| RTDB listeners | **NO** |
| WebSockets / SSE | **NO** |
| Polling loops | **NO** (except OTP **resend cooldown** `Timer.periodic` in `AuthViewModel`) |
| FCM | **NO** |
| Sequence / version / eventId on domain events | **NO** application events |

Firebase Auth `authStateChanges` is the only realtime stream in the app.

### Answers to the required questions

1. How does a passenger learn a driver accepted? **NOT IMPLEMENTED.**  
2. How does a driver learn another driver won? **NOT IMPLEMENTED.**  
3. Passenger UI update on assignment? **NOT IMPLEMENTED.**  
4. Other drivers’ request cards disappear? **NOT IMPLEMENTED.**  
5–11. Duplicate / out-of-order / stale events, sequence, version, event ID, idempotency for ride events? **NOT IMPLEMENTED.** Register idempotency exists only for `register_{uid}`.  
12–15. Reconnect, background, late FCM, dropped realtime? **NOT IMPLEMENTED** for rides. Auth session restore exists.

Documented model (`docs/architecture-final/06-realtime-events.md`, ADR-009): RTDB `rideSignals` / `tripLocations` / `rideRequests` + FCM fallback + `aggregateVersion`. **None of that is code.**

**Realtime confidence: HIGH that it is absent.**

---

## 11. Ride State Machine

### CURRENT STATE MACHINE (code)

**There is no ride state enum, no ride document, no transition table in Dart or TypeScript.**

Grep of `*.dart` / `*.ts` for `SEARCHING`, `DRIVER_ASSIGNED`, `RIDE_STARTED`, `REQUEST_CREATED`, `OFFERS_AVAILABLE`: **zero matches**.

Documented machine (`docs/ORA_STATE_MACHINE.md`, `docs/architecture-final/03-state-machines.md`) is **PLANNED**.

Auth/OTP UI states (`OtpState`, `AuthStatus`, `AuthFlowState`) are **not** ride states.

**Ride SM confidence: HIGH (absent).**

---

## 12. Ride Assignment / Concurrency

### Actual accept/assign implementation

**NONE.** No accept endpoint, no offer collection writes, no `ALREADY_ASSIGNED` handling, no compare-and-set on a ride document.

The only concurrency control in production code is:

```text
registerUser: Firestore transaction
  get users/{uid}
  if exists → return
  else set passenger bootstrap fields
```

(`backend/auth-service/src/services/users.ts`)

That guarantees **at most one user document per uid**. It says nothing about rides.

### Formal race-condition analysis (rides)

| Scenario | Can it happen today? |
| -------- | -------------------- |
| Driver A and B both assigned | **N/A — no assignment** |
| Stale request card | N/A |
| Duplicate navigation | N/A |
| Two drivers assigned | N/A |
| Late accept after assign | N/A |
| Retry duplicate assignment | N/A |
| App restart loses assignment | N/A |

**Do not treat Firestore-as-future-authority as implemented.** ADR-003 is a document, not a transaction in `rides/{id}`.

**Assignment confidence: HIGH (not implemented).**

---

## 13. Location

### Packages

`geolocator` is **not** in `mobile/pubspec.yaml`.  
Android `ACCESS_FINE_LOCATION` / iOS `NSLocationWhenInUseUsageDescription` are **absent**.

### Code

```dart
// mobile/lib/core/location/location_service.dart
PlaceholderLocationService.isServiceEnabled() => false;
```

Not registered in `providers.dart`.

### Required answers

| Question | Answer |
| -------- | ------ |
| Updates per second? | **0.** NOT IMPLEMENTED |
| Where do they go? | Nowhere |
| Transmission? | None |
| Storage? | None |
| Passenger receive? | None |
| Map animation? | None |
| Old packet / poor accuracy / stop / background / disconnect? | N/A |

**Location confidence: HIGH.**

---

## 14. Maps / Routing

- `google_maps_flutter` **not** in pubspec  
- `PlaceholderMapsService.initialize()` is a no-op (`core/maps/maps_service.dart`)  
- Feature barrel `features/maps/maps.dart` is empty  
- No Places, Geocoding, Routes API, polyline, markers, camera, or session tokens  
- No Maps API key in Android/iOS manifests  
- `docs/implementation/phase-04-maps-location.md` status: **NOT STARTED**

Cost-risk of Maps APIs today: **none** (no calls). Future cost risk is documented, not incurred.

**Maps confidence: HIGH.**

---

## 15. Fare Engine

**FARE ENGINE NOT IMPLEMENTED.**

No pricing service, no `pricingRules` reads, no `recommendedFareMinor`, no snapshot IDs, no rounding/min/max in code.

`docs/algorithms/fare-engine.md` correctly separates:

- **PUBLICLY DOCUMENTED PRODUCT BEHAVIOR** (passenger offer, driver counter, passenger selects)  
- **PRIVATE/UNKNOWN INTERNAL ALGORITHM** — “Ora does **not** claim knowledge of inDrive's private algorithm”

That distinction is healthy **as documentation**. It is not software.

**Fare confidence: HIGH (absent).**

---

## 16. Driver Discovery / Matching

**NOT IMPLEMENTED.**

- No Redis client, `GEOADD`/`GEORADIUS`, or Memorystore config in any `package.json`  
- No Firestore geo query for drivers  
- No `drivers` collection writes  
- `docs/implementation/phase-08-dispatch.md` status: **NOT STARTED**

Firestore would be a **poor** high-frequency geospatial dispatch engine (read amplification, no GEO index, cost). The architecture docs already prefer Redis GEO as non-authoritative candidate generation (ADR-004). That remains **future**.

**Matching confidence: HIGH (absent).**

---

## 17. Passenger System

| Feature | Status | Evidence |
| ------- | ------ | -------- |
| Home | PARTIAL | `HomeShellView` config + design sheet only |
| Pickup / destination | NOT IMPLEMENTED | |
| Places autocomplete | NOT IMPLEMENTED | |
| Saved places | PLANNED (rules only) | `firestore.rules` `savedPlaces` |
| Route / fare preview | NOT IMPLEMENTED | |
| Ride request / offers / selection | NOT IMPLEMENTED | |
| Live tracking / arrival / trip / payment / rating / history | NOT IMPLEMENTED | |
| Cancellation / support / safety | NOT IMPLEMENTED | |
| Logout from home | NOT IMPLEMENTED | Logout exists on **onboarding** only |

---

## 18. Driver System

| Feature | Status |
| ------- | ------ |
| Onboarding / identity / vehicle / documents / verification | NOT IMPLEMENTED |
| Online/offline | NOT IMPLEMENTED |
| Incoming requests / accept / decline / counter-offer | NOT IMPLEMENTED |
| Assignment / nav / arrival / trip | NOT IMPLEMENTED |
| Earnings / wallet / payouts / ratings / incentives / hot zones | NOT IMPLEMENTED |
| `driverStatus` field | Server default `'none'` on user doc only |

`features/driver/driver.dart` is a library stub.

---

## 19. Performance

No production ride/map load exists. Risks that **already** apply:

| Risk | Evidence |
| ---- | -------- |
| Splash dual navigation | `SplashView` `context.go(home)` vs guard |
| Broad router rebuild | `appRouterProvider` watches `authStateNotifierProvider` and **rebuilds a new `GoRouter`** on every auth status change |
| In-memory local storage | No persistent cache; irrelevant until maps |
| Unused codegen packages | `riverpod_generator` in pubspec unused |
| Auth bootstrap double register | `verifyOtp` registers, then `ResolveAuthProfileUseCase` registers again (idempotent, extra RTT) |

### Recommended measurable targets (NOT measured)

| Event | Suggested SLO (p95) | Achieved? |
| ----- | ------------------- | --------- |
| App launch to first interactive auth screen | &lt; 2.5 s mid-range Android | **UNKNOWN** |
| Map ready | n/a until Phase maps | N/A |
| Route ready | n/a | N/A |
| Request created / dispatch / accept / assignment / location | n/a | N/A |

Do **not** claim `docs/ORA_LATENCY_SLO.md` numbers are met.

**Performance confidence: MEDIUM** for structural risks; **LOW** for timings (unmeasured).

---

## 20. UX / Responsiveness

Reference: existing Ora/Raahi design docs vs current Flutter.

**What exists:** phone entry, OTP with resend cooldown, splash loading/error+retry, onboarding placeholder, home design-system demo, `OraButton` loading, `OraErrorState`, `OraEmptyState` widget (unused by ride flows), responsive max width 640.

**Gaps likely to feel wrong:**

| Issue | Why |
| ----- | --- |
| Onboarding “Continue” does not continue | Completeness requires `displayName`; no capture UI |
| Home has no sign-out | User who reaches home (only if name pre-set in Firestore) cannot log out in-app |
| Splash may flash “loaded” then bounce | View navigates home; guard may send back |
| Profile bootstrap failure | Silent stay on splash (`authenticated`) — retry only if user finds splash error path; bootstrap failure is not the splash VM error |
| No empty/error states for rides | No ride UI |
| Tablet | `Responsive` helpers exist; no map/tablet layout |
| Accessibility | No audit; min tap 48 in `AppConstants` only |
| Copy still says “Phase 1” on home | `home_shell_view.dart` |

Do not redesign in this audit.

**UX confidence: HIGH** for onboarding trap; **MEDIUM** for the rest (no device session).

---

## 21. Reliability

| Failure | CURRENT BEHAVIOR | EXPECTED (product) | GAP |
| ------- | ---------------- | ------------------ | --- |
| No internet at OTP | Firebase/Dio error → mapped `AppFailure` on phone/OTP | Same + retry | Small; unmeasured |
| No internet at `/me` | Stay splash `authenticated` | Retry + message | **No dedicated retry UI on that state** |
| Weak / switching network | Dio retry for GET/idempotent POST | Survive | Partial |
| App background during OTP | Firebase session + secure OTP id | Resume OTP | OTP verificationId may expire (Firebase) |
| App killed | Firebase restore + `/me` | Return to home/onboarding | Works **if** profile already complete |
| GPS disabled | N/A | Prompt | NOT IMPLEMENTED |
| API timeout | Dio timeouts 15/30/30s | User message | Mapped |
| Firebase Auth down | Init failure screen or OTP errors | Same | Implemented |
| FCM delayed | N/A | Wake + reconcile | NOT IMPLEMENTED |
| Duplicate ride events | N/A | Idempotent | NOT IMPLEMENTED |
| Cloud Run cold start | Auth-service only; client timeouts | Healthz exists | Unmeasured |
| Driver/passenger cancel races | N/A | Server SM | NOT IMPLEMENTED |
| Simultaneous register | Transaction | One doc | Implemented for users only |

**Reliability confidence: HIGH** for auth; **N/A** for trips.

---

## 22. Testing

| Test Area | Count | Passing (this audit) | Missing | Quality |
| --------- | ----: | -------------------- | ------- | ------- |
| Flutter unit (files) | 24 | **UNKNOWN** (not re-run) | Widget/golden/integration | **Good for auth contracts**; does not prove device OTP |
| Flutter widget / integration | 0 | — | Entire UI E2E | Missing (`integration_test/` absent) |
| Auth-service Vitest files | 4 | UNKNOWN | Real Firestore emulator for transactions | Good IDOR/App Check/rate-limit **with mocks** |
| Firestore rules emulator | 1 file (`test/firestore.rules.test.mjs`) | UNKNOWN; **not in CI** | `isActive` mutation test | Good for role/banned/self-read |
| Concurrency / assignment | 0 | — | Entire | Missing |
| Performance / load | 0 | — | Entire | Missing |
| E2E device | Documented historically in Phase 2A | **Not executed here** | Staging App Check | Historical only |

Phase 2 report claimed `flutter test` 131/131. This audit **does not re-verify**.

**Critical distinction:** tests **prove** token-uid identity, guard matrix, MVVM imports, `profileComplete` verbatim, production App Check start guard. They do **not** prove production Phone Auth against Play Integrity, Console Enforce, or any ride invariant.

---

## 23. Architecture Contradictions

## CONTRADICTION REGISTER

| ID | Severity | Docs say | Code is |
| -- | -------- | -------- | ------- |
| X1 | CRITICAL | Master plan: Ride Engine + Redis + RTDB + Pub/Sub | Only auth-service + Firestore `users` |
| X2 | CRITICAL | `04-api-contracts.md` inventories dozens of ride/payment endpoints | Only `/healthz`, `/v1/auth/register`, `/v1/auth/me` |
| X3 | HIGH | `phase-02-authentication.md` Known Limitation: `/me` not called after sign-in | `AuthStateNotifier` + `ResolveAuthProfileUseCase` **do** call it |
| X4 | HIGH | Same doc: App Check not initialized | `main.dart` + `firebase_app_check_bootstrap.dart` |
| X5 | HIGH | `phase-03-auth.md` NOT STARTED: implement phone OTP, Google, App Check | Phone OTP + App Check **already exist**; Google Sign-In still absent (and likely **should stay** absent per ADR-016) |
| X6 | HIGH | `phase-02a-s-security-gate.md`: App Check NOT IMPLEMENTED, rate limits MISSING, rules NOT YET CREATED | All three exist in 2B code |
| X7 | HIGH | Role via “Firebase custom claims” (`AuthUser`, `04-api-contracts.md` §23) | Role is a **Firestore field**; no `setCustomUserClaims` |
| X8 | HIGH | Onboarding Continue proceeds to home | Completeness needs `displayName`; no writer |
| X9 | MEDIUM | `phase-02-design-system.md` NOT STARTED | Phase 1 already shipped tokens + `Ora*` widgets |
| X10 | MEDIUM | Redis GEO for matching (ADR-004) | Zero Redis usage |
| X11 | MEDIUM | RTDB presence/location | No RTDB |
| X12 | MEDIUM | Distributed rate limiting | Memory `Map` |
| X13 | MEDIUM | Durable outbox / `idempotencyRecords` | Register uses txn + header match only |
| X14 | MEDIUM | `ORA_MASTER_PLAN.md` folder `firestore/` | Rules live at **repo root** |
| X15 | LOW | `router.dart` “guards in Phase 3” | Guards live now |
| X16 | LOW | Home copy “Phase 1” | Auth is Phase 2+ |

**Do not treat architecture-final as the running system.** `01-system-overview.md` itself says Flutter Phase 1 had no ride/RTDB — that sentence is still true for rides, and **outdated** for auth.

---

## 24. Technical Debt

1. Stale implementation docs (Phase 2 limitations, Phase 3 plan, 2A-S gate).  
2. Placeholder feature barrels pretending to be modules.  
3. `InMemoryLocalStorage` in production DI.  
4. Unused `riverpod_generator` / `riverpod_annotation`.  
5. Unused backend `uuid`.  
6. Rate-limit env vars not wired.  
7. Dual splash navigation.  
8. Register called twice per sign-in.  
9. Android auto-verify credential drop.  
10. `AuthStateNotifier.setAuthenticatedReady()` exists and **could** forge home if misused (onboarding does not call it; tests cover placeholder).  
11. Debug signing for release builds.  
12. CI gap (backend + rules).  
13. Docs volume ≫ code volume — high risk of implementing the wrong next phase from an old markdown file.

---

## 25. Critical Gaps

1. **Cannot complete onboarding** in the real app path.  
2. **No ride product.**  
3. **No realtime, maps, fare, dispatch, payments.**  
4. **In-memory rate limit** unsafe for scaled Cloud Run.  
5. **Firestore `isActive` client-updatable.**  
6. **Console / App Check Enforce unverified.**  
7. **CI does not protect auth-service.**  
8. **No account deletion / GDPR path.**  
9. **No structured observability.**  
10. **Phase ordering in master plan would start Maps/Google Sign-In before closing auth.**

---

## 26. Target Architecture

Grounded in **current code + locked ADRs that remain valid**. Do not preserve bad ideas just because they are written down.

### Flutter

| Layer | Owns | Must never own |
| ----- | ---- | -------------- |
| **Presentation (Views)** | Render `ViewState`, send intents | Dio, Firebase, Firestore, Maps SDK, business rules |
| **ViewModels** | UI state, loading/error, cooldown timers | Authoritative ride/payment/role |
| **Use cases** | Orchestrate one user journey | SDK imports |
| **Repositories** | Map domain ↔ data sources | Widget trees |
| **Services / data sources** | Firebase Auth, HTTP, (future) Maps/GPS wrappers | Forging `profileComplete` / assignment |

Keep the existing auth layering. Add feature modules the same way when Maps/Rides start — **do not** put Firestore in Views.

### Backend

| Component | Why it exists | Owns | Must never own |
| --------- | ------------- | ---- | -------------- |
| **Auth API** (exists) | Bootstrap identity | `users/{uid}` create/read, token verify | Ride state, fares |
| **API gateway / Ride API** (future) | Single mobile-facing HTTP surface | Request validation, authz | Direct client writes to ride docs |
| **Ride engine** | Assignment + SM | `rides`, `rideOffers`, transitions | Client GPS as truth |
| **Dispatch engine** | Candidate notify | Waves, eligibility | Assignment winner |
| **Pricing engine** | Recommended fare + snapshot | `pricingRules`, snapshots | Agreed fare after assign |
| **Location gateway** | Validate/sample GPS | Sequence, stale reject | Payment |
| **Notification service** | FCM + projection fanout | Delivery attempts | Ledger |

Keep **one** mobile-facing HTTP API (auth-service can remain a service *or* merge later). Do not let Flutter write `rides`.

### Data

| Store | Why | Owns | Must never own |
| ----- | --- | ---- | -------------- |
| **Firestore** | Durable truth | Users, rides, offers, payments, outbox | High-Hz GPS |
| **RTDB** | Ephemeral projection | Presence, tripLocations, request cards | Assignment/payment |
| **Redis** | Optimization | GEO, rate limits, notify sets | Winner of assignment |
| **Pub/Sub** | Async fanout | Downstream jobs | Synchronous assign |
| **Storage** | Driver docs / media | Blobs | Authz decisions |

ADR-003 (Firestore assignment barrier), ADR-004 (Redis non-authoritative), ADR-005 (outbox), ADR-008 (server SM) remain **correct targets**. They are not implemented.

### External

Firebase Auth, App Check, Google Maps/Places/Routes (when Maps phase starts), FCM, a **future** payment provider. No payment provider exists today.

---

## 27. Target Realtime Model

Every correctness-relevant event should carry:

```text
eventId, rideId, version (aggregateVersion),
serverTimestamp, eventType, actorId
```

Plus `schemaVersion` and `correlationId` as already frozen in event-contract docs.

| Concern | Rule |
| ------- | ---- |
| Ordering | Apply only if `version == local+1` or snapshot replace; never rewind |
| Dedup | `eventId` set (client + server) |
| Replay | Safe; same `eventId` no double navigation |
| Reconnect | Snapshot from Firestore, then attach RTDB; discard `version <= local` |
| Stale | Drop older `eventSequence` / `locationSeq` |
| Snapshot recovery | Firestore ride doc is repair source |
| Optimistic UI | Allowed for taps; **reconcile** to server; never commit assignment locally |
| Authority | Firestore transaction; RTDB/FCM are projections |

**Do not implement in this audit.**

---

## 28. Target Concurrency Model

Passenger selects offer (or future auto-assign policy) **on the server**. Driver accept/counter creates an **offer**, not an assignment (product model already documented).

```
Driver A, B, C post offers   →  rideOffers PENDING  (idempotency key per driver+ride)
Passenger selects offer O*
Server transaction:
  read ride
  if ride.state not in {SEARCHING, OFFERS_AVAILABLE}: abort STATE_CONFLICT
  if ride.assignedDriverId != null: abort ALREADY_ASSIGNED
  if O* expired/withdrawn: abort OFFER_NOT_SELECTABLE
  set assignedDriverId, agreedFare snapshot, state=DRIVER_ASSIGNED, version++
  outbox: ride.assigned
Losers: projector deletes RTDB pending cards; optional FCM
Retry: same Idempotency-Key returns same winner, no second assign
```

Firestore conditional transaction is the **only** correctness barrier. Redis SETNX is optional contention reduction, never the winner.

**Not implemented today.** No pseudocode should be mistaken for current code.

---

## 29. Target Location Model

```
GPS → validate (accuracy, jump, timestamp)
    → adaptive sampling (e.g. 1 Hz moving, slower when stopped)
    → POST /v1/location/update (driver, ride-scoped)
    → server writes RTDB tripLocations + Redis GEO (if online)
    → passenger RTDB listener
    → interpolate on map (client), never trust out-of-order seq
```

Suggested starting SLOs (not promised):

| Metric | Target |
| ------ | ------ |
| Update frequency (en-route) | 1 Hz typical, back off if accuracy &gt; 50 m |
| Stale threshold | &gt; 8 s without valid point → “location delayed” |
| Accuracy gate | Reject &gt; 40–50 m for GEO/index; still may show last good |
| Fields | `seq`, `serverTs`, `clientTs`, `lat`, `lng`, `heading`, `speed`, `accuracy` |
| Background | OS-limited; degrade sampling; do not invent points |
| Reconnect | Resume from last `seq`; snapshot latest |

**NOT IMPLEMENTED.**

---

## 30. Target Pricing Model

Independent Ora engine. **Do not** claim inDrive’s private formula.

| Amount | Meaning | Authority |
| ------ | ------- | --------- |
| `recommendedFareMinor` | Guidance | Pricing service + `pricingVersion` |
| `passengerOfferMinor` | Bid | Passenger via API |
| `driverCounterOfferMinor` | Counter | Driver via API |
| `agreedFareMinor` | Contract | Server at assignment; **immutable** |
| Payment amount | Settlement | Payment/ledger from agreed fare + fees |

Every accepted fare snapshot:

`pricingVersion, fareSnapshotId, currency, distance, duration, category, rulesUsed, timestamp`

Until this service exists, the client must **not** compute production fares.

---

## 31. Target Security Model

### Trust boundaries

| Boundary | May | Must not |
| -------- | --- | -------- |
| **CLIENT** | Show UI; send OTP; attach Bearer + App Check; send intents | Set `role`, `banned`, `isActive`, assignment, fare agreement, payment capture |
| **SERVER (Cloud Run + Admin)** | Verify token+App Check; mutate authoritative docs; assign; price | Trust body uid/role; skip SM; log tokens |
| **DATABASE RULES** | Allow low-risk owner fields (e.g. saved places, displayName **via API preferred**) | Allow client writes to rides/payments/drivers |
| **ADMIN** | Audited corrections | Silent SM bypass without `adminAuditLogs` |

### Explicit list (current + target)

**CLIENT MAY:** request OTP, verify OTP, call register/me, later call ride APIs with their token.  
**CLIENT MAY NOT:** create `users` docs, change `role`/`banned`/`isActive`, write `rides`.  
**SERVER MAY:** create users, later assign rides.  
**SERVER MUST:** `verifyIdToken(token, true)`; identity from token; fail closed without App Check in production.  
**ADMIN MAY:** only via audited admin API (not implemented).

**Fix before Maps:** add `isActive` to Firestore protected fields; profile updates through API with validation.

---

## 32. Target Performance SLOs

Aspirational for a **future** ride-capable app on mid-range Android / typical PK mobile network. **None measured.**

| Event | p50 | p95 | p99 |
| ----- | --- | --- | --- |
| Cold start to phone entry (session none) | 1.2 s | 2.5 s | 4 s |
| Session restore to home/onboarding | 1.5 s | 3.5 s | 6 s |
| Map first frame (future) | 0.8 s | 1.8 s | 3 s |
| Route + recommended fare (future) | 0.6 s | 1.5 s | 3 s |
| Ride request ack | 0.3 s | 0.8 s | 1.5 s |
| Dispatch first notify | 0.5 s | 2 s | 4 s |
| Accept/offer ack | 0.2 s | 0.6 s | 1.2 s |
| Assignment visible to both parties | 0.4 s | 1.2 s | 2.5 s |
| Location projection (en-route) | 0.3 s | 1.0 s | 2 s |
| Auth UI frame after tap | 16 ms | 32 ms | 50 ms |

Do not advertise these as current.

---

## 33. Recommended Development Roadmap

Do **not** blindly execute `docs/ORA_MASTER_PLAN.md` Phase 3 (Google Sign-In + Maps) or Phase 4 Maps next. Auth is incomplete as a product, and 2B already forbade Maps until Console + rate-limit plan.

### Phase A — Auth & Onboarding Closure (NEXT)

- **Objective:** A new phone user can finish a real passenger profile and reach home; leave onboarding; sign out from home; CI covers auth-service + rules.  
- **Dependencies:** Current auth-service + Flutter auth.  
- **Scope:** `PATCH` (or `PUT`) profile API; displayName (and later required passenger fields); protect `isActive`; fix Android auto-verify; remove splash dual-nav; wire CI; optional logout on home. **No Maps, Redis, RTDB, rides.**  
- **Tests:** API validation, completeness transitions, rules `isActive` deny, widget test onboarding.  
- **Security:** Keep token identity; no client Firestore for profile.  
- **Firebase Console:** Checklist from `phase-02b-firebase-console-checklist.md` (manual; not this phase’s code).  
- **Done when:** New user sets name → `profileComplete=true` → home; banned still blocked; CI green including `npm test` in auth-service.  
- **Rollback:** Feature-flag profile PATCH; old clients still fail closed to onboarding.

### Phase B — Production auth hardening

- Shared rate limit (Memorystore or Cloud Armor) **before** public traffic.  
- Staging App Check E2E.  
- Secret Manager / Workload Identity instead of JSON on disk.  
- Release signing.  
- Provider cleanup (Google/Email) **only with human approval**.

### Phase C — Maps & location (passenger preview only)

- After A+B. Server-side Routes/Places where cost/abuse matters. No dispatch.

### Phase D — Ride request + offer model (no live matching required for first vertical slice)

- Ride SM on server; passenger create request; **manual/stub dispatch optional**. Assignment transaction **before** any “accept assigns” shortcut.

### Phase E — Dispatch (Redis GEO) + RTDB projections + FCM

- Redis non-authoritative; outbox; versioned signals.

### Phase F — Trip lifecycle, then payments, then safety

- Payments last among money-adjacent features; ledger immutable (ADR-010) when introduced.

Old numbers (Phase 5 pricing before a request API, Phase 6 driver before any ride) can shift: **pricing snapshot is required at ride create**, so a thin pricing stub belongs with Phase D, not as a disconnected Phase 5.

---

## 34. NEXT PHASE

### What should be done next

**Phase A — Auth & Onboarding Closure** (name it `phase-02c` or a rewritten Phase 3). Close the identity product: profile write path, onboarding UI that actually collects `displayName`, Firestore `isActive` lock, Android auto-retrieve fix, CI for backend/rules, home logout, doc reconciliation.

### Why

The only implemented product cannot reach its own home screen for a newly registered user. Building Maps or a ride engine on top of a stuck onboarding gate wastes work and repeats the docs-vs-code failure.

### What must happen before it

Nothing architectural. Optional: apply Firebase Console checklist items that do not require code (do not Enforce App Check globally until staging clients send tokens).

### What must NOT happen yet

- Maps / Geolocator / RTDB / Redis / Pub/Sub / FCM  
- Ride, offer, dispatch, fare engine, payments  
- Google / Apple Sign-In (not needed; increases Console attack surface)  
- Client Firestore SDK for profile (use API)  
- Claiming production-ready auth

---

## 35. Exact Next Cursor Prompt

```text
# ORA — PHASE 2C AUTH & ONBOARDING CLOSURE (IMPLEMENTATION)

## ROLE
Implement the next slice of Ora from the ACTUAL repo state (see docs/audits/ORA_COMPLETE_ARCHITECTURE_AUDIT.md). You are not starting Maps, rides, Redis, RTDB, or payments.

## CURRENT FACTS (do not re-litigate)
- Flutter MVVM + Riverpod + go_router auth already works: Firebase Phone OTP, POST /v1/auth/register, GET /v1/auth/me.
- New users are created with displayName: null. deriveProfileComplete() requires a non-empty displayName, so AuthStatus stays onboardingRequired.
- OnboardingPlaceholderView.completePlaceholder() only retries /me and cannot write a name.
- There is no PATCH/PUT profile endpoint. Do not add cloud_firestore to the Flutter app for this.
- firestore.rules allow client update of displayName and do NOT protect isActive. Protect isActive (and keep role/banned/uid/phone protected). Profile mutation must go through auth-service.
- Android verificationCompleted currently completes with sessionId 'auto' and drops PhoneAuthCredential — fix without breaking the manual OTP path.
- SplashView context.go(home) fights AuthRouteGuard — make splash not navigate; let the guard own destination.
- CI (.github/workflows/ci.yml) runs Flutter only — add auth-service `npm test` and document how to run Firestore rules tests (add to CI if emulator action is practical).
- HomeShellView has no logout. Add it via existing LogoutUseCase / AuthViewModel.logout.
- Do not implement Google Sign-In, Maps, ride APIs, Redis, or FCM.

## IMPLEMENT
1. auth-service: authenticated PATCH /v1/auth/profile (or equivalent) that updates displayName (trim, length bounds, charset). Identity from verified token only. Recompute profileComplete server-side. Return the same UserProfile JSON as /me.
2. Flutter: real onboarding screen (replace placeholder behavior) — collect displayName, call the new API, then retryProfileBootstrap. Views still must not import Dio/Firebase.
3. Firestore rules: add isActive to protected fields; add emulator test that client cannot set isActive.
4. Fix FirebaseAuthDataSource auto-retrieval to sign in with the credential OR ignore auto and wait for codeSent — pick the correct Firebase-recommended behavior and test what can be unit-tested.
5. Remove dual splash navigation.
6. Home sign-out.
7. CI: backend unit tests.
8. Update stale docs that say /me is not called and App Check is not wired (phase-02-authentication.md limitations; do not rewrite the entire architecture-final tree).

## TESTS
- Backend: validation, IDOR (cannot patch another uid), banned/inactive still 403, completeness true after name.
- Flutter: onboarding VM does not forge authenticatedReady; calls use case; route guard still fail-closed if profileComplete false.
- Rules: isActive update denied; displayName still allowed OR denied if you move all profile writes to API-only (prefer API-only: deny client update of users except nothing — even displayName — if the API is the writer). Strongest: client update of users/{uid} denied entirely; only Admin SDK writes. That matches “API-mediated mutations”.

## STOP
Do not start Phase 4 Maps. Do not add ride collections usage. Do not deploy Firebase Console changes automatically.
```

---

# Implementation matrix (audit §3)

Status vocabulary: COMPLETE | PARTIAL | PLANNED | NOT IMPLEMENTED | BROKEN | UNKNOWN

## Authentication

| Feature | Status | Evidence | Location | Production ready? |
| ------- | ------ | -------- | -------- | ----------------- |
| Firebase Phone Auth | PARTIAL | `verifyPhoneNumber` + credential sign-in; debug bypass; auto-retrieve bug | `firebase_auth_data_source.dart` | No |
| OTP UI + 30s cooldown | COMPLETE | `AuthViewModel` timer | `auth_view_model.dart` | UX only |
| Session restore | COMPLETE | `restoreSession` + `getIdToken(true)` | `auth_repository_impl.dart` | For auth yes |
| Token refresh | COMPLETE | `FirebaseAuthTokenProvider` + 401 interceptor | `auth_token_provider.dart`, `api_client.dart` | Yes (auth) |
| Token revocation | PARTIAL | `verifyIdToken(_, true)` | `middleware/auth.ts` | API yes; unproven vs Console |
| Logout | PARTIAL | Implemented; home has no button | `logout_use_case.dart`, onboarding view | No |
| Account deletion | NOT IMPLEMENTED | No deleteUser / revoke | — | No |
| Disabled account | PARTIAL | Firebase revoke + Firestore banned/isActive | `auth.ts`, `users.ts`, `AuthStateNotifier` | Partial |
| Profile creation | COMPLETE | Register transaction | `users.ts` | Yes |
| Profile completion | BROKEN | Requires displayName; no writer | `profile.ts`, onboarding placeholder | No |
| Onboarding routing | PARTIAL | Guard works; destination stuck | `route_guards.dart` | No |
| API authentication | COMPLETE | Bearer + optional App Check | `middleware/auth.ts` | Dev yes; prod needs App Check on |
| App Check | PARTIAL | Client + server wiring; Console UNKNOWN | `firebase_app_check_bootstrap.dart`, `index.ts` | No |

## Passenger / Driver / Ride (compressed)

All pickup, destination, Places, saved places (app), route, fare, request, offers, tracking, payment, rating, history, cancellation, support, safety: **NOT IMPLEMENTED** except passenger **home placeholder** (PARTIAL) and **savedPlaces rules-only** (PLANNED).

All driver onboarding, vehicle, docs, online, accept, earnings, wallet, payouts, hot zones: **NOT IMPLEMENTED**.

## Backend platform

| Feature | Status | Evidence | Production ready? |
| ------- | ------ | -------- | ----------------- |
| API | PARTIAL | auth-service only | No (product) |
| AuthZ | PARTIAL | Token uid; no roles on API beyond passenger default | For /me yes |
| Firestore | PARTIAL | `users` only | For auth yes |
| RTDB / Redis / Pub/Sub / Functions / FCM / Storage / Secret Manager | NOT IMPLEMENTED | No deps/dirs | No |
| Cloud Run | PARTIAL | Dockerfile; no IaC | No |
| Monitoring / structured logging | NOT IMPLEMENTED | console only | No |
| Rate limiting | PARTIAL | In-memory | **No** at scale |
| Idempotency | PARTIAL | `register_{uid}` + txn | Register only |
| Event processing / jobs | NOT IMPLEMENTED | | No |

---

# ORA ARCHITECTURE AUDIT STATUS

| Area | Status |
| ---- | ------ |
| Architecture | **Documented target is coherent; implemented architecture is auth-only.** |
| Security | **Auth IDOR/token path is solid in code; production/App Check/Console/rate-limit/rules `isActive` are not closed.** |
| Frontend | **Good MVVM auth; stubs for the product.** |
| Backend | **Single Express auth-service.** |
| Realtime | **NOT IMPLEMENTED** |
| Location | **NOT IMPLEMENTED** |
| Maps | **NOT IMPLEMENTED** |
| Fare | **NOT IMPLEMENTED** |
| Dispatch | **NOT IMPLEMENTED** |
| Concurrency (rides) | **NOT IMPLEMENTED** |
| Payments | **NOT IMPLEMENTED** |
| Testing | **Strong unit/security tests for auth; no ride/E2E/load; CI incomplete** |
| Production readiness | **NO** |

### TOP 10 RISKS

(Ranked IMPACT × LIKELIHOOD × DIFFICULTY TO RECOVER)

1. **Proceeding to Maps/rides from stale Phase 3 docs** while onboarding is stuck — wasted architecture, false “feature complete”.  
2. **Onboarding completeness deadlock** (`displayName`) — every new user.  
3. **In-memory rate limit on multi-instance Cloud Run** — trivial to overrun auth.  
4. **Client-writable `isActive`** if anyone uses the Firestore SDK.  
5. **App Check not Console-enforced** — unattested API clients.  
6. **Android auto-verify credential drop** — intermittent sign-in failure.  
7. **CI blind to auth-service** — security regressions undetected.  
8. **Future duplicate assignment** — no transaction exists; risk appears the day accept is coded wrongly on the client.  
9. **Future stale RTDB cards / reconnect** — no event versioning in code.  
10. **Payment manipulation** — N/A today; becomes critical the moment a client-trusted fare is introduced.

(Duplicate assignment, stale driver requests, incorrect realtime, location staleness, payment manipulation, client-controlled ride state, replay, reconnect: **not present as bugs because the features are absent** — they are **design risks for the next product phases**.)

### TOP 10 RECOMMENDATIONS

1. Implement Phase 2C profile API + onboarding UI.  
2. Deny all client writes to `users/{uid}` (API-only) **or** at least protect `isActive`.  
3. Put auth-service tests in CI.  
4. Fix auto-retrieve OTP.  
5. Guard-owned navigation only.  
6. Plan Redis/Armor rate limits before public launch (implement when scaling, not with Maps).  
7. Finish Firebase Console checklist before claiming production security.  
8. Reconcile stale Phase 2/3 markdown so the next agent cannot start Google Sign-In/Maps by accident.  
9. Keep Redis/RTDB/Firestore SoT rules from ADRs when rides start.  
10. Do not add `cloud_firestore` to Flutter for authority.

### WHAT IS ALREADY GOOD

- Clean auth layering and security tests forbidding Views from importing Firebase/Dio  
- Token-only identity on the API; forged uid ignored  
- Firestore fail-closed default + explicit deny lists for future collections  
- Register idempotency + transaction  
- Production start guards for App Check (process-level)  
- HTTPS / App Check refuse-start in Flutter release+production  
- Honest comments in `rate_limit.ts` that memory limiter is not production  
- Fare docs that refuse to invent inDrive’s private algorithm  
- ADR split: Firestore assignment truth vs Redis optimization  

### WHAT MUST BE FIXED

- Onboarding write path  
- `isActive` protection / API-only user mutations  
- Auto-verify OTP  
- Splash vs guard  
- CI coverage  
- Stale “next phase” documents  

### WHAT MUST NOT BE TOUCHED

- MVVM + Riverpod composition root pattern for features  
- Fail-closed `profileComplete` from server JSON  
- `verifyIdToken(token, true)`  
- Register identity-from-token  
- Denying client writes to `rides` / payments in rules  
- Decision that Redis is not assignment authority  
- Decision that Firebase Phone Auth (not custom `otpSessions`) owns OTP  
- Decision not to store ID tokens in SecureStorage  

### EXACT NEXT PHASE

**Phase 2C — Auth & Onboarding Closure** (profile API, real onboarding, rules lock, OTP auto-retrieve fix, CI). **Not Maps. Not rides.**

### EXACT NEXT CURSOR PROMPT

See **§35** above.

---

**STOP.** This audit does not implement the next phase.

*End of report.*
