# ORA — Master Architecture Plan

**Version:** 0.1.0-architecture  
**Date:** 2026-08-18  
**Status:** Phase 0 Complete — DO NOT IMPLEMENT until Phase 1 is explicitly started

---

## Executive Summary

Ora is a production-grade Flutter ride-hailing platform targeting Android and iOS. The product model mirrors inDrive's open-marketplace fare negotiation (passenger sets price; drivers accept/counter) combined with direct assignment where preferred. A single app serves both passengers and drivers. The backend is server-authoritative, meaning no client ever owns ride state, fare calculation, or driver assignment.

---

## 1. Product Architecture

```
┌─────────────────────────────────────────────────┐
│                   ORA APP                        │
│  Flutter 3 · Dart 3 · Riverpod · go_router      │
│                                                   │
│  ┌───────────────┐  ┌───────────────────────┐   │
│  │  PASSENGER    │  │     DRIVER            │   │
│  │  MODE         │  │     MODE              │   │
│  └───────────────┘  └───────────────────────┘   │
└──────────────────┬──────────────────────────────┘
                   │
          Firebase Auth + App Check
                   │
         ┌─────────▼──────────┐
         │   Cloud Run API    │
         │  (Ride Engine)     │
         └─────────┬──────────┘
         ┌─────────┼──────────────────┐
         ▼         ▼                  ▼
    Firestore   Redis GEO        Pub/Sub
  (durable    (ephemeral       (async events
   truth)      dispatch)        + analytics)
         │
         ▼
    RTDB (presence, live location)
    FCM  (push fallback)
    Google Maps APIs (geocoding, routes, ETA)
```

---

## 2. Technology Stack Summary

See `ORA_TECH_STACK.md` for full detail.

**Frontend:** Flutter 3, Dart 3, MVVM + Riverpod 2, go_router, google_maps_flutter, geolocator, freezed. Canonical tree: `docs/architecture/flutter-mvvm-architecture.md`.  
**Backend:** Cloud Run, Firestore, RTDB, Redis (Memorystore), Pub/Sub, FCM, Cloud Storage  
**Auth:** Firebase Auth + App Check  
**Maps:** Google Maps, Places, Routes, Distance Matrix APIs  
**Observability:** Cloud Monitoring, Cloud Logging, Crashlytics, Firebase Analytics  

---

## 3. Folder Architecture

```
/
├── docs/                          # This package — architecture docs only
│   ├── ORA_MASTER_PLAN.md
│   ├── ORA_TECH_STACK.md
│   ├── ORA_STATE_MACHINE.md
│   ├── ORA_LATENCY_SLO.md
│   ├── ORA_SECURITY_MODEL.md
│   ├── architecture/
│   ├── product/
│   ├── algorithms/
│   ├── database/
│   ├── api/
│   ├── security/
│   ├── performance/
│   ├── testing/
│   ├── operations/
│   └── implementation/
│
├── mobile/                        # Flutter app (Phase 1+)
│   ├── lib/
│   │   ├── app/
│   │   │   ├── app.dart
│   │   │   ├── router/
│   │   │   └── theme/
│   │   ├── core/
│   │   │   ├── errors/
│   │   │   ├── network/
│   │   │   ├── storage/
│   │   │   ├── location/
│   │   │   ├── maps/
│   │   │   └── utils/
│   │   ├── features/
│   │   │   ├── auth/
│   │   │   ├── passenger/
│   │   │   ├── driver/
│   │   │   ├── ride/
│   │   │   ├── maps/
│   │   │   ├── payments/
│   │   │   └── safety/
│   │   └── main.dart
│   ├── test/
│   ├── integration_test/
│   └── pubspec.yaml
│
├── backend/                       # Cloud Run services (Phase 6+)
│   ├── ride-engine/
│   ├── location-service/
│   ├── pricing-service/
│   └── notification-service/
│
├── functions/                     # Cloud Functions (Phase 6+)
│   └── src/
│
├── firestore/                     # Firestore rules + indexes (Phase 3+)
│   ├── firestore.rules
│   └── firestore.indexes.json
│
└── scripts/                       # Dev tooling (Phase 1+)
```

---

## 4. Database Architecture Summary

See `docs/database/firestore-schema.md` for full schema.

