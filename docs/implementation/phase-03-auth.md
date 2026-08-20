# Phase 3 — Authentication

**Status:** NOT STARTED  
**Dependencies:** Phase 2  
**Estimated effort:** 1.5 weeks

## Objectives

Implement phone OTP, Google Sign-In, Apple Sign-In, App Check, JWT storage, and protected route navigation.

## Tasks

### 3.1 Firebase Project Setup

- Create Firebase project: `ora-app-production`
- Create second project: `ora-app-staging` (separate environments)
- Enable: Authentication, App Check, Firestore, RTDB, Storage, FCM, Crashlytics
- Download `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)
- Store in `secrets/` (gitignored); document in README

### 3.2 Auth Methods

- Phone + OTP (SMS via Firebase)
- Google Sign-In (`google_sign_in` package)
- Apple Sign-In (`sign_in_with_apple` package; required for iOS)

### 3.3 App Check

```dart
// Initialize before runApp()
await FirebaseAppCheck.instance.activate(
  androidProvider: AndroidProvider.playIntegrity,
  appleProvider: AppleProvider.deviceCheck,
);
```

Debug token for CI: loaded from `.env`, never committed.

### 3.4 Auth Flow Screens

- Splash → auto-navigate: if auth + App Check valid → Home; else → Auth
- Sign Up screen: name, phone, password
- Sign In screen: phone, password
- OTP screen: 4-digit input, resend timer

### 3.5 Routing (go_router)

```dart
GoRoute(
  path: '/home',
  redirect: (context, state) {
    final authState = ref.read(authProvider);
    if (!authState.isAuthenticated) return '/auth/signin';
    return null;
  },
)
```

### 3.6 Token Storage

JWT stored in `flutter_secure_storage` (Keychain on iOS, Keystore on Android).  
Auto-refresh via `firebase_auth` listener.

### 3.7 First User Document Creation

On successful first auth:
```
POST /v1/auth/register
Body: { displayName, referralCodeUsed? }
Server: creates users/{uid} in Firestore
       assigns referralCode
       sets role: "passenger"
```

## Acceptance Criteria

- [ ] Phone OTP works end-to-end on real device
- [ ] Google Sign-In works on Android real device
- [ ] Apple Sign-In works on iOS real device
- [ ] App Check passes on real device; fails gracefully on simulator (debug token)
- [ ] JWT stored in secure storage; not in SharedPreferences
- [ ] Unauthenticated users redirected to signin; cannot deep-link to protected routes
- [ ] Unit test: route guard blocks unauthenticated access
- [ ] Unit test: token refresh logic
- [ ] User document created in Firestore after first auth
- [ ] `flutter analyze` still clean
