# Ora — Current State (Authoritative Snapshot)

**Status:** CURRENT  
**Evidence date:** 2026-10-19 (reconciled; see note below)  
**Git tip at documentation:** `master` @ `521e8b9` (verify with `git log -1`)  
**Rule:** Code + executable proofs outrank historical markdown. If this file conflicts with older docs, **this file wins** until updated with new code evidence.

> **2026-10-14 reconciliation:** statements that said "5C device pending", "5D+ deferred", "N2B/RTDB not implemented", or "no outbox projector/FCM consumer" were stale and are corrected below. Verified 2026-10-14 evidence: `MAP3_I_MAP1SMOKE_CLOSEOUT_REPORT.json`, `FCM_ORDERING_FIX_PHYSICAL_VERIFY_REPORT.json`, `passenger_fare_offer_physical_followup_report.json`, `TWO_ACTOR_LIFECYCLE_RATINGS_CLOSEOUT.json` (all under `mobile/.e2e_artifacts/`).
>
> **2026-10-19 note — staging outage:** `ora-auth-service-staging` is currently **down** (health 503/500; Cloud Logging: "billing is disabled for this project"). Scheduled sweeps and all API traffic are unavailable until billing is restored. Physical NO_SHOW wait-clock proof was attempted and is recorded as BLOCKED — see `docs/audits/ORA_MASTER_ROADMAP_AUDIT.md` §0 addendum (2026-10-19).

Read this first in any new Cursor/engineering session. Then follow links to phase docs, architecture maps, and diagnostics.

---

## A. Project identity

| Concern | Actual |
| ------- | ------ |
| Product | **Ora** — P2P offered-fare ride-hailing (passenger + driver in one Flutter app) |
| Backend | `backend/auth-service/` — Express modular monolith (auth + rides + drivers + location + Redis GEO) |
| Mobile | `mobile/` — Flutter (Riverpod, go_router, Firebase Auth / App Check) |
| Identity | Firebase Auth ID tokens verified by Admin SDK |
| Durable SoT | **Firestore** (`firestore.rules`, `firestore.indexes.json`, emulator port **8181**) |
| Redis | **Optional** via `REDIS_URL` — N2C GEO projection only (`ioredis`) |
| RTDB | **Implemented** — `src/rtdb/` (`admin_trip_location_rtdb.ts`, `memory_trip_location_rtdb.ts`); `firebase_database` client SDK in `mobile/pubspec.yaml`; tripLocations projection + ACL physically verified (L2 reports) |
| Outbox | Firestore `outboxEvents` + **FCM dispatch projector** (`src/delivery/dispatch_fcm_projector.ts`) — PENDING-first scan, leftover-budget CLAIMED reclaim (fix verified 2026-10-14) |

**Start here for diagnosis:**

| Need | Document |
| ---- | -------- |
| Location pipeline | [`docs/architecture/N_LOCATION_FLOW.md`](architecture/N_LOCATION_FLOW.md) |
| Request traces | [`docs/architecture/N_REQUEST_FLOWS.md`](architecture/N_REQUEST_FLOWS.md) |
| Symptom → fix | [`docs/diagnostics/BACKEND_TROUBLESHOOTING.md`](diagnostics/BACKEND_TROUBLESHOOTING.md) · [`MOBILE_E2E_TROUBLESHOOTING.md`](diagnostics/MOBILE_E2E_TROUBLESHOOTING.md) |
| Error codes | [`docs/diagnostics/BACKEND_ERROR_INDEX.md`](diagnostics/BACKEND_ERROR_INDEX.md) |
| Data ownership | [`docs/architecture/DATA_OWNERSHIP.md`](architecture/DATA_OWNERSHIP.md) |
| API surface | [`docs/architecture/API_CONTRACT_INDEX.md`](architecture/API_CONTRACT_INDEX.md) |
| ADRs | [`docs/architecture/DECISION_INDEX.md`](architecture/DECISION_INDEX.md) |
| Engineering rules | [`docs/ENGINEERING_RULES.md`](ENGINEERING_RULES.md) |

---

## B. Current implementation status

Status vocabulary used below:

| Status | Meaning |
| ------ | ------- |
| **IMPLEMENTED** | Routes/services exist and are wired in `createApp` |
| **PARTIAL** | Core code exists; production/Console/client gaps remain |
| **NOT IMPLEMENTED** | No registered route / no writer path |
| **PLANNED** | Docs only |
| **DEFERRED** | Intentionally postponed (named in code comments) |

Live proof column: **PASS** (claimed in phase closure docs on disk), **SCRIPT EXISTS** (not re-run in this doc session), **NOT RUN**, **N/A**, **NONE**.

| Phase | Capability | Status | Implementation | Tests | Live Proof | Next Dependency |
| ----- | ---------- | ------ | -------------- | ----- | ---------- | --------------- |
| 2A | Auth register / me | IMPLEMENTED | `src/routes/auth.ts`, `services/users.ts` | `src/__tests__/auth.test.ts` | N/A | 2C profile |
| 2B | App Check option, rate limit, guards | PARTIAL (dev `REQUIRE_APP_CHECK=false`) | `middleware/auth.ts`, `rate_limit*`, `production_guards.ts` | `security_phase2b`, `production_guards` | Console checklist docs | Prod App Check enforce |
| 2C | Onboarding / PATCH profile | IMPLEMENTED | `routes/auth.ts`, `services/profile.ts`, rules deny client user writes | `profile.test.ts` | Closure doc claims PASS | Ride slices |
| 2E | Ride create / get / cancel / assign | IMPLEMENTED | `rides/ride_service.ts`, `rides/routes.ts` | `rides.test.ts`, `test:ride-proof` | SCRIPT EXISTS (`test:ride-firestore-concurrency`) | 2F+ |
| 2F | Offers create/list/withdraw/select | IMPLEMENTED | `ride_service.ts`, `offer_lifecycle.ts` | rides + offer proofs | SCRIPT EXISTS | 2G |
| 2G | Post-assign progression | IMPLEMENTED | `markEnRoute`…`completeRide` | rides + progression proof | SCRIPT EXISTS | 2H |
| 2H | Ride close | IMPLEMENTED | `closeRide` | close proof | SCRIPT EXISTS | 2I |
| 2I | Ride history list | IMPLEMENTED | `GET /v1/rides`, `list_query.ts` | rides + list proof | SCRIPT EXISTS | 2J |
| 2J | Ride expire sweeper | IMPLEMENTED | `POST /v1/internal/rides/expire-sweep` | `run_phase_2j_unit_proof` | SCRIPT EXISTS | 2K |
| 2K | Offer expire sweeper | IMPLEMENTED | `POST /v1/internal/rides/offer-expire-sweep` | `run_phase_2k_unit_proof` | SCRIPT EXISTS | 2L |
| 2L | Durable `arrivedAt` | IMPLEMENTED | arrive path sets `arrivedAt` once | `run_phase_2l_unit_proof` | SCRIPT EXISTS | 2M |
| 2M | NO_SHOW sweeper | IMPLEMENTED | `POST /v1/internal/rides/no-show-sweep` | `run_phase_2m_unit_proof` | SCRIPT EXISTS | 2N |
| — | Passenger wait-clock UX | IMPLEMENTED + automated-tested | `DRIVER_ARRIVED` → "Driver has arrived" + 1 Hz "Waiting" from server `arrivedAt`; `NO_SHOW` → "No-show recorded" (no invented fees) | `active_ride_ui_test`, `active_ride_view_model_test` | 58 focused tests PASS (2026-10-19); physical proof BLOCKED — staging billing outage | — |
| 2N | Ratings (stars) | IMPLEMENTED | `POST/GET .../ratings` | `run_phase_2n_unit_proof` | **PASS** — two-actor physical (`TWO_ACTOR_LIFECYCLE_RATINGS_CLOSEOUT.json`, both directions persisted) | N-series |
| M0 | Open-ride discovery | IMPLEMENTED | `GET /v1/rides/open` chronological | `open_discovery.test.ts`, `run_phase_m0_unit_proof` | SCRIPT EXISTS | N3 ≠ M0 |
| N1 | Driver go-online/offline | IMPLEMENTED | `drivers/*` | `driver_availability.test.ts`, `run_phase_n1_unit_proof` | SCRIPT EXISTS (`test:driver-availability-firestore`) | N2A |
| N2A | Location accept + cursor | IMPLEMENTED | `location/*` | `run_phase_n2a_unit_proof` | SCRIPT EXISTS (`test:location-update-firestore`) | N2C |
| N2B | RTDB tripLocations projection | **IMPLEMENTED** | `src/rtdb/*` Admin projection; mobile `firebase_database` client | L2 step reports | PASS (`L2_STEP4_PHYSICAL_VERIFICATION_REPORT.json`) | — |
| N2C | Geo projection | IMPLEMENTED — **Firestore-only** `geoDrivers/{driverId}` (lat/lng + marker + `lastLocationTs`/`accuracy` twins); Redis removed 2026-10-21 | `redis/firestore_geo_client.ts`, hooked from location + go-offline | `firestore_geo_client.test.ts`, `geo_projection.test.ts` | NOT DEPLOYED | N3 |
| N3 | Nearby drivers query | **IMPLEMENTED** — lat/lng on `geo:drivers` (city not required) | `GET /v1/internal/drivers/nearby`, `drivers/nearby_service.ts` | `nearby.test.ts`, `run_phase_n3_unit_proof` | SCRIPT EXISTS (`test:nearby-redis-proof`) | N4 |
| N4 | Dispatch / matching waves | **IMPLEMENTED** (MVP) — invite ledger 5/10/15; pickup lat/lng → N3; no auto-assign | `dispatch_wave_service.ts`, internal dispatch-sweep/tick | `dispatch.test.ts`, `run_phase_n4_unit_proof` | SCRIPT EXISTS (`test:dispatch-live-proof`) | **D1** delivery freeze |
| D1 | Dispatch invite delivery (FCM wake) | **IMPLEMENTED (VERIFIED 2026-10-14)** — projector scans `PENDING` first, reclaims expired-lease `CLAIMED` in leftover budget (terminal backlog starvation fix) | `delivery/*`, `POST .../device-tokens`, `POST .../outbox/dispatch-fcm-sweep` | `delivery_d1.test.ts` (incl. ordering tests S1–S8), `run_phase_d1_unit_proof` | PASS — `FCM_ORDERING_FIX_PHYSICAL_VERIFY_REPORT.json` (staging physical) | Continuous ops only |
| Ph 4–5 | Location resolve + pricing estimate + **passenger fare edit (5D)** | **GREEN incl. 5C device + 5D physical** | Flutter GPS+Places+estimate UI + editable offer within bounds; server Routes+estimate+snapshot+offer validation | fare/routes/estimate + Flutter tests | 4A DEVICE GREEN; 5B live Routes GREEN; **5C device PASS** (`p5c_device_proof_report.json`); **5D physical PASS** (`passenger_fare_offer_physical_followup_report.json`, custom Rs 860 vs rec 850) | — |
| Ph 3, 6–15 | Remaining product (payments, safety, etc.) | **PLANNED** | stubs / docs | mobile stubs | NONE | After Ph 4–5 / product priority |

