# Ora Architecture Audit

Date: 2026-11-24 · Scope: full repo read-only inspection
(`backend/auth-service`, `mobile/`, Firebase config, deploy scripts, CI).
Branch: `devin/1794389046-orange-profile-merge`; working tree also
contains the uncommitted `cost-optimization-local` changes.

Finding labels: **[VC]** verified in code · **[VCL]** verified in cloud
(prior audits) · **[CALC]** calculated · **[ASM]** assumed · **[RT]**
requires testing.

---

## 1. System shape

```
Flutter app (Riverpod, go_router, dio)
  ├─ Firebase Auth (phone OTP) + App Check (prod enforced)
  ├─ RTDB listener: tripLocations/{rideId}/latest (active trips only)
  └─ HTTPS → Cloud Run ora-auth-service (Express modular monolith)
        ├─ /v1/auth, /v1/rides, /v1/drivers, /v1/location,
        │  /v1/pricing, /v1/device-tokens, /v1/delivery-config
        ├─ /v1/internal/* (worker-token sweeps + nearby + FCM outbox)
        └─ Firestore (authority) + RTDB (trip location projection)
             + FCM Admin Messaging (data-only nudges)
Cloud Scheduler → Cloud Run Jobs → /v1/internal/* (per-minute sweeps)
```

There is **no chat, no reels/media feed, no Firebase Storage usage, no
payments backend, no microservices**. Marketplace UI (logistics /
rental / services) exists as honest empty states only. Those audit
sections are therefore **Not applicable** — recorded, not invented.

## 2. Backend API surface [VC]

| Router | Endpoints | Auth | Notes |
|---|---|---|---|
| `/v1/auth` | register, me, PATCH profile, mode | Firebase JWT + App Check + 60/min | mode switch is transactional, ghost-driver guarded |
| `/v1/rides` | create, list, /open, /invited, invites accept/decline, get, offers CRUD+select+withdraw, lifecycle (en-route/arrive/start/complete/close), courier stops/settlement/disputes, ratings | same | idempotency-keyed mutations; state machine enforced server-side |
| `/v1/drivers` | onboarding, go-online/offline, availability, device-tokens | same | availability is Firestore-authoritative |
| `/v1/location` | POST /update | same | N2A stream cursor + geo projection |
| `/v1/pricing` | POST /estimate | same + stricter 10/min | writes pricingSnapshots doc per call |
| `/v1/device-tokens` | POST/DELETE | same | passenger FCM tokens |
| `/v1/internal` | 8 sweep endpoints + `/sweeps/all` + nearby + dispatch-tick | `X-Ora-Worker-Token` (≥16 chars, constant-time-ish compare) | fail-closed when unconfigured |

Health: `GET /healthz` unauthenticated. JSON body limit **32 kb**
globally (`app.ts:95`).

## 3. Data architecture [VC]

- **Authority:** Firestore only. `users`, `drivers`, `rides`,
  `rideOffers`, `rideDispatchWaves`, `outboxEvents`,
  `idempotencyRecords`, `pricingRules`, `pricingSnapshots`,
  `locationStreams`, `driverDeviceTokens`, `passengerDeviceTokens`,
  `driverInviteResponses`, `ratings`, `disputes`, `deliveryConfig`,
  `cities`, `savedPlaces` (client-writable, owner-scoped).
- **Derived geo index:** `geoDrivers/{driverId}` — merged doc
  (lat/lng + marker JSON + `lastLocationTs`/`freshUntilMs`/`accuracy`
  twins + optional `ls*` merged cursor). One write per accepted idle
  packet when `LOCATION_IDLE_MERGED_CURSOR` is on.
- **RTDB:** `tripLocations/{rideId}/latest` + `rideAccess/{rideId}/{uid}`
  ACL; `geoPresence`/`locationStreams` RTDB backends exist behind
  `GEO_BACKEND`/`LOCATION_STREAMS_BACKEND` flags (default `firestore`).
- **Rules:** `firestore.rules` is fail-closed (catch-all deny; only
  `users` self-read and `savedPlaces` owner access). `database.rules.json`
  gates `tripLocations` reads via `rideAccess`. Admin SDK bypasses —
  all authoritative mutations go through the API. **Sound.**
- **Indexes:** `firestore.indexes.json` covers all hot queries incl.
  `geoDrivers` `freshUntilMs` variants (deployed to cloud per prior
  audit [VCL]).

## 4. Ride matching & location pipeline [VC]

- Presence: client publishes idle fixes per `PresencePublishPolicy`
  (30 s stationary / 10 s moving / 8 s invite-boost / keepalive /
  backoff; flag `ORA_ADAPTIVE_PRESENCE`, default OFF).