**Firestore collections:**
- `users` — profile, role, status
- `drivers` — approval, rating, earnings summary
- `vehicles` — make/model/plate/approval
- `driverDocuments` — licence, insurance, photo (server-verified)
- `rides` — active/historical ride records
- `rideEvents` — immutable audit log per ride
- `paymentIntents` — payment obligation per ride or wallet operation
- `paymentAttempts` — one provider interaction per attempt
- `paymentTransactions` — provider-side transaction references and settlement states
- `paymentProviderCallbacks` — deduplicated inbound provider webhooks
- `walletAccounts` — derived wallet balances and account metadata
- `walletLedgerEntries` — immutable append-only ledger
- `refunds` — refund requests and outcomes
- `driverPayouts` — payout requests and settlement outcomes
- `reconciliationRecords` — mismatch detection and settlement audit
- `ratings` — passenger/driver ratings
- `savedPlaces` — home, work, favourites
- `pricingRules` — zone/category pricing config
- `pricingSnapshots` — immutable fare snapshot per ride
- `serviceAreas` — city/zone polygons
- `hotZones` — demand zones
- `referrals` — referral tracking
- `supportTickets` — help tickets
- `safetyEvents` — SOS, reports

**RTDB paths:**
- `driverPresence/{driverId}` — ephemeral connection and presence projection
- `tripLocations/{rideId}` — current trip location projection for ride participants only
- `rideSignals/{rideId}` — authoritative-aggregate wake-up signal for ride participants only
- `rideRequests/{driverId}/pending/{rideId}` — per-driver pending offer/request projection

**Redis keys:**
- `geo:drivers:{city}` — GEOADD sorted set
- `lock:ride:{rideId}` — optional contention lock (SETNX, 30s TTL)
- `dispatch:notified:{rideId}` — list of notified driver UIDs by wave
- `offer:dedup:{rideId}:{driverId}` — prevent duplicate offers

---

## 5. API Architecture

All public APIs are hosted on Cloud Run. Base URL: `https://api.ora.app/v1`

**Ride API:** POST /rides, GET /rides/{id}, POST /rides/{id}/offers, POST /rides/{id}/offers/{offerId}/select, PATCH /rides/{id}/status, POST /rides/{id}/cancel  
**Driver API:** POST /drivers/go-online, POST /drivers/go-offline, GET /drivers/nearby  
**Location API:** POST /location/update  
**Pricing API:** POST /pricing/estimate, GET /pricing/rules  
**Payment API:** POST /payments/initiate, POST /payments/cash-collected, POST /payments/refund  
**Auth API:** POST /auth/verify-driver, GET /auth/me  

See `docs/api/api-contract.md` for full OpenAPI-style documentation.

---

## 6. Realtime Architecture

```
Driver GPS update
    ↓
  Flutter BGGeo → POST /location/update (Cloud Run)
    ↓
  Server validates (accuracy, staleness, speed plausibility)
    ↓
  Redis GEOADD (update GEO index)
    ↓
  RTDB write: tripLocations/{rideId}/{seq} (active trip only)
    ↓
  Passenger RTDB listener fires
    ↓
  Kalman-smoothed position rendered on map

Ride offer + assignment:
    ↓
  Driver taps Accept or Counter → POST /rides/{id}/offers  (pending offer; NOT assignment)
    ↓
  Passenger selects offer → POST /rides/{id}/offers/{offerId}/select
    ↓
  Optional Redis SETNX lock:ride:{rideId}  (select contention only)
    ↓
  Firestore transaction (verify owner/state/offer PENDING/not expired/requestVersion/assignedDriverId null → write DRIVER_ASSIGNED + agreedFareMinor)
    ↓
  Firestore outbox event record committed with state change
    ↓
  Async projector/publisher
    ├── RTDB rideSignals/{rideId} update
    ├── RTDB remaining-driver cleanup
    ├── Pub/Sub publish
    └── FCM fallback
    ↓
  All listening drivers see invalidation → request card disappears
    ↓
  Passenger RTDB / Firestore listener → shows driver info
    ↓
  FCM fallback (if RTDB listener not active)
```

---

## 7. Location Architecture

- **Foreground:** 2s interval, 10m distance filter, HIGH_ACCURACY
- **Active trip (driver):** 1s interval, 5m filter, BEST accuracy
- **Idle driver:** 5s interval, 20m filter, BALANCED
- **Passenger (pickup):** Point-in-time; not streamed
- **Accuracy threshold:** Reject if horizontal accuracy > 50m
- **Stale threshold:** Mark stale if no update in 8 seconds (active trip)
- **GPS smoothing:** Kalman filter in Dart; applied server-side for trip reconstruction
- **Out-of-order protection:** GPS `locationSeq` is independent of ride version and durable event version; client and server discard stale location packets per ride-stream
- **Backward movement prevention:** Passenger map renders only monotonically increasing seq positions

