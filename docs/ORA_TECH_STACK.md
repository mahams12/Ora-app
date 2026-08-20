# ORA — Technology Stack Decision Record

**Version:** 0.1.0-architecture  
**Date:** 2026-08-18  
**Status:** APPROVED FOR PHASE 0

---

## 1. Frontend

| Layer | Technology | Rationale |
|---|---|---|
| UI Framework | Flutter 3.x (stable channel) | Single codebase for Android + iOS; Skia/Impeller rendering avoids WebView overhead; strong ecosystem |
| Language | Dart 3.x (sound null safety) | Type-safe, AOT-compiled, Isolate support for background work |
| State Management | Riverpod 2.x (code-gen) | Compile-time safety; no ProviderScope hell; easy async; testable; no BuildContext dependency |
| Navigation | go_router 14.x | Declarative, deep-link ready, shell routes for persistent bottom nav |
| Networking | Dio + Retrofit (codegen) | Interceptor chain; retry; request cancellation; type-safe endpoints |
| Maps | google_maps_flutter 2.x | Official plugin; supports polylines, markers, camera control |
| Location | geolocator 11.x + flutter_background_geolocation (Transistor) | Foreground + background; accuracy filters; heading; speed |
| Places / Autocomplete | google_maps_webservice / places_autocomplete | Autocomplete, reverse geocoding, place details |
| Local Storage | hive_ce (encrypted where needed) | Prefer an actively maintained lightweight cache; keep secrets in secure storage |
| Secure Storage | flutter_secure_storage | Keychain/Keystore for tokens |
| Push Notifications | firebase_messaging | FCM for both foreground and background |
| Analytics | Firebase Analytics + Crashlytics | Crash reporting + funnel analytics |
| Design System | Custom Ora Design System (ODS) | Navy/Gold/Teal tokens; Material 3 baseline; Sora + Inter fonts |
| Theming | ThemeExtension + AppTheme | Dark-first (matches prototype); light theme planned Phase 2 |
| Localization | flutter_localizations + intl | ARB-based; English first; Urdu ready |
| Immutable Models | freezed + json_serializable | Immutable data classes; union types; copyWith |
| DI | Riverpod providers | No service locator; scoped providers |
| Testing | flutter_test + mocktail + patrol | Unit, widget, integration |

### Flutter Architecture Pattern: Feature-First Clean Architecture

```
lib/
  core/
    config/
    error/
    network/
    theme/
    utils/
  features/
    auth/
      data/
      domain/
      presentation/
    ride/
    driver/
    map/
    payment/
    safety/
  shared/
    widgets/
    models/
    services/
  main.dart
  app.dart
```

---

## 2. Maps & Location Stack

| Capability | Technology | Notes |
|---|---|---|
| Base map rendering | Google Maps Flutter | Tile caching; custom map styles |
| Geocoding | Google Geocoding API | Server-side only (API key not in client) |
| Autocomplete | Google Places Autocomplete API | Session tokens to control billing |
| Route calculation | Google Routes API (preferred) or Directions API | Traffic-aware; waypoints; alternatives |
| ETA matrix | Google Distance Matrix API (server side) | Used for matching engine only |
| GPS sampling (foreground) | geolocator — 2-second interval, 10m distance filter, HIGH accuracy | |
| GPS sampling (active trip) | 1-second interval, 5m filter, BEST accuracy | |
| GPS sampling (idle driver) | 5-second interval, 20m filter, BALANCED accuracy | |
| Background location | Transistor BGGeo plugin | Stationary detection; saves battery |
| Location smoothing | Kalman filter (Dart) server-side validation | |
| Stale threshold | 8 seconds without update → mark stale | |
| Accuracy threshold | Reject fixes > 50m horizontal accuracy | |
| Heading | geolocator heading field | Animate car marker rotation |

---

## 3. Backend

### 3a. Firebase Services

| Service | Role | Constraints |
|---|---|---|
| Firebase Authentication | Identity: phone OTP, Google Sign-In, Apple Sign-In | Server validates token on every API call |
| App Check | Attest genuine app binary; block unauthorized API callers | DeviceCheck (iOS) + Play Integrity (Android) |
| Cloud Firestore | Durable source of truth: users, rides, drivers, payments | NOT used for high-freq GPS writes |
| Firebase Realtime Database (RTDB) | Ephemeral: driver presence, active trip GPS location, connection state | TTL managed by server; cleared after trip |
| Cloud Messaging (FCM) | Push: ride requests, status updates, offers, receipts | Supplement only; primary channel = RTDB listener |
| Cloud Storage | Driver documents, vehicle photos, profile photos | Client upload via signed URL; no direct Storage SDK key |
| Crashlytics | Client crash reporting | |
| Firebase Analytics | Product analytics | |

### 3b. Google Cloud Services

| Service | Role |
|---|---|
| Cloud Run | Ride Engine API (stateless, auto-scaling, cold-start < 2s) |
| Cloud Run | Location API microservice |
| Cloud Run | Pricing API microservice |
| Cloud Run | Notification dispatcher |
| Memorystore for Redis | GEO index for driver proximity; distributed locks; short-lived dispatch data; offer deduplication |
| Cloud Pub/Sub | Async events: ride created, assigned, completed; analytics; notification fan-out |
| Secret Manager | All secrets: API keys, signing keys, Redis URL — never in code |
| Cloud Armor | DDoS, WAF, rate limiting at load balancer layer |
| Cloud Monitoring + Logging | Structured logs; latency dashboards; alerting |
| Cloud Scheduler | Ride expiry sweeper, driver cleanup, bonus calculation |

### 3c. Architecture Responsibility Matrix

```
Component         | Writes GPS | Owns Ride State | Atomic Assign | Auth |
------------------|-----------|----------------|--------------|------|
Flutter Client    | Sends     | Reads only     | NO           | Token|
Cloud Run API     | Validates | YES            | YES          | YES  |
Firestore         | Persists  | Source of truth| Via txn      | Rules|
RTDB              | Ephemeral | Presence/signals/GPS projections | NO | Rules|
Redis             | GEO index | Ephemeral coordination/cache | Optional contention reduction | N/A  |
Cloud Functions   | Scheduled | Expire/cleanup | NO           | Admin|
```

---

## 4. Rejected / Deferred Alternatives

| Alternative | Decision | Reason |
|---|---|---|
| Firestore for GPS | REJECTED | Too expensive; too slow; 1/s write limit per doc |
| Client-side ride assignment | REJECTED | Race condition guaranteed; security violation |
| GraphQL | DEFERRED | REST sufficient for Phase 0–10; evaluate Phase 11+ |
| WebSocket direct | DEFERRED | RTDB provides managed WebSocket with reconnect |
| Socket.io | REJECTED | Operational overhead vs managed RTDB |
| ML ranking | DEFERRED | Deterministic scoring first; ML in Phase 14+ |
| Stripe | DEFERRED | Pakistan PSP first: JazzCash, Easypaisa; Stripe Phase 11+ |
| GetX | REJECTED | Mixes concerns; testing harder |
| BLoC | CONSIDERED | Riverpod chosen for less boilerplate |
| Provider | REJECTED | No compile-time safety; harder to test |

---

## 5. Third-Party SDKs — Client Risk Assessment

| SDK | Risk | Mitigation |
|---|---|---|
| google_maps_flutter | API key exposure | Key restricted to package ID + SHA; Maps SDK only; no billing key client-side |
| geolocator | Battery drain | Adaptive frequency; stationary detection |
| firebase_messaging | Background battery | Prefer data-only FCM; RTDB primary |
| Transistor BGGeo | Paid SDK | Evaluate open alternative in Phase 4 |