Phase documentation for N1/N2A/N2C/N3/N4/D1: [`docs/implementation/n-series/`](implementation/n-series/).  
N3 closure: [`implementation/n-series/N3-nearby-planning.md`](implementation/n-series/N3-nearby-planning.md).  
N4: [`implementation/n-series/N4-dispatch-planning.md`](implementation/n-series/N4-dispatch-planning.md).  
D1 freeze (next): [`implementation/n-series/D1-dispatch-delivery-planning.md`](implementation/n-series/D1-dispatch-delivery-planning.md).
---

## CURRENT FRONTIER

```text
CURRENT FRONTIER
```

1. **Last completed verification milestone (2026-10-14):** **two-actor staging lifecycle + both-actor ratings — GREEN_SEGMENTED** (`TWO_ACTOR_LIFECYCLE_RATINGS_CLOSEOUT.json`; ride `5e1a8232-c4ee-45dd-8972-3d2170558aba` closed with passenger 5★ / driver 4★ persisted). Also closed in the same window: **FCM outbox ordering fix** (PENDING-first scan), **MAP-3 `I_map1Smoke`** (harness flake → GREEN), **Phase 5D passenger fare edit** (physical PASS, custom Rs 860 vs recommended 850).
2. **Passenger device auth baseline:** VERIFIED (OTP → onboarding → Home → relaunch).
3. **Passenger Ride Request:** **Phase 4A GREEN + 5C device PASS + 5D physical PASS** — Flutter calls estimate, shows PKR, passenger can edit offer within server bounds, sends `pricingSnapshotId` + `city` + `passengerOfferMinor` on create.
4. **Passenger wait-clock / NO_SHOW UX:** **IMPLEMENTED + automated-tested (2026-10-19)** — wait label derives only from server `arrivedAt`; physical proof attempted but BLOCKED by staging outage (billing disabled).
5. **Next implementation slice:** TBD — roadmap §5/§6 ranks executed; see updated audit addendum.
5. **4B/5B:** **IMPLEMENTED / VERIFIED** — live Google Routes proof passed; MemoryDb estimate + snapshot proofs passed.
6. **5A:** **IMPLEMENTED** — `calculateFare` + `PricingRulesRepository`.
7. **5C:** **IMPLEMENTED + DEVICE PASS** — `PricingRemoteDataSource`, review UI, city suggestion/picker, capabilities from live estimate (`p5c_device_proof_report.json`).
8. **D1:** **IMPLEMENTED / VERIFIED** — FCM wake path + outbox ordering fix (`FCM_ORDERING_FIX_PHYSICAL_VERIFY_REPORT.json`).
9. **N4:** **IMPLEMENTED**.
10. **N2B / RTDB:** **IMPLEMENTED** — `src/rtdb/` projection + `firebase_database` client; L2 physical verified.
11. **City / coverage:** `rides.city` + `pricingRules/{city}_{category}` metadata (not matching gate); Flutter sends suggested/selected city slug.
12. **Still deferred:** invite-poll; Redis demandMult; surge/tolls; payments/safety/intercity phases; release signing (owner keystore).
13. **Profile-mode frame timing:** **CAPTURED + OPTIMIZED (2026-10-19)** — `PROFILE_FRAME_TIMING_MAP_REPORT.json` (856 samples baseline) → post-opt `LOCN_NAMING_PERF_OPT_CLOSEOUT.json` (1129 samples: raster med 7.86→7.20ms, total med 13.35→12.19ms, total p95 37.33→33.80ms). Optimization: 3D tilt + building extrusions now expanded-mode-only; post-fit tilt is an instant `moveCamera` (was a second 450ms `animateCamera`). Note: enable with `ORA_FRAME_TIMING=true` — `bool.fromEnvironment` ignores `=1`.
14. **Current-location naming:** **UX hardened (2026-10-19); name resolution BLOCKED by project billing** — key audit: correct key is `AIzaSyCdEpWc…` ("API key ", apiTargets include Places New, no app restrictions); Places API enabled; but `ora-app-d8112` has `billingEnabled: false` (linked billing account closed) → all paid Maps calls 403, same as Cloud Run. Old builds also embedded the wrong key (Firebase Android key `AIzaSyD7c36…` → `API_KEY_SERVICE_BLOCKED`). App surfaces honest unresolved state ("Location selected" + "Retry name lookup", GPS preserved). Unblock = owner re-links an open billing account, then rebuild with `ORA_GOOGLE_PLACES_API_KEY` from `local.properties`.
15. **Realtime smoothness Phase 1 (MAP-RT + NOTIF-RIDE-NUDGE):** **IMPLEMENTED + unit-tested (2026-10-19)** — (a) `DriverMarkerInterpolator` gives presentation-only smoothing of the active-ride driver marker between valid/fresh RTDB fixes (700ms segments; snaps on >150m discontinuity, stream restart, stale/invalid data, state transition, recenter; ticker stops when idle/invisible). RTDB coords remain authoritative — interpolation never feeds publishing, state, pricing, or camera identity. (b) `DispatchFcmService` now emits `RideFcmNudge` for non-invite FCM messages carrying `rideId` (eventId-deduped); `fcmRideNudgeProvider` feeds 500ms-debounced `refresh()` hints into passenger `ActiveRideViewModel` + `DriverAssignedRideViewModel`. Push payloads are never state; HTTP polling is unchanged as authoritative fallback. **Caveat:** no backend ride-state push projector exists yet (FCM is dispatch-invite-only) — nudge path is client-ready and inert until backend emits `{data:{rideId}}` messages. Physical marker/latency measurement BLOCKED by staging outage. Evidence: `REALTIME_PHASE1_CLOSEOUT.json` (29 tests incl. 9 interpolator + 5 nudge + 4 VM-nudge).
16. **Saved Places + Recent Destinations (Phase 2):** **IMPLEMENTED + on-device verified (2026-10-19)** — `features/saved_places/` (entities, pure policy, `PassengerPlacesStore` port, `SecurePassengerPlacesStore` on SecureStorage, `PassengerPlacesViewModel`). Storage decision: SecureStorage keys `ora.saved_places.v1.{uid}` / `ora.recent_destinations.v1.{uid}` — durable, uid-scoped, wiped on logout (`deleteAll`) → no cross-account leakage, no new dependency. Compose pane shows saved rows under untouched pickup/destination fields + recents under destination; selection is instant (zero network — coords already resolved); proposal card gets "Save place" (Home/Work slots + custom); rows get edit → rename/remove sheets. Recents record only on explicit `confirmDestination` (dedup ≤75m/placeId, cap 8). `ResolvedPassengerLocation.displayName` carries user names UI-only (never sent as `address`); `PassengerLocationSource.recent` added. Verified on SM-A325F: save→persist→instant apply→confirm→recent all work. 10 focused tests PASS.
17. **FCM ride-state push:** client nudge path inert by design until backend exists. Scoped design doc: `docs/design/FCM_RIDE_STATE_PROJECTOR_DESIGN.md` — mirrors D1 projector; event allowlist, passenger+driver recipient resolution via `rides/{id}` (+ `offers/{id}` for offer.selected), identifiers-only payload. **Backend blocker found:** device-token registration is driver-only (`driverStatus=='approved'` gate) — passengers need a token path (parameterize `DeviceTokenService` or parallel collection). NOT implemented/deployed.
18. **Driver Earnings + Ride History (Phase 3):** **IMPLEMENTED + on-device verified (2026-10-19)** — new `DriverEarningsView` + `DriverEarningsViewModel` + pure `computeDriverEarnings` aggregator. Reuses `GET /v1/rides?status=completed` (driver scope is server-side: `assignedDriverId == caller uid`; no new endpoint). Auto-scans up to 200 completed rides (50/page, `scanCapped` flag labels partial totals; `Load more` continues), pulls-to-refresh replaces, cursor dedupes. **Honest money semantics:** the only verified field is `agreedFareMinor` (gross trip fare on the selected offer) — UI calls it "Trip fares", never payout/net; missing fares counted and excluded with an explicit note; payout/commission shown as *not recorded*. Period tiles: Today / Last 7 days / Completed count. `fromDriverJob`/`fromOpenRide` card captions corrected from "Your earnings" → "Trip fare" (was mislabeling gross fare). Verified on SM-A325F via extended local stub (driver mode): Rs 1130 total, Today Rs 650 / 1 trip, 7d Rs 1130 / 2 trips, 3 completed, missing-fare + payout-gap notes render; error/retry state shown live. Evidence: `p3_driver_earnings.png`, `DRIVER_EARNINGS_CLOSEOUT.json`. 13 focused tests PASS.
19. **Map-preview "key not configured" regression (2026-10-19):** **RESOLVED — build flag, not code.** Ad-hoc `flutter build apk` stub builds omitted `--dart-define=MAPLIBRE_TILE_KEY`; `MapPreviewConfig` resolves it build-time only (local.properties is not runtime-read). Rebuilt debug APK with the define from `android/local.properties` → tiles + pins + full compose confirm flow verified on SM-A325F (`p3_map_preview_fixed.png`). Canonical path: `scripts/build_staging_apk.sh` injects it automatically — raw builds must copy that script's full define set.
20. **Driver payout model — IMPLEMENTED at launch policy (2026-10-19):** `src/pricing/fee_policy.ts` + `selectOffer` derives `driverPayoutMinor`/`platformFeeMinor`/`payoutCurrency` atomically inside the select tx (`feePolicies/{city}_{category}` → `_global` lookup; resolution `APPLIED`/`LAUNCH_DEFAULT`/`UNAVAILABLE`; launch fee NONE → payout = fare when data valid, nulls otherwise). Completion never recomputes; no backfill. `publicRide` gained a server-derived `viewer` gate — payout internals (`driverPayoutMinor`/`platformFeeMinor`/`payoutCurrency`/`feePolicyResolution`) are **driver-only**; passenger select/GET/list responses omit them while `agreedFareMinor` is unchanged. Client: `Ride` entity + earnings aggregator track payout vs fare-only bases separately — hero shows "Driver payout" only when payout-backed. 11 new backend tests (+1 role-gating regression, 12 total) + 3 new mobile tests; suite 469/469 & driver suite green. Details: `DRIVER_PAYOUT_MODEL_PLAN.md` §Implementation record, `DRIVER_PAYOUT_MODEL_CLOSEOUT.json`.
21. **FCM Ride-State Projector (NOTIF-RS-PUSH):** **IMPLEMENTED + unit-tested (2026-10-19); NOT deployed, no live push verified.** New `RideStateFcmProjector` (`src/delivery/ride_state_fcm_projector.ts`) mirrors D1 mechanics for the 13-event closed allowlist; emits identifiers-only `{type:RIDE_UPDATE, rideId, eventId}`. Recipients resolved server-side from `rides/{id}` (`rideOffers/{id}` fallback for `offer.selected`); tokens union `driverDeviceTokens` + new `passengerDeviceTokens`. New passenger route `POST/DELETE /v1/device-tokens` (role-gated); new worker route `POST /v1/internal/outbox/ride-state-fcm-sweep`; scheduler script updated but **not run** (billing still disabled). Client: passenger token sync post-frame on `HomeShellView`; clears on sign-out. 17 new backend tests + 1 client parse test; 457 backend tests pass. Live E2E pending billing + redeploy.
22. **Intercity service type (INTERCITY-ENTRY):** **IMPLEMENTED + unit-tested (2026-10-19)** — passenger compose now exposes the already-supported backend `serviceType` axis. `RideRequestUiState.serviceType` (`'ride'` default) → estimate request + create body (was hardcoded `'ride'`); `seedServiceType` honors `?service=intercity` deep-link; `selectServiceType` invalidates + refetches pricing (stale-guard tracks `_estimateServiceType` since the estimate response doesn't echo it). Home: Intercity promo card (eyebrow now "NOW AVAILABLE") + Services-grid tile enter compose as intercity; `_ServiceTypeSelector` chips (City ride | Intercity) render in compose **and** review. Courier/Move remain honest "Coming later" — different product semantics, not faked. Zero backend changes needed — `estimate_service.ts` validates `ride|courier|intercity|move` and `createRide` already persists the field; drivers see it via existing `historyServiceTypeLabel`/`open_ride_display`. 5 new VM tests + 2 widget tests; `ride_request_view_model_test` 42/42, `ride_request_ui_test` 14/14, `analyze lib/` clean. **E2E verification pass (same day):** `createRide` now enum-validates `serviceType` and rejects `PRICING_SNAPSHOT_MISMATCH` (422) when body serviceType/category disagree with `snapshot.inputs` — server-side stale-snapshot guard, backward compatible with snapshots lacking the inputs. Both active-ride trip cards show "service · Category"; created-view unchanged (unreachable — submit goes straight to offers inbox). Backend **471/471**, VM tests **44/44**.
23. **Pickup Location Naming + Confidence UX (LOCN-NAME-UX):** **IMPLEMENTED + unit/widget-tested + on-device geocoder verified (2026-10-19)** — the "Location selected" gap from #14 now has a no-billing fallback. `DeviceGeocoderPort` + `GeocodingDeviceGeocoder` wrap the native Android Geocoder via `geocoding ^5.0.0` (instance API — `Geocoding().placemarkFromCoordinates`/`isPresent()`; no API key, no GCP billing). `FallbackPlaceSearch` decorates `GooglePlacesHttpSearch` at DI: Places first; on throw OR on a success without a usable address → device label composed from real placemark fields (`devicePlacemarkLabel`, max 3 parts, deduped, never invented); total failure rethrows the **primary** error so the honest unresolved state + "Retry name lookup" remain. `ResolvedPassengerLocation.horizontalAccuracyMeters` carries `Position.accuracy` (excluded from `==` — fix-quality metadata, not identity); proposal card shows "GPS fix accuracy ±N m" only when reported, kept separate from address confidence; unresolved copy now states the honest adjustment path (search/suggestions; map preview is display-only, no pin-drag). Naming never moves the pin — resolved address attaches to the original GPS coords; `retryPickupNameLookup` reuses them (no GPS re-acquire). **On-device:** `integration_test/device_geocoder_smoke_test.dart` ran on SM-A325F (Android 13) — real impl returned "Plot n, Sher Ali Road, Aitchison Society" for 31.46/74.26. Places/Maps API keys still blocked by project billing (staging down unchanged) — the device geocoder is the working name path until billing restores. 10 new tests (label composer, fallback decorator, VM accuracy/coord-preservation/retry) + 1 widget test; focused suite **69/69**, `analyze lib/` clean. Closeout: `PICKUP_LOCATION_NAMING_CONFIDENCE_CLOSEOUT.json`.
27. **INFRA CHANGE (2026-10-21):** Billing account re-opened + converted to paid; `ora-app-d8112` and `novexa-4876f` both `billingEnabled: True`. **$1 budget alerts created on both projects** (email at 50/90/100% — alerts only, GCP has no hard cap). **All 12 Cloud Scheduler jobs PAUSED** (they were driving every-minute Cloud Run Job executions; resume per-job with `gcloud scheduler jobs resume` when verifying — left paused to keep idle cost ~$0). Redis + connector were briefly deleted then **restored per owner request**: `ora-staging-vpc` connector recreated (us-central1, e2-micro, 2/3, range 10.8.0.0/28), both Redis instances recreated BASIC 1GB (`ora-staging-n3-redis` 10.116.204.219, `ora-production-n3-redis` 10.81.149.155) via `scripts/wire_staging_redis.sh` / `wire_production_redis.sh` — secrets `ora-staging-redis-url` v9 + `ora-production-redis-url` v2 updated to the new hosts, staging revision `ora-auth-service-staging-00027` re-deployed and serving. Verified: staging `/v1/rides/open` → 401, prod → APP_CHECK_REQUIRED. GEO nearby-drivers (N2C/N3) functional again (projection repopulates from driver location updates). **Ongoing cost reality: ~$84/mo standing (2× Redis + connector) + scheduler ticks when resumed** — pause schedulers + delete Redis/connector is the only path to ~$0; owner chose full restore. Accrued charges since Sep 29 re-enable are NOT visible via CLI — check Console → Billing → Reports.

28. **Firestore geo store (GEO-STORE-FIRESTORE):** **IMPLEMENTED + unit-tested (2026-10-21); NOT deployed, real-Firestore latency/index behavior unverified.** `createFirestoreGeoClient(db)` (`src/redis/firestore_geo_client.ts`) implements the full `RedisGeoClient` port against one collection: `geoDrivers/{driverId}` carries geo membership (`lat`,`lng`) AND the online marker (`markerValue`,`markerExpiresAtMs`, top-level `lastLocationTs`/`accuracy` twins parsed from marker JSON, `expiresAt` Timestamp twin) — **merged single-doc schema, 1 write per accepted GPS packet**. `georadius` = lat/lng bounding-box query + optional `minLastLocationTs` server-side freshness floor (Firestore range filter; Redis ignores — caller marker checks identical) + haversine filter + distance-asc sort + count slice + 5000-doc scan cap (now logs `GEORADIUS_SCAN_CAPPED`) + `markerValue` piggybacked on hits (N3 skips MGET entirely in Firestore mode — `diag.redisGetCount=0` verified). Required index updated: `geoDrivers (lat ASC, lng ASC, lastLocationTs ASC)` — NOT deployed. **N3 busy-prefetch fix:** `prefetchBusyDriverIds` now filters `state in BUSY_RIDE_STATES` server-side (was reading ALL historical rides per candidate — unbounded); chunk size 30→7 to satisfy Firestore's 30-disjunction cap (7 drivers × 4 states = 28); chunks run in parallel. Existing `rides(assignedDriverId,state)` index covers it. **N4 radius expansion (inDrive-style):** `N4_WAVE_RADII_KM = [10,15,25]` via `waveRadiusKm()` — replaces flat `N4_RADIUS_KM=10`; wave doc + outbox payload record the searched radius; nearest-first ordering, invite caps (5/10/15/30), requestVersion and create-once wave-doc idempotency all unchanged. **Seq-guard fix:** per-`locationStreamId` seq + cross-stream `lastLocationTs` (idle↔trip interleave). Selection unchanged: `GEO_STORE=firestore` env opt-in; deploy scripts clear VPC connector + REDIS_URL secret in firestore mode. **Driver idle presence (mobile):** `DriverPresencePublisher` publishes idle-mode updates ~10s while signed-in+online+foreground; availability data source + `GET /v1/drivers/availability` + real home toggle + shell lifecycle. **Tests: backend 505/505** (+10 this round: georadius markerValue ×2, minLastLocationTs, del-clears-twins, N3 mget-skip diagnostic, disjunction bound, closed-ride-history, wave radii assertions, radius expansion, nearest-first, waveRadiusKm table); tsc + flutter analyze clean. **memoryDb fixes this round:** added `<`/`>` ops; fixed `FieldValue.delete` sentinel detection (real SDK exposes `methodName` getter not `_methodName` — prior del tests passed coincidentally). **Pre-existing mobile failures (untouched files):** 2× ride_history_ui, 1× home_shell_driver_gate (FCM [core/no-app]), 2× passenger_shell_ui (un-overridden passengerPlacesProvider). **Known limits:** memoryDb ≠ real index enforcement; cross-region latency unmeasured; bounding box still reads out-of-circle docs (~27% geometric over-read); docs without parseable marker lack `lastLocationTs` → excluded by freshness floor (fail-closed, correct). Nothing deployed; Memorystore+connector still live/billing. Closeout: `.e2e_artifacts/FIRESTORE_GEO_CLIENT_IMPLEMENTATION.json`.
26. **Driver open-rides browse filters (OPEN-RIDES-FILTERS):** **IMPLEMENTED + unit/widget-tested (2026-10-19); no device/staging proof.** `GET /v1/rides/open` now accepts `serviceType` (enum-validated) + `category` (trimmed non-empty ≤64 chars) — exact-match narrowing applied to discoverable rides before sort/cursor/page; never changes eligibility, matching, or dispatch. **Cursor binding now hashes the active filter set** — a cursor minted unfiltered cannot paginate a filtered list and vice versa (cross-filter replay → 400, verified). Mobile: params threaded through data-source→repo→use-case; VM gains `serviceTypeFilter`/`categoryFilter`/`hasActiveFilters` + setters that refetch page 1 (same value = no-op); `loadMore`/`refresh` carry active filters (seq-guard discards stale responses). View adds Service + Category chip rows (`OraChip`, mirrors history rows; labels via `historyServiceTypeLabel` + `kRideCategoryOptions`) and an honest filtered-empty state ("No open rides match" + Clear filters) distinct from the true empty state. Backend **478/478** (+7 filter/cursor-binding tests); `slice_m_driver_test` **37/37** (+6); driver feature suite 137 pass; `analyze lib/` clean. No device (adb offline); no staging (billing). Closeout: `OPEN_RIDES_FILTERS_CLOSEOUT.json`.

25. **Passenger compose draft persistence (COMPOSE-DRAFT):** **IMPLEMENTED + unit-tested (2026-10-19); physical process-death proof not run.** Mid-compose work (pickup/destination points + labels + texts, category, serviceType, passenger offer draft) now survives navigation away / process death — restores into a pristine compose on next build. New `RideComposeDraft` domain model (JSON round-trip + corruption-tolerant `tryFromJson` + 24h staleness rule), `RideComposeDraftStore` port, and `SecureRideComposeDraftStore` on `SecureStorage` keyed per authenticated uid (uid isolation; no uid → no reads/writes at all). VM integration: async restore fires at build, applies **only** when compose is still pristine (any passenger input or a deep-link seed wins over the draft), bumps all search/resolve generations so in-flight results can't overwrite restored endpoints, and auto-refetches pricing when the restored draft is already submittable. Persist is debounced (600 ms) across all mutators; emptied compose clears the stored draft; successful `createRide` clears it. **Pricing snapshots are never persisted or trusted** — estimates always refetch fresh; restored `confirmed` endpoints become proposals (confirm requires a fresh estimate). Self-review audit caught + fixed two defects: stale-state capture across `_invalidatePricing()` during restore, and cached-uid writes that could leak a draft across an account switch (uid now read fresh at write time). Tests: 9 new in `ride_compose_draft_test.dart` (model round-trip/corrupt/staleness boundary, store round-trip/uid-isolation/corrupt/clear, VM restore/stale-discard/pristine-precedence/debounced-persist/no-uid no-op) — **76/76** focused green with VM+UI suites; `analyze lib/` clean. No backend change; no pricing/matching/lifecycle/payout surface touched. Closeout: `COMPOSE_DRAFT_PERSISTENCE_CLOSEOUT.json`.

24. **Set-point-on-map pin adjust (MAP-PIN-ADJUST):** **IMPLEMENTED + unit/widget-tested (2026-10-19); on-device map-tap proof BLOCKED (adb link dropped mid-run).** Passenger can now adjust pickup/destination by tapping the compose map — closes the "no pin adjustment path" limitation recorded in #23. `RideRequestUiState.pinAdjustTarget` (UI-only, never persisted) arms set-point mode; proposal cards get "Adjust on map" → auto-expands the map; `RideMapPreview` gains `pinAdjustLabel`/`onMapPointSelected`/`onCancelPinAdjust` + `MapLibreMap.onMapClick` wiring + a "Tap the map to set {endpoint} / Cancel" banner (gestures unaffected — a drag never fires onMapClick). `vm.setPinFromMapTap` makes the tapped lat/lng the proposal with `source: mapPin`, reverse-geocoded via the existing Places→device fallback; naming failure keeps honest unresolved state + retry (`retryPickupNameLookup` now accepts mapPin; new `destinationNameUnresolved` + `retryDestinationNameLookup` for parity). Coordinates authoritative — naming never moves the pin; `pinAdjustTarget` cleared on every competing selection path + map collapse so a stray tap can't overwrite a proposal. Pricing invalidates normally on point change. 7 new VM tests + 1 widget test; `ride_request_view_model_test` **51/51**, `ride_request_ui_test` **16/16**, `analyze lib/` clean; ride suite 338 pass / 2 pre-existing `ride_history_ui_test` failures (unmodified files, documented in earlier addendum). On-device: `integration_test/map_pin_adjust_smoke_test.dart` harness written (real view + real fallback, fake GPS only) — run attempted twice; first stalled awaiting app launch, second failed at install when the SM-A325F's adb link dropped (`device not found`); pending a stable USB session. Closeout: `MAP_PIN_ADJUST_CLOSEOUT.json`.
25. **Must NOT be touched without a new freeze:** ride/offer SM; fabricating pricing snapshots; N3/N4 matching redesign; N2A/N2C write semantics.

31. **CI diagnosis + fix (CI-2026-10-22):** The ❌ `2/3` on every commit since Oct 14 = `firestore-rules` ✅ + `auth-service` ✅ + `flutter` **cancelled after 6h** (GitHub job cap), NOT a test failure — `dart run build_runner build` hung at step 5 in every run while analyze/test/apk were skipped. Root cause: floating `channel: stable` — the runner's newer Dart SDK vs pinned toolchain (local 3.35.6 builds in 19-23s incl. cold `build_runner clean`). Fix (uncommitted): `flutter-version: '3.35.6'` pinned in `.github/workflows/ci.yml`, `timeout-minutes: 30` job + 15 on the build_runner step (never another 6h burn), `--verbose` for future logs, 15-min timeouts on the other two jobs. **Two latent CI failures also found & fixed before they could hit:** `flutter analyze` (whole project, not lib/) had 2 warnings + 11 infos — all fatal in this Flutter version: `Future.delayed` inference, `Map` raw type, `SemanticsFlag.hasFlag` deprecated → `flagsCollection`, unused `dart:ui`/`semantics.dart` imports, `fake_async` missing from dev_deps, `prefer_const_*` ×6. After fixes: `flutter analyze` = "No issues found", touched test files all pass, `npm ci --dry-run` clean. NOT yet pushed — awaiting authorization; the in-flight run on `f821d8d` still uses the old workflow and will cancel at the 6h cap.

30. **Final audit + 5-failure resolution (AUDIT-2026-10-21):** Full Flutter suite is now **776/776** (was 771/5). Root causes found and fixed — none were unexplained "pre-existing": (a) `GeocodingDeviceGeocoder` constructed `geo.Geocoding()` eagerly in its constructor → `GeocodingPlatformFactory.instance!` NPE in tests (no plugin) — now lazy (`_resolved ??= _injected ?? geo.Geocoding()`); this was a **real product bug** — any container wiring the port without calling it crashed; (b) `DispatchFcmService.syncDriverTokenRegistration`/`syncPassengerTokenRegistration`/`clearRegisteredToken` called `FirebaseMessaging.instance` unguarded → `[core/no-app]` escaped an unawaited driver-shell mount call — now `_messagingOrNull` degrades gracefully (invites still arrive via HTTP listing); (c) `RideCardSecondaryStatus` was unbounded in `RideCardHeader`'s Row → real 45px `RenderFlex` overflow on long raw-state labels (`RIDE_STARTED`) — now both badges are `Flexible` + secondary text ellipsizes; (d) ride-history test had 3 stale assertions from the filter/payout reworks (`Closed` chip no longer exists — filters are all/completed/cancelled; `Fare` caption → `Trip fare`; `Completed` matched chip+badge — scoped finders). Backend 521/521 ×3 runs; `rides.test.ts` had ONE transient 404 on offer create (mechanism not found — memoryDb commits synchronously, no fake timers; non-reproducible, flagged for monitoring). Stale Redis exports removed from `launchd_entry.sh`/`run_local_device_backend.sh`; `run_n3_staging_seed_job.sh` no longer wires Redis secret/connector (Firestore seeder). **BILLING: `ora-app-d8112` and `novexa-4876f` both `billingEnabled=false` (re-verified via `gcloud beta billing projects describe`); `project-c573799b`/`single-ripsaw-498112` unreachable (deleted or access lost).** Resources that still EXIST despite disabled billing: Cloud Run `ora-auth-service` + `ora-auth-service-staging` (suspended; cannot serve), VPC connector `ora-staging-vpc` (e2-micro×2, READY — will bill ~$35/mo if billing re-enabled), `run-sources-ora-app-d8112-us-central1` bucket; Memorystore Redis (2× BASIC-1GB per #27), 12 paused Scheduler jobs, and Redis/Maps/internal-worker secrets are billing-gated to enumerate — **presumed still provisioned; ~$84/mo resumes on billing re-enable. Zero charges while billing is off.**

29. **Firestore-only geo + driver invitation flow (GEO-REMOVE-REDIS / N4-INVITE):** **IMPLEMENTED + unit-tested (2026-10-21); NOT deployed; index + latency unverified.** (a) **Redis runtime removed** — `ioredis` dep + `src/redis/client.ts` deleted; `GEO_STORE`/`REDIS_URL` env selection gone; `index.ts` always builds `createFirestoreGeoClient` (log `geo_init store=firestore`). The `RedisGeoClient` *port name* is retained as the geo abstraction (memory fake still implements it for tests); all "Redis GEO" label comments corrected. Redis-specific scripts deleted (`wire_*_redis.sh`, `run_*_redis_proof.ts`, n3 benchmark VPC tooling); `run_dispatch_live_proof.ts` + `run_n3_firestore_investigation.ts` converted to the Firestore client. Deploy scripts no longer wire Redis secret/connector — **scripts edited, never run**; live Memorystore/VPC resources untouched in cloud (still provisioned per #27 — deletion is a separate owner-approved op). **Backend is Firestore-only geo — no silent fallback, no unbounded scan** (bounding box + `minLastLocationTs` range + 5000 cap + `GEORADIUS_SCAN_CAPPED`). (b) **Driver invitation flow** — dispatch wave docs now carry `inviteExpiresAt = min(now + N4_INVITE_TTL_MS=20s, ride.expiresAt)`; included in `ride.dispatch.wave_completed` outbox payload + `DISPATCH_INVITE` FCM data. New `InviteService` (`src/rides/invite_service.ts`): `GET /v1/rides/invited` (array-contains scan ≤100, in-code sort, page ≤25; returns invite + ride card + `serverNowMs` for clock-skew); `POST /v1/rides/:rideId/invites/:waveId/accept` (tx-checked ownership `driverIds ∋ caller`, `now < inviteExpiresAt` → `422 INVITE_EXPIRED`, ride state/requestVersion recheck → delegates to `RideService.createOffer` with deterministic idempotency — **accept creates a fare offer; passenger still selects**); `POST .../decline` (durable `driverInviteResponses` doc, idempotent). Dispatch continues to later waves after decline/expiry — expiry only gates that driver's response. Open-rides browse stays unrestricted (agreed). Mobile: `driver_invites_view_model` + invites section on open-rides screen — countdown from server `inviteExpiresAt` + bounded server/device offset, auto-dismiss at 0, single-flight accept/decline, `INVITE_EXPIRED` removes card; FCM `DISPATCH_INVITE` parses `inviteExpiresAt` as wake-up hint only. Backend **521/521** (+16 invite tests incl. expiry/ownership/duplicate/race/already-assigned/dispatch-continuation; `memoryDb` gained `array-contains` + `<`/`>` + `FieldValue.delete` sentinel fixes); mobile invite tests all green; `tsc` + `flutter analyze` clean; full Flutter suite 771 pass / 5 pre-existing failures (driver gate, passenger shell ×2, ride history ×2 — unchanged files). **Unverified:** real Firestore `array-contains` cost/indexes, cross-wave FCM timing on device, Samsung physical countdown, staging concurrency.

### Nearby meaning (frozen product intent in architecture docs)

> **Nearby** = drivers near **passenger pickup** (Redis GEO candidate generation).  
> **Not** = open rides near the driver.  
> Open rides are **M0** chronological Firestore discovery (`GET /v1/rides/open`).

### Location stack (actual)

```text
Firestore = durable business SoT (rides, availability, locationStreams cursor)
           + geo projection `geoDrivers` (N2C write; N3 bounding-box read — Redis removed 2026-10-21)
RTDB     = ephemeral trip projection (N2B) — IMPLEMENTED (`src/rtdb/` + `firebase_database`; L2 physical verified)
```

---

## Registered HTTP surface (summary)

See full index: [`API_CONTRACT_INDEX.md`](architecture/API_CONTRACT_INDEX.md).

- Auth: `POST /v1/auth/register`, `GET /v1/auth/me`, `PATCH /v1/auth/profile`
- Rides + offers + ratings + internal sweeps
- Drivers: `POST /v1/drivers/go-online`, `POST /v1/drivers/go-offline`
- Location: `POST /v1/location/update`
- Internal nearby: `GET /v1/internal/drivers/nearby` (worker token; N3)
- Health: `GET /healthz`
- **Not registered (by design for N3 MVP):** `GET /v1/drivers/nearby` (JWT/passenger)

---

## Proof commands (backend)

From `backend/auth-service` (after local `npm ci` — do not run as part of doc-only tasks unless asked):

| Slice | Unit / memory | Live |
| ----- | ------------- | ---- |
| N1 | `npm run test:phase-n1-unit-proof` | root `npm run test:driver-availability-firestore` |
| N2A | `npm run test:phase-n2a-unit-proof` | root `npm run test:location-update-firestore` |
| N2C | `npm run test:phase-n2c-unit-proof` / `firestore_geo_client.test.ts` | live proof: `run_dispatch_live_proof.ts` (Firestore client) |
| N3 | `npm run test:phase-n3-unit-proof` / `nearby.test.ts` | same — geo client is Firestore (Redis proofs deleted) |
| 5A | `npm run test:phase-5a-unit-proof` / `fare_calculator.test.ts` + `pricing_rules_repository.test.ts` | N/A (seed is Admin/ops) |
| 4B/5B | `npm run test:phase-5b-unit-proof` / `google_routes_provider` + `pricing_estimate` tests | `GOOGLE_MAPS_SERVER_KEY=… npm run test:phase-5b-live-proof` |
| Rides | `npm test`, `npm run test:ride-proof` | root `npm run test:ride-*-firestore-*` |

CI (`.github/workflows/ci.yml`): Flutter + `auth-service` vitest + `test:ride-proof` + Firestore rules. **Does not** run N1/N2A/N2C/N3 unit proofs or Redis live proofs (vitest may include `nearby.test.ts` if present in suite).

---

## Stale documentation warning

These are **historical** and must not be used as live status:

- [`docs/audits/ORA_COMPLETE_ARCHITECTURE_AUDIT.md`](audits/ORA_COMPLETE_ARCHITECTURE_AUDIT.md) — claims Redis/rides absent (pre–Phase 2E / N-series)
- Auth-service README was auth-era only (updated to point here)
- Phase 2J/2K **investigation** docs that say go-online/Redis “missing” — superseded by N1/N2C code
- Much of [`docs/ORA_MASTER_PLAN.md`](ORA_MASTER_PLAN.md) remains aspirational — use the COMPLETED / FRONTIER sections added there

---

## Flutter / client gaps (evidence)

- Phase **4A** adds `geolocator` + Places HTTP (requires `ORA_GOOGLE_PLACES_API_KEY`)
- Phase **5C** adds `POST /v1/pricing/estimate` client + review fare UI + `city` on create (device PASS)
- Phase **5D** adds editable passenger offer within server bounds (physical PASS 2026-10-14)
- Maps SDK integrated — MAP-1…MAP-3 + half-screen compose map physically verified; no Routes client (Routes remain server-only)
- Driver UI uses **open rides** (M0), not GEO nearby; driver progression lives under drawer → **My trips** → assigned ride detail
- `firebase_database` + `firebase_messaging` are in `pubspec.yaml` (N2B/L2 + D1)

---

## Zero-cost local development (Firebase emulators)

Runs the full backend + Flutter debug app with **$0 incremental cloud cost** —
no billing, no deploys, no paid Google APIs.

**Start:**

```bash
# 1. Emulators (firestore :8181, auth :9099, rtdb :9000 — firebase.json)
firebase emulators:start --project ora-app-d8112

# 2. Backend on :8080 (sets emulator hosts, ORA_FCM_SENDER=none,
#    ORA_ROUTING_PROVIDER=haversine, unsets GOOGLE_MAPS_SERVER_KEY + ADC)
backend/auth-service/scripts/dev_emulator_backend.sh

# 3. Local tick loop — replaces Cloud Scheduler (dispatch waves + FCM sweep)
backend/auth-service/scripts/dev_local_ticks.sh
```

**Physical device (USB, `adb reverse`):**

```bash
backend/auth-service/scripts/dev_adb_reverse.sh   # api :8081→:8080, auth :9099, rtdb :9000
cd mobile && flutter run --debug -d <serial> \
  --dart-define=ORA_API_BASE_URL=http://127.0.0.1:8081/v1 \
  --dart-define=ORA_ALLOW_HTTP_API=true \
  --dart-define=ORA_ENV=development \
  --dart-define=ORA_FIREBASE_EMULATOR_HOST=127.0.0.1
```

Note: FlutterFire remaps `127.0.0.1`→`10.0.2.2` (emulator alias) — on a
**physical** phone bind emulators to `0.0.0.0` and pass the Mac's LAN IP as
`ORA_FIREBASE_EMULATOR_HOST` instead; `adb reverse` only covers the API.

**Scripted proof:** `backend/auth-service/scripts/run_local_emulator_e2e.ts` —
28 checks: emulator auth, driver approval/online, geo projection, dispatch
waves 10→15→25 km, invite list + 20s server-authoritative expiry, accept →
offer → passenger select → full lifecycle → ratings, idempotency.

**What cannot run locally:** real FCM delivery, Google Routes pricing
(haversine instead), Places autocomplete (no key), MapTiler tiles (no key —
placeholder style). Emulator data is wiped on restart — re-seed users +
`pricingRules` before each session.

**Phase-2 device audit (2026-10-22):** physical Accept AND Decline captured
on SM-A325F — `INVITE_ACCEPT`→offerId then `INVITE_DECLINE` logged
server-side from on-device taps. Pull-to-refresh on Open rides now refreshes
BOTH the open list and the invite feed (`_refreshAll` in
`driver_open_rides_view.dart`) — previously invites only re-fetched on
mount/resume or FCM, so a missed/delayed push (or FCM-off local builds) hid
live invitations for the whole session. Measured on-device: create→invited
1.7s, invite TTL ~20s server-authoritative (expired status at 21.97s incl.
poll latency), invite accept 75ms, accept-after-decline →
`INVITE_ALREADY_RESPONDED`, decline replay idempotent, duplicate accept →
same offerId. `STATE_CONFLICT` earlier observed was a genuine 5-min
offer-window expiry (ride `expiresAt`), not a version bug — `requestVersion`
is immutable through dispatch waves (regression-tested in
`dispatch.test.ts`). Driver offline→online cycle verified: offline driver
excluded (`invitedCount: 0` across all 3 waves), re-online re-invited.

**Production-safety incident + fail-closed guard (2026-10-24):** a bare
`tsx src/index.ts` launch once connected to the **real** Firebase project
(`ora-app-d8112`) for ~2 min — sweeps ran, `fcm_sender_init: firebase`, and
one production `outboxEvents` doc (`aeacaade-cf21-…`, a 10-day-old
`ride.dispatch.wave_completed`) was updated to `DELIVERED` at
`2026-10-24T12:37:04Z`. No FCM delivery confirmed (`sent: 0` in all observed
records) but real credentials were present, so attempts were possible; treat
as an incident — no cleanup performed without approval. Fix:
`src/config/firebase_target_guards.ts` runs before `initializeApp` — local
mode now **refuses to start** unless all three emulator hosts are set plus
`ORA_FCM_SENDER=none` and `ORA_ROUTING_PROVIDER=haversine`; verified by
intentional misconfigured launches (exit 1) and a clean emulator boot.
Local scripts no longer source real service-account/Maps credentials.

**Device-verified (2026-10-24, SM-A325F driver + headless AVD passenger):**
full two-actor chain — dispatch invite w/ live countdown → Accept → PENDING
offer → passenger Select → DRIVER_ASSIGNED → driver lifecycle
en-route → arrived → started → completed → closed, mirrored on both UIs;
memory bounded ~505MB PSS. Background/resume: invite card auto-removes on
resume past server deadline (no countdown reset). Network cut (adb-reverse
removed): pull-refresh fails closed with "Cannot reach Ora API" while
retaining last-known cards; recovery refetches. GPS: presence publisher
`accepted: true` ~10-15s cadence with real fixes.

**Zero-cost destination selection (2026-10-24):** `ride_request_view.dart`
now shows "Set pickup/destination on map" in each field's untouched state —
no Places key, saved place, or prior proposal required. Map tap → pin →
device-geocoder name (best-effort, unresolved stays retryable) → confirm.
Verified end-to-end on the emulator UI: pickup via GPS, destination via map
tap ("9, Jubilee Town Housing Scheme, Lahore"), Request Easy → SEARCHING
ride that invited the physical driver — no paid API calls anywhere.

**Post-Redis migration audit (2026-10-24):** repository-wide diff of the
Redis-removal commit `f821d8d` vs parent baseline `521e8b9`, all changed
files audited. External behavior preserved through the `RedisGeoClient`
port; Firestore `geoDrivers/{driverId}` merged doc = GEO membership +
online marker (one write per accepted GPS packet, same as Redis hot path).
Regressions found & fixed this pass:

- `georadius` bounding-box scan cap (5000 docs) returned index-ordered rows,
  not nearest-first — dense fleets could silently hide the closest drivers.
  Fix: recursive quadrant-split on cap hit (depth 4, ≤33 queries), dedup +
  exact haversine + distance sort unchanged. `GEORADIUS_SCAN_CAPPED` still
  logged if a leaf stays capped at the query bound.
- `GET /v1/rides/invited` did `array-contains` + `limit(100)` with no
  orderBy — doc-id order meant a driver with >100 lifetime wave memberships
  could lose their ACTIVE invite. Fix: `orderBy('createdAt', 'desc')` +
  `limit(25)` server-side; new composite index
  `rideDispatchWaves(driverIds ARRAY_CONTAINS, createdAt DESC)` added to
  `firestore.indexes.json`.
- Script-level production safety: backend `index.ts` was guarded but
  standalone scripts using `applicationDefault()` could still fall back to
  ADC and touch the real project. New `scripts/lib/script_env.ts`
  (`assertScriptFirebaseTarget`, same fail-closed semantics) wired into
  `check_driver_online.ts`, `check_driver_device_tokens.ts`,
  `list_searching_rides.ts`. cert()-based staging tools left as-is
  (explicit credential = declared intent).

Not a regression (documented): the Rs 136,470 local test fare was a
test-seed units bug — paisa-scale numbers (`baseFare:16000, ratePerKm:20000,
ratePerMin:200`) entered into rupee-denominated `pricingRules` fields:
`16000 + 5.882×20000 + 14.117×200 = 136,466 → Rs 136,470`. Calculator is
correct; units clarified in `buildPricingRuleSeed` JSDoc + pinned by
regression tests (realistic Lahore ≈ Rs 290, intercity ≈ Rs 7,940, and the
anomalous seed reproducing exactly 13,647,000 minor).

Verification this pass: `tsc --noEmit` clean; vitest **538/538** (8 new:
quadrant-split, scan-cap bound, stale-in-box, invite >100-wave listing,
fare realism ×3, script guard ×4 + backend guard negatives); flutter
analyze clean; flutter test **781/781**; emulator E2E `run_local_emulator_e2e.ts`
**28/28** on fresh emulator (incl. RTDB `tripLocations` projection — a
prior FAIL was the running backend missing `FIREBASE_DATABASE_URL`, not a
code defect); firestore.rules mocha **43/43**, database.rules **9/9**.
Geo benchmark vs emulator (wall-clock, NOT production latency):
projection write p50 10.3ms (1 read + 1 write/packet); findNearby p50
35ms @10 / 37ms @100 / 380ms @1000 (~320 in-box doc reads). Emulator data
is in-memory — `locationStreams` seq cursors persist across runs, so the
E2E needs a fresh emulator per run (stale cursors correctly reject
`locationSeq:1` as SEQUENCE_VIOLATION — validated live).

## Hot-path optimization (post-audit)

Two safe optimizations landed after the audit (all 547 backend tests +
28/28 E2E + 43 rules + 9 RTDB rules still pass on the new path):

1. **Atomic marker guard** (`firestore_geo_client.projectLocation`):
   the stale-packet guard and the geo+marker write now run inside ONE
   Firestore transaction (`markerGuard` callback on
   `ProjectLocationOptions`; memoryRedis parity added). Previously the
   guard was a standalone `get` followed by a separate `set` — a
   check-then-act window where a stale packet could interleave and
   overwrite a fresher projection (idle + trip publishers overlap at
   mode transitions). Same billed ops (1R+1W per accepted packet,
   1R+0W on guard-skip), strictly better atomicity.
2. **Bounded eligibility cache** (`DriverEligibilityCache`, 15s TTL):
   the per-packet `users` + `drivers` reads are now cached. Staleness
   is safe — matching re-checks `drivers/{id}` authoritatively at match
   time, so a just-banned/offline driver can only waste geo writes for
   ≤15s, never become incorrectly matchable. Same-process availability
   transitions invalidate immediately via an
   `onAvailabilityTransition` hook wired in `app.ts`
   (drivers router → location router shared instance). Only successful
   loads are cached (fail-closed). Deliberately NOT cached: trip
   publish authorization (ride-state checks stay fresh — a driver
   must stop publishing within one request of trip completion).

Per-packet ops: **2.07R+2W** measured (cache 29 hits / 1 miss over 30
packets) vs **4R+2W** before ≈ 48% fewer reads, ~33% fewer total ops.
Post-optimization emulator benchmark (`BENCH_FLEETS=10,100,1000,5000`):
- `projection_write_tx_guard` p50 5.8ms / p95 12.4ms (30 samples)
- `full_update_per_packet` p50 11.0ms / p95 15.7ms end-to-end
- `findNearby` p50: 13.7ms @10, 14.3ms @100, 35.2ms @1k, 50.1ms @5k
Rejected as unsafe: skip-writes on unchanged position (the 15s N3
freshness window on `lastLocationTs` vs the 10s publish cadence leaves
no safe skip margin — skipping would let stationary drivers go stale);
a blind write without the guard read (stale cross-stream overwrite).
Documented future option (needs approval, ~25% read cut): merge idle+
trip cursors into one `locationStreams/{driverId}` doc so the geo
write can join the same transaction without a separate guard read.

Revised cost model — honest arithmetic (Firestore $0.06/100k reads,
$0.18/100k writes; idle presence at 10s cadence = 6 pkt/min =
8,640 packets/day per always-online driver; trip packets add +1R ride
auth +1 RTDB write):
- Per driver/day (idle, 24h): ~17.9k reads + ~17.3k writes ≈ **$0.042**
- 10 drivers ≈ $0.42/day (~$13/mo); 100 ≈ $4.2/day (~$126/mo);
  1k ≈ $42/day (~$1.3k/mo); 5k ≈ $210/day; 10k ≈ $420/day (~$12.6k/mo);
  25k modeled ≈ $1,050/day. Dispatch/rides traffic adds ~1-3% at these
  volumes (waves ≈ 200-300 reads/ride). Storage negligible (<$0.10/mo).
- Redis/Memorystore (~$84/mo standing) crossover ≈ **~70 always-online
  drivers** — below that Firestore presence is cheaper; above it the
  old Redis design was. At 10k drivers a dedicated geo store
  (RTDB/Redis/custom) is materially cheaper — flagged, not adopted.
- Free tier (50k reads + 20k writes/day): ~1 always-online driver;
  a ~5-driver × ~4h/day pilot fits under both caps. Zero incremental
  cost during development is met via emulators, not the free tier.
- Trip-mode premium: publishable states only (ASSIGNED→STARTED, ~4-10
  pkt/min) — roughly +50% ops vs idle while active.

---

## RTDB geohash GEO (candidate replacement — local verified)

Implemented 2026-10-24 behind `GEO_BACKEND=firestore|rtdb`
(`src/index.ts` startup selection; unknown values + missing
`FIREBASE_DATABASE_URL` refuse startup — fail closed). Local dev
scripts (`dev_emulator_backend.sh`, `run_local_device_backend.sh`)
default to `rtdb`; the code default and production stay `firestore`
until a staging soak is approved. Rollback is one env var — both
implementations live behind the same `RedisGeoClient` contract.

Design (`src/rtdb/rtdb_geo_client.ts` + `src/rtdb/geohash.ts`):
- `geoPresence/{driverId}` node per online driver: `{g: geohash(12),
  l:[lat,lng], lat, lng, accuracy, lastLocationTs, expiresAtMs,
  markerExpiresAtMs, markerValue, stream}`.
- Marker guard + write inside ONE RTDB `transaction()` per node —
  same atomic cross-stream protection as the Firestore tx-guard.
- `georadius` = geohash covering-cell queries
  (`orderByChild('g')` + `startAt/endAt` per cell, dedup) → exact
  haversine filter → nearest-first sort. Correctness identical to
  the Firestore quadrant-split path (same candidate sets measured).
- Expiry: `expiresAtMs`/`markerExpiresAtMs` filters in queries (lazy
  eligibility) + `sweepExpired()` storage-hygiene sweeper exposed at
  `POST /v1/internal/geo/presence-sweep` (worker token), driven by
  `dev_local_ticks.sh` slow loop. Verified end-to-end: sweep removed
  3 expired nodes post-backend-restart.
- `database.rules.json`: `geoPresence` is `.read:false/.write:false`
  (server-write-only, admin bypasses rules) with `.indexOn: [g,
  expiresAtMs]` — verified by a new rules test (10/10 RTDB rules).
- `locationStreams` cursors stay in Firestore (durable authority —
  deliberate). Geo projection and cursor are NOT one atomic unit on
  either backend; the accepted-then-project ordering + guard
  semantics are unchanged from the Firestore path.
- Restart recovery: state is external — a restarted backend reads
  `geoPresence` on the next match (verified: backend restart +
  presence-sweep read/write post-restart). Multi-instance: verified
  live — two backend processes (:8080 + :8082, both `GEO_BACKEND=rtdb`)
  share the same `geoPresence`; instance B swept a node that instance
  A then confirmed absent.

Benchmarks (emulator wall-clock — NOT production latency; identical
workloads both backends, `run_geo_benchmark.ts`):

| op | Firestore GEO | RTDB GEO |
|---|---|---|
| projection write tx-guard p50 | 4.2–6.8ms | 3.6–4.0ms |
| full `update()` p50 | 8.3–15.2ms | 6.7–28.0ms |
| findNearby p50 @10 | 15.4ms | 46.9ms (cold first query) |
| findNearby p50 @100 | 16.6ms | 18.7ms |
| findNearby p50 @1k | 22.3ms | 21.4ms |
| findNearby p50 @5k | 28.0ms | 27.6ms |
| findNearby p50 @10k | 109.7ms | **46.7ms** |

Candidate sets identical at every fleet size (7/21/52/52/52).

Billed ops per accepted idle packet:
- Firestore GEO: ~2.07R + 2W → ~$0.042/driver/day (@6 pkt/min).
- RTDB GEO: eligibility cache (~0.07R) + `locationStreams` tx (1R+1W)
  + RTDB tx (uploads free) → ~1.07R + 1W ≈ **$0.021/driver/day —
  ~50% cut**; RTDB downloads only on match queries (≈52 candidates ×
  ~200B ≈ pennies/day). Documented further option (not taken):
  `locationStreams` → RTDB would drop billed ops to ~$0.004/driver/day
  but moves cursor authority off Firestore — needs explicit approval.

Verification: tsc clean; backend 568/568 (+21: 7 geohash, 14 RTDB
client); RTDB rules 10/10; Firestore rules 43/43; Flutter analyze
clean + 781/781; emulator E2E **29/29 on GEO_BACKEND=rtdb**
(incl. geoPresence write, dispatch wave, ~20s invite TTL, guardrails,
offer→select, lifecycle, RTDB tripLocations, ratings, expired-invite
rejection). E2E script gained a `GEO_BACKEND`-aware geo-store check +
a driver presence refresh before the expired-invite ride (the check
previously raced the 15s freshness gate — timing artifact, not a
weakening: an online driver republishes every ~10s).

Remaining (unchanged): real-Firestore/RTDB latency, index performance,
real FCM, Google Routes accuracy — external blockers. RTDB-specific:
dual-instance live soak, staging soak before any production flag flip.

---

## locationStreams → RTDB (cursor migration — local verified)

Implemented 2026-10-24 behind `LOCATION_STREAMS_BACKEND` (defaults to
the `GEO_BACKEND` pairing; explicit override allowed; invalid values +
missing `FIREBASE_DATABASE_URL` refuse startup). Firestore cursor
remains available for rollback via `LOCATION_STREAMS_BACKEND=firestore`.

Design (`src/location/stream_store.ts` + `src/rtdb/rtdb_stream_store.ts`):
- `LocationStreamStore` interface — `accept` (atomic cursor tx),
  `close` (idempotent), `sweepExpired` (hygiene). Firestore impl is the
  ORIGINAL transaction verbatim — semantics byte-identical on both.
- RTDB layout: `locationStreams/{docId}` mirrors the Firestore doc
  (`activeStreamId, lastAcceptedSeq, streamState, previousStreamIds[],
  rideId?, expiresAtMs, createdAt, updatedAt`) — docId = driverId
  (idle) or `{rideId}_{driverId}` (trip).
- `accept` = one RTDB `transaction()` per doc; rejection = abort with
  out-of-band reason → same `SEQUENCE_VIOLATION` 422s (CLOSED, same-
  stream seq, replaced stream). RTDB serializes per-node transactions —
  concurrent publishers/multi-instance stay correct.
- `closeTripLocationStream` / `cleanupTripLocationOnTerminal` route
  through the same store (ride terminal close still sets CLOSED).
- `ExpiresAtCleanupService` delegates `locationStreams` cleanup to
  `store.sweepExpired` — `orderByChild('expiresAtMs')` + `.indexOn`.
- Atomicity analysis (documented, deliberately NOT merged): a single
  tx covering cursor+geo requires folding cursor memory into
  `geoPresence/{driverId}` — offline geo removal would then erase
  previousStreamIds/CLOSED memory and allow stale-stream re-acceptance
  after re-online, and per-ride expiresAt cannot be indexed inside the
  geo node. Two ordered transactions (cursor accept → guarded geo
  project) preserve the exact atomicity of the original Firestore
  design: cursor can never lag geo; a crash between them only delays
  geo by ≤1 packet.

Billed ops per accepted idle packet: **~0.07R + 0W** (eligibility
cache amortized) — was ~1.07R+1W on RTDB geo alone, ~2.07R+2W on
Firestore geo, 4R+2W pre-optimization. Verified live: after a full
29/29 E2E, RTDB `locationStreams` held all 3 cursors (incl. trip
cursor `{rideId}_{driverId}` + previousStreamIds) while Firestore
`locationStreams` had **0 docs**.

Latency note (emulator wall-clock): `full_update_per_packet` p50
48.4ms / p95 71.2ms — two SEQUENTIAL RTDB transactions per packet add
~10–40ms over the Firestore-cursor path (~7–15ms). Trivially within
the 10s publish cadence; production regional latency will differ.

Revised per-packet cost model (@6 pkt/min, 8,640 pkt/driver/day):
- Idle packets: ~605 eligibility reads/day ≈ **$0.0004/driver/day**
- Trip packets (+1 uncached ride-auth read, ~10% of time): +$0.0005
- Effective ≈ **$0.0005–0.001/driver/day ≈ $0.02–0.03/driver/mo** —
  ~97–98% reduction vs the pre-migration ~$0.65/driver/mo GPS pipeline.
- RTDB: uploads free; downloads only on match queries (~52 docs ×
  ~200B ≈ pennies/day); storage ~650B/driver → 10k ≈ 6.5MB ≈ $0.03/mo.
- What still bills: eligibility + trip-auth reads (~$20/mo @1k
  drivers), ride business ops (unchanged), hosting compute, egress,
  auth. NOT free — honest pilot math: a ~5-driver × 4h/day pilot now
  fits comfortably under Firestore free tier for the GPS path; the
  backend host remains the dominant cost at every fleet size.

Verification: backend 581/581 (+13 stream-store tests: seq ordering,
replaced-stream rejection, CLOSED, concurrency, expiry, sweep);
RTDB rules 11/11 (new locationStreams deny test); Firestore rules
43/43; emulator E2E 29/29 on the RTDB cursor path (expired-invite,
trip-auth and sequence guards all exercised against RTDB cursors);
Flutter unchanged (backend-only).

---

## RELEASE GATE — full-system stabilization (2026-11)

Complete inventory + audit of the existing system (no new features).
Issues found & fixed this round:

1. **`scripts/` never typechecked** — `tsconfig.json` includes only
   `src/**/*`; CI ran no `tsc` at all. Fixed: new
   `backend/auth-service/tsconfig.scripts.json` (ESM/NodeNext for
   `import.meta`, strict, `declaration:false`, noEmit-only), 19 real
   semantic errors fixed across 5 scripts (`run_geo_benchmark.ts`,
   `repro_open_rides_live.ts`, `run_phase_n2c_unit_proof.ts`,
   `run_ride_offer_create_firestore_concurrency.ts`,
   `seed_e2e_driver_profile.ts`). New npm scripts `typecheck` +
   `typecheck:scripts`; CI now runs both before `npm test`.
   No script was excluded to make compilation pass.
2. **N2C proof test 9 failing (pre-existing bit-rot)** —
   `run_phase_n2c_unit_proof.ts` test 9 ("homeCity change keeps
   primary; moves legacy shard only") had not run since the
   eligibility-cache refactor. Root cause: `drivers` doc mutation via
   `db.seed` is invisible inside the 15s `DriverEligibilityCache`
   window → stale `homeCity` → legacy-shard `zrem` skipped. Analysis:
   correct-by-design staleness (homeCity is ops-seeded, never
   API-written; legacy `geo:drivers:{city}` shards are never read by
   N3; marker `prevCity` self-heals ≤15s; primary `geo:drivers` is
   city-independent). Fix: `CreateAppOptions.eligibilityCache` is now
   injectable (`options.eligibilityCache ?? new DriverEligibilityCache()`)
   and the test injects `new DriverEligibilityCache(0)` (TTL 0 disables
   `set`). Proof now 11/11. Availability transitions already
   invalidate via `onAvailabilityTransition` (verified `app.ts`).
3. **Ambiguous dispatch comment** — `dispatch_types.ts` line 17 said
   "Wave 1 → 5, 2 → 10, 3 → 15" (invite sizes) next to radii
   `[10,15,25]` — clarified to "Invite capacity per wave". Verified
   authoritative constants: radii **10 → 15 → 25 km**, invite sizes
   **5/10/15**, `N4_INVITE_TTL_MS = 20s` — matches inDrive-style spec.

Re-verification this round (all local, emulators only):
- `tsc -p tsconfig.json --noEmit` + `tsc -p tsconfig.scripts.json
  --noEmit`: both clean (all 63+ scripts now checked).
- Backend suite: **581/581** (40 files) post-changes.
- Emulator E2E `run_local_emulator_e2e.ts`:
  - `GEO_BACKEND=rtdb` (+RTDB cursors): **29/29** — geoPresence,
    invite TTL 20s, offer→select, lifecycle, tripLocations, ratings,
    expired-invite rejection.
  - `GEO_BACKEND=firestore` (+Firestore cursors): **29/29** —
    full rollback path green (`geoDrivers` asserted).
- Concurrency proof `test:ride-offer-create-firestore-concurrency`:
  8/8 (real Firestore txn contention observed).
- `test:phase-n2c-unit-proof`: 11/11 (was 10/11 — now fixed).
- Rules: Firestore 43/43, RTDB 11/11 (unchanged).
- Flutter: analyze clean, 781/781 (unchanged — backend-only edits).
- Backend RSS ~53MB idle.

Rollback drill: backend restarted with `GEO_BACKEND=firestore
LOCATION_STREAMS_BACKEND=firestore` → E2E 29/29 → restarted back to
`rtdb`. Rollback is one env var, verified working.

Remaining locally-unverifiable (production/staging only):
- Real Firestore/RTDB latency + index behavior at scale.
- FCM delivery + retry (sender = none locally).
- Google Routes production accuracy/cost (haversine locally).
- Staging soak + flag rollout; physical Samsung verification of the
  RTDB backend path (device proofs predate the RTDB switch —
  Flutter code unchanged, but the on-device RTDB GEO round-trip is
  not yet device-verified).
- Production hosting/auth/egress/notification costs remain non-zero;
  local dev stays at $0 incremental cloud cost.

---

## How to update this file

When a phase closes:

1. Verify routes + tests + proof scripts on disk.
2. Update the status table and CURRENT FRONTIER.
3. Add/update `docs/implementation/...` phase closure.
4. Do **not** rewrite historical audits; mark them HISTORICAL and link here.