---

## 8. Fare Algorithm

See `docs/algorithms/fare-engine.md` for full formulas.

### Recommended Fare Formula

```
R = B + (D × ratePerKm) + (T × ratePerMin) + tollEstimate + airportFee
    × categoryMultiplier
    × clamp(demandMultiplier, 1.0, 1.8)
    × nightAdjustment (1.0 | 1.15)

R = round(R / 10) × 10   // round to nearest Rs 10
R = max(R, minFare)
R = min(R, sanityBoundary)
```

Where:
- B = base fare (per category)
- D = route distance in km (from Google Routes API)
- T = estimated trip duration in minutes
- ratePerKm, ratePerMin = zone/city/category specific
- demandMultiplier = derived from recent booking rate in zone (min 1.0, max 1.8)
- Historical market median used to bound outliers

**Passenger may offer a price.** Server may enforce a configurable `OfferBoundPolicy` (example defaults 0.70R–2.50R). Those ratios are anti-abuse bounds, **not** the pricing model. Recommended fare is guidance. Trip price is later `agreedFare` from the selected offer.

Fare is **snapshotted** at ride creation (`pricingSnapshot` document) and **never silently recalculated** after passenger confirms.

---

## 9. Matching Algorithm

See `docs/algorithms/matching-engine.md` for detail.

### Candidate Generation (Redis GEO + deterministic waves)

```
GEORADIUS geo:drivers:{city} {pickupLng} {pickupLat} {radius} km ASC COUNT 100
```

Filter candidates:
1. Online (RTDB presence)
2. `driverStatus == "approved"`
3. `vehicleStatus == "approved"`
4. Category matches request
5. Not on active ride
6. Not suspended
7. Location age < 15 seconds
8. Location accuracy < 50m
9. Within service area

### Ranking Score

```
score = 0.40 × (1 - normalizedETA)
      + 0.20 × (normalizedRating / 5.0)
      + 0.15 × (1 - normalizedDistance)
      + 0.10 × (1 - normalizedCancellationRate)
      + 0.10 × (1 - normalizedNoShowRate)
      + 0.05 × completedRidesBonus

Sort descending by score, then dispatch in configured waves:

- Wave 1: top 5 candidates, small radius, short response window
- Wave 2: next 10 candidates if still unresolved
- Wave 3: next 15 candidates if still unresolved
```

Deterministic formula; no ML in Phase 0–13. ML evaluation in Phase 14.

---

## 10. Atomic Assignment Algorithm

See `docs/algorithms/ride-assignment.md` and `docs/algorithms/offer-model.md`.

Dispatch presents the request. Driver Accept/Counter creates a **pending offer**. Assignment is **passenger select**:

```
1. Passenger sends POST /rides/{rideId}/offers/{offerId}/select
2. Server validates JWT + App Check + passenger owns ride
3. Optional Redis SET lock:ride:{rideId} passengerId NX EX 30  (select contention only)
4. Firestore.runTransaction():
   a. Assert SEARCHING or OFFERS_AVAILABLE, assignedDriverId == null
   b. Assert offer PENDING, not expired, requestVersion match, driver eligible
   c. Write DRIVER_ASSIGNED, assignedDriverId, immutable agreedFareMinor
   d. Offer SELECTED; siblings SUPERSEDED
   e. Outbox ride.assigned
5. Projector updates RTDB / FCM
```

Driver Accept does **not** assign. Three concurrent accepts create three pending offers.

**Guarantee:** Exactly one authoritative assignment can commit because Firestore transaction/state validation is the correctness barrier.

---

## 11. Ride State Machine

See `ORA_STATE_MACHINE.md` for full detail.

```
DRAFT → ROUTE_READY → REQUEST_CREATED → SEARCHING
  → OFFERS_AVAILABLE → DRIVER_ASSIGNED
  → DRIVER_EN_ROUTE → DRIVER_ARRIVED → RIDE_STARTED
  → RIDE_COMPLETED → RIDE_CLOSED

Cancellation paths:
  SEARCHING / OFFERS_AVAILABLE → EXPIRED (TTL)
  DRIVER_ASSIGNED → DRIVER_CANCELLED / PASSENGER_CANCELLED
  DRIVER_ARRIVED → NO_SHOW (wait TTL)
  Payment lifecycle is separate and begins from agreedFare after `RIDE_COMPLETED`
```