- Server per packet: eligibility (15 s `DriverEligibilityCache`) →
  optional trip-authz ride read → stream cursor accept (Firestore tx
  or merged into geoDrivers tx) → best-effort RTDB trip projection →
  geo marker write. Steady state merged: **1R+1W** per packet.
- Matching: `georadius` bbox query + server-side freshness floor +
  haversine sort + batched `getAll` users/drivers + chunked busy-ride
  prefetch; `minFreshUntilMs` when adaptive flag on.
- Dispatch: waves 10→15→25 km, 5 s cadence, ≤3 waves, ≤30 invites,
  20 s invite TTL; create-once `rideDispatchWaves` docs + transactional
  ride cursor; outbox → FCM projector (PENDING-first scan, lease
  reclaim, dead-letter).
- Invite revalidation: `loadInviteRevalidationContext` batched
  snapshot (N3 latency hardening, local-only).

## 5. Notifications & realtime [VC]

- FCM data-only nudges: `RIDE_DISPATCH_INVITE`, `RIDE_UPDATE`
  (13-event allowlist). At-least-once; poll is the correctness floor.
- Client polling is bounded everywhere it exists: offers inbox
  2→3→5 s (6-min cap), active ride 3→5→8 s (4-h cap), driver assigned
  ride similar. **Driver invite discovery has NO periodic poll** —
  see gap GAP-001.
- RTDB `onValue` listener only during active trips, gated by ride
  state; malformed payloads and permission errors degrade softly.

## 6. Mobile architecture [VC]

- Riverpod (Notifier/autoDispose) + go_router + dio; repository
  pattern per feature (auth, driver, ride, marketplace stubs,
  saved_places, safety, payments stub).
- `ApiClient` retry policy: GET/HEAD + explicitly-idempotent only,
  3 attempts, exp backoff from 300 ms; 401 → single token-refresh
  retry. **No retry storms.**
- Location: `geolocator` fused stream; presence publisher owns idle
  cadence; trip publisher (4 s min) owns trip cadence; mutual
  suppression via providers. Foreground service keeps publishing in
  background (verified on-device Oct 30).
- Startup: Firebase init → optional emulator hosts (debug only) →
  AppConfig → App Check activate → runApp. Frame-timing logger is
  opt-in dart-define.
- Maps: `google_maps_flutter` + `maplibre_gl` POC/preview; style
  loader fetches map style with 12 s timeout.
- Place search: Nominatim primary, Google Places fallback, ≥3-char
  debounce (350 ms estimate debounce on pin moves).

## 7. Infrastructure & deploy [VC]/[VCL]

- Cloud Run `ora-auth-service` (prod, maxScale 10, 1 vCPU/512 Mi,
  minScale 0, 300 s timeout) + `-staging` (maxScale 2–3).
- Deploy scripts build `--source=.` → **builds whatever is in the
  working tree** (documented risk; clean-worktree deploy required).
- Prod deploy script already: clears VPC connector, removes
  `REDIS_URL` secret, sets `REQUIRE_APP_CHECK=true`,
  `ORA_ENV=production`, wires Maps + worker-token secrets,
  `FIREBASE_DATABASE_URL` when present in `.env`.
- Cost-opt flags are NOT yet in the deploy script's `ENV_VARS` —
  must be added when enabling (documented in cost plan §G).
- CI: Flutter analyze+test+debug APK, backend typecheck+vitest+ride
  proof, Firestore rules tests. Pinned Flutter 3.35.6.
- Scheduler/worker topology per prior cloud inventory [VCL]: prod
  schedulers paused; staging coalesced scheduler paused after window.

## 8. What is NOT in this codebase (explicitly)

| Requested area | Status |
|---|---|
| Main/private chat, messaging, encryption | **Not implemented** — no collections, routes, or UI |
| Reels, media feed, video/image upload, thumbnails | **Not implemented** — only avatar picker (base64) |
| Firebase Storage / buckets / media lifecycle | **Not used** |
| Payments, wallets, payouts execution | Schema-denied stubs only (`paymentIntents`, `walletAccounts` etc. exist in rules as deny; no service code) |
| Cloud Tasks / Pub-Sub | Not used — sweeps via Scheduler→Jobs→HTTP |
| Redis/Memorystore runtime | Removed from code path; instances still provisioned in cloud pending deletion approval |

## 9. Architecture strengths observed

- Fail-closed everywhere that matters: startup guards (emulator
  requirement, prod App Check), worker-token boundary, rules catch-all,
  eligibility re-checks at match AND invite time.
- Idempotency is systematic: `Idempotency-Key` + `idempotencyRecords`
  on all mutations; create-once wave docs; CAS outbox leases.
- Bounded everything: polling caps, sweep batch limits, scan caps,
  invite caps, rendered-invite cap (ANR fix documented).
- Correctness layered for location: client cadence → server
  `freshUntilMs` → invite-time revalidation → `N3_MAX_FIX_AGE_MS`
  honest-position cap.