---

## 12. Driver Onboarding Flow

1. Driver switches to "Earn on Ora" in passenger home
2. Driver registration form (name, phone, CNIC)
3. Vehicle information (make, model, year, plate, color, category)
4. Document upload (driving licence, vehicle registration, CNIC copy, vehicle photo)
5. Documents submitted → status: `PENDING_REVIEW`
6. Admin reviews (manual + optional OCR check)
7. Approved → `driverStatus: "approved"` custom claim set
8. Driver can now go online
9. Driver home screen activated

---

## 13. Passenger Flow

1. Splash → Auth (OTP)
2. Home: location shown; "Where are you headed?" search bar
3. Destination selection (Places autocomplete + saved places + recents)
4. Category/vehicle selection + fare shown
5. Fare offer: passenger enters price (recommended fare is guidance)
6. Submit → SEARCHING / OFFERS_AVAILABLE
7. Compare driver offers (price, rating, vehicle, ETA, completed rides)
8. Passenger selects one offer → DRIVER_ASSIGNED (no Direct Mode)
9. Live map: driver en route, ETA countdown
10. Driver arrives → notification
11. Ride starts → real-time navigation view
12. Trip completes → receipt from agreedFare + rating screen

---

## 14. Driver Flow

1. Go online → appear in Redis GEO index
2. Incoming ride card (full-screen or banner): pickup/destination, fare, passenger rating, ETA
3. Accept / Counter / Decline (15-second timer on card)
4. Offer created → wait for passenger selection (not yet assigned)
5. If selected → navigate to pickup
6. Arrive at pickup → tap "Arrived"
6. Passenger boards → tap "Start ride"
7. Navigate to destination (turn-by-turn via Google Maps deep link or in-app)
8. Tap "End ride" at destination → server confirms via geofence
9. Payment processed (cash or digital)
10. Rating screen
11. Return to available state

---

## 15. Payment Architecture

- Primary: Cash (Pakistan market default)
- Digital: JazzCash, Easypaisa (Phase 11)
- Wallet: In-app credit (top-up via PSP)
- Flow: Ride completion creates or updates a `PaymentIntent`; provider interaction is tracked through `PaymentAttempt`; ledger is immutable; wallet balance is derived
- All financial writes server-only
- Cancellation fees: server-calculated based on policy
- Driver payout: batch settled (daily/weekly) via admin payout API

---

## 16. Safety Architecture

- **Share trip:** Passenger shares live link with emergency contacts
- **Emergency SOS:** One-tap; notifies Ora support + stores safety event; optionally calls emergency
- **Verify driver:** Passenger can check plate + photo match before boarding
- **Silent alert:** Shake gesture or hidden button → discreet SOS
- **Route deviation detection:** Server monitors driver path vs route; alerts on significant deviation
- **Emergency contact storage:** Encrypted, server-side

---

## 17. Security Model

See `ORA_SECURITY_MODEL.md` for full detail.

- No client-trusted financial state
- No client-trusted ride state transitions  
- Firestore is the authoritative assignment barrier
- Durable outbox records are required for state-change side effects
- All secrets in Secret Manager
- App Check on every API call
- JWT validation on every API call
- Firestore rules: default DENY; explicit ALLOW minimally
- Audit log on every state change
- Rate limiting at Cloud Armor layer

---

## 18. Observability

See `docs/operations/observability.md` for full detail.

Every critical operation tagged with:
- `requestId` (UUID per API call)
- `rideId`
- `driverId` / `passengerId`
- `eventId`
- `operationId`
- `timestamp`
- `duration_ms`

Latency measurements at T0–T11 (see `ORA_LATENCY_SLO.md`).  
Dashboards: Cloud Monitoring; alerting via PagerDuty.

---

## 19. Testing Strategy

See `docs/testing/test-strategy.md` for full detail.

- Unit tests: fare engine, matching, state machine, auth, location validation
- Integration tests: ride lifecycle, simultaneous accept (3-driver race), offline/reconnect
- E2E: Two physical devices (Device A = passenger, Device B = driver)
- Race condition test: 3 drivers accept simultaneously → exactly 1 wins
- Failure tests: network loss, GPS loss, duplicate events, stale packets

**No feature is marked complete without an executable test proving it.**

---

## 20. Performance Budgets

See `ORA_LATENCY_SLO.md` for full targets.

- Cold start → interactive: < 3.5s P95
- Ride request → driver screen: < 900ms P95 for foreground connected listeners
- Driver accept → passenger sees driver: < 500ms P95 for foreground connected listeners
- GPS → passenger marker: < 500ms P95 for active trip foreground listeners
- Frame render: < 16.67ms (60fps)

---

## 21. Deployment

- Flutter: Google Play Store + Apple App Store
- Backend: Cloud Run (auto-scale; min instances = 2 to prevent cold start)
- Firestore: Multi-region (nam5 for Pakistan/Asia: consider asia-south1)
- RTDB: Single region (asia-south1)
- Redis: Memorystore in asia-south1
- CDN: Cloud CDN for static assets
- CI/CD: GitHub Actions → test → build → deploy Cloud Run → deploy Firebase

---

## 22. Rollback

- Flutter: Play Store phased rollout (5% → 20% → 100%); fast rollback via Store
- Cloud Run: Traffic splitting; `--no-traffic` deploy then manual promote
- Firestore rules: Version-controlled; revert via git + `firebase deploy --only firestore:rules`
- Feature flags: Remote Config for kill switches; zero-downtime rollback

---

## 23. Disaster Recovery

| Scenario | RTO | RPO | Strategy |
|---|---|---|---|
| Cloud Run instance failure | < 30s | 0 | Auto-scaling replaces |
| Firestore outage | < 4h | < 1 min | Multi-region; local Hive cache; degrade gracefully |
| RTDB outage | < 15 min | Ephemeral | FCM fallback for notifications; Firestore polling fallback |
| Redis outage | < 5 min | Ephemeral | Fallback: Firestore transaction for assignment (slower but safe) |
| Complete region failure | < 24h | < 15 min | Multi-region Firestore; manual failover runbook |

---

## 24. Implementation Phases

| Phase | Name | Deliverable | Depends On |
|---|---|---|---|
| 0 | Architecture | This document package | — |
| 1 | Foundation | Flutter project setup, CI, linting, folder structure | 0 |
| 2 | Design System | Ora Design System tokens, typography, components | 1 |
| 3 | Auth | Phone OTP, Google, Apple, App Check, protected routes | 2 |
| 4 | Maps & Location | Maps SDK, GPS, geocoding, autocomplete, polylines | 3 |
| 5 | Pricing Engine | Fare calculation, route cost, demand multiplier, snapshot | 4 |
| 6 | Driver System | Onboarding, documents, approval flow, vehicle | 3 |
| 7 | Ride Request | Passenger booking flow, fare offer, submission | 4, 5 |
| 8 | Dispatch Engine | Matching, candidate generation, driver notifications | 6, 7 |
| 9 | Realtime | RTDB listeners, atomic assignment, invalidation, reconnect | 8 |
| 10 | Trip | Live map, navigation, state transitions, completion | 9 |
| 11 | Payments | Wallet, JazzCash, Easypaisa, receipts, payouts | 10 |
| 12 | Safety | SOS, share trip, emergency contacts, route deviation | 10 |
| 13 | Testing | Full test suite, race condition tests, E2E | 10 |
| 14 | Performance | Profiling, Firestore read reduction, render optimization | 13 |
| 15 | Production | Security audit, pen test, App Store submission, monitoring | 14 |

---

## 25. Acceptance Criteria Per Phase

### Phase 1 — Foundation
- [ ] Flutter project runs on Android emulator and iOS simulator
- [ ] CI pipeline runs on every commit (lint + test)
- [ ] Folder structure matches architecture doc
- [ ] No secrets in code
- [ ] `flutter analyze` returns 0 errors

### Phase 2 — Design System
- [ ] Color tokens match Ora prototype (navy #12182B, gold #D4A756, teal #1F9C82)
- [ ] Sora + Inter fonts load correctly
- [ ] OraButton, OraCard, OraTextField widgets exist and are documented
- [ ] Storybook-style widget catalog screen exists in dev
- [ ] Dark mode renders correctly

### Phase 3 — Auth
- [ ] Phone OTP flow works end-to-end
- [ ] Google Sign-In works on Android
- [ ] Apple Sign-In works on iOS
- [ ] App Check passes on real device
- [ ] JWT stored in secure storage
- [ ] Protected routes redirect unauthenticated users
- [ ] Unit tests: token validation, route guard

### Phase 4 — Maps & Location
- [ ] Map renders on home screen
- [ ] User location shown
- [ ] GPS updates at correct interval
- [ ] Autocomplete returns places
- [ ] Route polyline renders between two points
- [ ] ETA displayed accurately
- [ ] Battery drain test: < 5% per hour in idle mode
- [ ] Integration test: stale location detection

### Phase 5 — Pricing Engine
- [ ] POST /pricing/estimate returns fare within 400ms P95
- [ ] Fare formula unit tests pass (all categories, zones, demand levels)
- [ ] pricingSnapshot written to Firestore on ride create
- [ ] Snapshot is immutable (server rejects any client write)
- [ ] Fare rounding to Rs 10 correct
- [ ] Min/max fare bounds enforced

### Phase 6 — Driver System
- [ ] Driver onboarding 4-step flow completes
- [ ] Documents upload via signed URL
- [ ] Admin can approve/reject in admin panel
- [ ] `driverStatus: "approved"` custom claim set after approval
- [ ] Driver home screen appears only after approval
- [ ] Unit tests: document validation, status transitions

### Phase 7 — Ride Request
- [ ] Passenger can create a ride request end-to-end
- [ ] Fare shown and adjustable within bounds
- [ ] Request appears in Firestore with correct schema
- [ ] Integration test: request created successfully
- [ ] Invalid requests rejected (missing destination, out-of-bounds fare)

### Phase 8 — Dispatch Engine
- [ ] POST /drivers/nearby returns candidate list in < 150ms
- [ ] Filtering: online, approved, correct category, no active ride
- [ ] Ranking score applied correctly
- [ ] Drivers within radius receive FCM + RTDB signal
- [ ] Integration test: 3 drivers receive request simultaneously

### Phase 9 — Realtime
- [ ] Atomic assignment: exactly one driver wins in 3-driver simultaneous accept test
- [ ] Losers receive 409 immediately
- [ ] Stale ride cards disappear from other driver screens within 500ms
- [ ] Passenger sees assigned driver within 500ms
- [ ] Reconnect test: driver drops network, reconnects, assignment still correct
- [ ] Offline test: passenger offline; sees correct state on reconnect

### Phase 10 — Trip
- [ ] Driver marker moves smoothly on passenger map (no backward jumps)
- [ ] ETA countdown updates in real time
- [ ] State transitions work: DRIVER_EN_ROUTE → DRIVER_ARRIVED → RIDE_STARTED → RIDE_COMPLETED
- [ ] Server validates all transitions (client cannot skip states)
- [ ] E2E test on two physical devices

### Phase 11 — Payments
- [ ] Cash payment flow completes
- [ ] JazzCash integration tested in sandbox
- [ ] Easypaisa integration tested in sandbox
- [ ] Wallet top-up works
- [ ] Receipt generated correctly
- [ ] Driver earnings updated correctly
- [ ] No double-charge on retry

### Phase 12 — Safety
- [ ] Share trip link works
- [ ] Emergency SOS creates safety event in Firestore
- [ ] Route deviation detected and logged
- [ ] Emergency contacts saved encrypted

### Phase 13 — Testing
- [ ] ≥ 80% unit test coverage on fare engine, state machine, matching
- [ ] 3-driver race condition test passes 100 times
- [ ] All failure scenarios in test-strategy.md have automated tests
- [ ] E2E device matrix test passes

### Phase 14 — Performance
- [ ] Cold start < 3.5s on mid-range Android (P95)
- [ ] T0→T6 < 900ms (P95) measured with observability tooling
- [ ] T6→T11 < 500ms (P95)
- [ ] Frame jank rate < 1%
- [ ] Firestore reads < 20 per cold session

### Phase 15 — Production
- [ ] Security audit complete
- [ ] App Check enforced in production
- [ ] No secrets in source code (scanner passes)
- [ ] Play Store submission approved
- [ ] App Store submission approved
- [ ] Monitoring dashboards active
- [ ] PagerDuty alerts configured
- [ ] Runbook documented for all critical failure scenarios

---

## 26. What MUST NOT Be Implemented Yet (Phase 0)

- No Flutter feature code
- No Firebase project configuration changes
- No backend code
- No database writes
- No package installations
- No API keys
- No production environment changes
- No fake success states or mock ride logic
- No ML models
- No payment SDK integration
- No App Store submission

**Phase 0 output is documentation only. Stop here.**
