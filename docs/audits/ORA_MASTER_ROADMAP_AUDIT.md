# Ora — Master Roadmap Audit

**Type:** Read-only audit (no code, config, infra, or dependency changes)  
**Generated:** 2026-10-12T09:50:00Z  
**Git tip inspected:** `master` @ `66a07f0` (`partial working on maps`)  
**Working tree:** Dirty — uncommitted half-screen map UX + MapLibre PoC + related tests/artifacts (not discarded; not treated as merged until committed)  
**Authority rule:** Code + executable proofs in-repo outrank stale narrative docs. `docs/ORA_CURRENT_STATE.md` (2026-09-21) is **stale** relative to MAP/L1–L2/half-screen/staging E2E evidence and must not be used as the live frontier without reconciliation.

---

## 0. Post-audit verification addendum (2026-10-14)

**Update scope:** documentation-only reconciliation against evidence generated after this audit. Prior sections retained for historical context; where they conflict, this section wins.

| Item audited as open | Verified status (2026-10-14) | Evidence |
| ---- | ---- | ---- |
| Passenger fare proposal / edit (Phase 5D) — §5 rank 1, §6 recommended slice | **PHYSICAL PASS** — custom offer Rs 860 vs recommended Rs 850, durable on create and driver-visible | `mobile/.e2e_artifacts/passenger_fare_offer_physical_followup_report.json` |
| MAP-3 physical YELLOW / soft `I_map1Smoke` | **GREEN** — diagnosed as **harness flake, not app defect** (single-shot dumps raced Places reverse-geocode; destination EditText below uiautomator viewport clip; wrong `input text` escape; stale review predicate). Harness corrected in `map2a_physical.py`; physical rerun passes Places + review | `mobile/.e2e_artifacts/MAP3_I_MAP1SMOKE_CLOSEOUT_REPORT.json`, `map3_map1smoke_closeout_review.png` |
| D1 FCM dispatch ordering | **VERIFIED** — projector now scans `PENDING` first and reclaims expired-lease `CLAIMED` only within leftover budget, so terminal `DELIVERED`/`DEAD_LETTER` backlog cannot starve new pending events. Unit tests S1–S8 in `delivery_d1.test.ts`; backend suite 440/440; physical verify on staging | `backend/auth-service/src/delivery/dispatch_fcm_projector.ts`, `mobile/.e2e_artifacts/FCM_ORDERING_FIX_PHYSICAL_VERIFY_REPORT.json` |
| Ratings two-actor physical proof — §5 rank 3, §8 "Low" | **GREEN_SEGMENTED** — one staging ride driven REQUESTED → ACCEPTED → EN_ROUTE → ARRIVED → STARTED → COMPLETED → RIDE_CLOSED with each transition verified in Firestore; both rating docs persisted (`passenger_rates_driver` 5★, `driver_rates_passenger` 4★) | `mobile/.e2e_artifacts/TWO_ACTOR_LIFECYCLE_RATINGS_CLOSEOUT.json`, ride `5e1a8232-c4ee-45dd-8972-3d2170558aba` |

**Important qualification:** the lifecycle+ratings proof is **segmented** — three harness runs of the same ride (fresh request+assign; resumed driver progression; resumed driver rating), not one uninterrupted E2E run. A mid-run adb/uiautomator failure (exit 137) ended the first run before report write; all legs were re-verified server-side.

**Remaining known limitations:** (a) two-actor harness relies on `uiautomator dump`, which is fragile on the emulator (transient exit 137 / cold-restart mid-run; mitigated by retries and resume modes, not eliminated); (b) ~~profile-mode frame timing~~ — **measured 2026-10-19** (`PROFILE_FRAME_TIMING_MAP_REPORT.json`, 856 profile-mode samples); (c) `docs/ORA_CURRENT_STATE.md` carried stale statements (5C device pending, N2B/RTDB not implemented, outbox projector absent) — reconciled in the same closeout.

**Addendum (2026-10-19) — profile-mode frame timing:** numeric gap **CLOSED** — `PROFILE_FRAME_TIMING_MAP_REPORT.json`: 856 real `FrameTiming` samples on SM-A325F profile build (`ORA_FRAME_TIMING=true`, ~69s of map expand/pan/zoom/collapse): buildMs median 0.42 / p95 1.69, rasterMs median 7.86 / p95 18.84, totalMs median 13.35 / p95 37.33 / max 275.69. Prior 0-sample gap root-caused: `bool.fromEnvironment` only accepts `"true"` — `ORA_FRAME_TIMING=1` never enabled the logger (procedure bug, not instrumentation inadequacy; no app-code change). Measured against a local auth stub (staging down).

**Addendum (2026-10-19) — passenger wait-clock / NO_SHOW UX inspection:** the passenger wait-clock already exists — no implementation gap found. `DRIVER_ARRIVED` renders "Driver has arrived" + a 1 Hz "Waiting Xm Ys" label computed only from the server-authoritative `arrivedAt` (immutable; `active_ride_display.dart::arrivedWaitLabel`, `active_ride_view_model.dart::_ensureClock`, `_ArrivedWaitLabel` widget); `NO_SHOW` renders "No-show recorded" + "no fees invented" copy and stops polling as terminal. Automated coverage exists (`active_ride_view_model_test` NO_SHOW polling stop, `arrivedWaitLabel` unit test; `active_ride_ui_test` ARRIVED/NO_SHOW widget tests — 58 focused tests pass). A dedicated physical run was attempted 2026-10-19 (`no_show_wait_clock_e2e.py`) but is **BLOCKED**: `ora-auth-service-staging` returns 503/500 because GCP billing is disabled on the project (Cloud Logging: "billing is disabled for this project"). Physical proof pending infra restoration — `no_show_wait_clock_physical_report.json` not produced.

**Addendum (2026-10-19, second session) — location naming UX + map perf optimization (local-only):**

- **Current-location naming root-caused (key audit completed 2026-10-19):** "Use current location" → GPS ok → `searchNearby` → **HTTP 403 on-device**. Full audit: the correct key `AIzaSyCdEpWc…` ("API key ", uid `c86457a2`) **already allows** `places.googleapis.com` and the API **is enabled** — the real blocker is `ora-app-d8112` `billingEnabled: false` (linked billing account `01F8D7-…` **closed**); the Routes key 403s identically, proving a project-wide billing denial (same root cause as the staging outage). Separately, old builds embedded the **wrong** key (Firebase Android key `AIzaSyD7c36…` → `API_KEY_SERVICE_BLOCKED`) — builds must use `ORA_GOOGLE_PLACES_API_KEY` from `android/local.properties`. No key-restriction change applied (GCP refused narrowing: key has recent `geocoding-backend` usage — left as-is). Unblock = owner re-links an open billing account. App-side hardening shipped: honest unresolved state, "Retry name lookup", 2 km `searchNearby` retry, `debugPrint` diagnostics — retry verified live on SM-A325F; naming remains blocked until billing is restored.
- **Map perf optimization shipped + measured:** evidence-backed A/B isolated 3D tilt + building extrusions as the raster-tail contributor (raster p95 18.84→14.82ms / max 61.56→28.66ms with them off). Change: 3D + buildings now apply **only when the map is expanded** (compact strip is flat 2D; toggles still honored on expand), and the post-fit tilt is an instant `moveCamera` instead of a second 450 ms `animateCamera`. Post-opt profile run (same device/flow): 1129 samples — raster med 7.86→7.20ms, total med 13.35→12.19ms, total p95 37.33→33.80ms, max 275.69→251.02ms. Modest aggregate delta by design — the measurement window is expanded-dominant and expanded keeps 3D fidelity. `totalMs>16.67ms` is a timing descriptor, not a dropped-frame count. `LOCN_NAMING_PERF_OPT_CLOSEOUT.json`, `ft_profile_map_frames_post_opt_run2.log`.

**Addendum (2026-10-19, third session) — Realtime smoothness Phase 1 (MAP-RT + NOTIF-RIDE-NUDGE) implemented:**

- **A — driver marker interpolation (MAP-RT):** `driver_marker_interpolator.dart` (pure, injectable clock) + `active_ride_map.dart` wiring. Presentation-only: 700ms linear segments between valid/fresh RTDB fixes; snaps on ≥150m discontinuity, stream-key restart, out-of-order seq, stale/expired/ineligible data, ride-state transition, recenter, init. Sub-1.5m jitter ignored. Ticker runs only while a segment is active (no continuous work when idle or detached). Server/RTDB coords remain authoritative — interpolation never feeds publishing, ride state, pricing, camera `fitIdentity`, or freshness. 9 focused unit tests pass.
- **B — FCM-triggered ride refresh (NOTIF-RIDE-NUDGE):** `ride_fcm_nudge.dart` parser + `DispatchFcmService.rideNudges` broadcast (eventId-deduped via the existing 200-entry seen set) + `fcmRideNudgeProvider` + 500ms-debounced `refresh()` hints in passenger `ActiveRideViewModel` and `DriverAssignedRideViewModel`. Payloads never treated as state; polling unchanged. **Known gap:** backend FCM today is dispatch-invite-only (`dispatch_fcm_projector.ts`) — no ride-state push projector exists, so the nudge path is client-ready but inert until the backend emits `{data:{rideId,eventId}}` messages (separate, backend-scoped work — was flagged as needing owner approval for a new push contract; client contract is deliberately lenient). 4 VM-level + 5 parser tests pass.
- **Verification:** `flutter analyze lib/` clean; focused suite 29 tests PASS (interpolator, nudge parser, VM nudge wiring incl. burst-collapse + disposed-screen safety); debug APK builds and launches to Home on SM-A325F. **Physical marker-smoothness / push-to-visible latency not measurable** — needs live ride + RTDB + real pushes (staging down: billing closed). `ride_history_ui_test` has 2 PRE-EXISTING failures at HEAD (unrelated; "Completed" label duplicated by card badge vs `findsOneWidget` expectation — predates this work). Evidence: `REALTIME_PHASE1_CLOSEOUT.json`.

**Addendum (2026-10-19, fourth session) — Phase 2: Saved Places + Recents shipped; FCM projector scoped:**

- **Saved Places + Recent Destinations (IMPLEMENTED + device-verified):** new `features/saved_places/` slice — entities (`SavedPlace`, `RecentDestination`), pure policy (`normalizePlaceName`, `upsertSavedPlace` with Home/Work reserved slots + cap 20, `pushRecentDestination` ≤75m/placeId dedup + cap 8), `PassengerPlacesStore` port, `SecurePassengerPlacesStore` (uid-scoped SecureStorage keys; chosen over adding shared_preferences because it's the app's only durable store AND wiped on logout — strongest account isolation), `PassengerPlacesViewModel` (watches `sessionUserProfileProvider`; rebuild+reload on account change). Compose pane: saved rows under untouched pickup/destination fields, recents under destination, all instant-apply with zero network; "Save place" on proposal cards (Home/Work/custom); rename/remove via manage sheet; snackbar feedback. `ResolvedPassengerLocation.displayName` (UI-only user names — `address` stays genuine-only for the create body); `PassengerLocationSource.recent`. Recents recorded only at `confirmDestination` — abandoned searches never recorded. Device-verified end-to-end on SM-A325F (save → persists across navigation → instant apply → "Home" proposal → confirm → "Pinned location" recent on next compose; `p2_saved_places_compose.{png,xml}`). 10 focused tests PASS (policy, store roundtrip/isolation/corrupt-tolerance, VM CRUD/scoping/dedup). Suite: 337 pass / 2 pre-existing history failures.
- **FCM ride-state push — scoped design only (not implemented):** `docs/design/FCM_RIDE_STATE_PROJECTOR_DESIGN.md`. Mirrors the D1 projector (PENDING-first scan, CAS fencing, per-recipient results, dead-letter). Closed event allowlist (assigned/en_route/arrived/started/completed/closed/cancelled/no_show/expired + offer.received/withdrawn/expired/selected); identifiers-only payload `{type:RIDE_UPDATE,rideId,eventId,deliveryEventId}` matching the shipped client contract; recipient = `rides/{id}.passengerId`/`assignedDriverId` (+ `offers/{id}` fallback for offer.selected). **Blocker surfaced:** `driverDeviceTokens` registration is driver-gated — passengers have no token path; design recommends parameterizing `DeviceTokenService` by collection + role gate. Files/tests/routes enumerated in the doc; no code written, nothing deployed.

**Addendum (2026-10-19, fifth session) — Phase 3: Driver Earnings + Ride History shipped; FCM scope estimated:**

- **Driver Earnings (IMPLEMENTED + stub-verified):** `features/driver/domain/driver_earnings_summary.dart` (pure aggregator — only completed states `RIDE_COMPLETED`/`RIDE_CLOSED`, sums verified `agreedFareMinor`, buckets Today/Last-7-days/All-loaded by `completedAt ?? closedAt ?? updatedAt ?? createdAt`, counts missing fares separately, detects mixed currencies) + `driver_earnings_view_model.dart` (reuses `ListRidesUseCase` with `status=completed`, auto-scans ≤200 rides at 50/page, `scanCapped` flag, refresh replaces, cursor dedupe) + `driver_earnings_view.dart` (Trip fares hero, period tiles, missing-fare note, explicit "payouts/commission/net not recorded" disclosure, completed-trips list via `RideCard`, load-more pagination). New `DriverShellPage.earnings` — wired from drawer item (was `_showUnavailable`) and both driver-home earnings affordances (hero + quick tile). **Honest-money fixes:** `fromDriverJob`/`fromOpenRide` fare captions changed `Your earnings` → `Trip fare`; card-level `fareCaption` fallbacks likewise (gross passenger fare is not driver payout — there is no commission/payout model server-side). Authorization is unchanged and server-side: the same `GET /v1/rides` endpoint filters `assignedDriverId == caller.uid` for approved drivers.
- **Backend data gap (documented, not invented):** no payout/commission/net field exists on rides. Smallest honest future change: server derives `driverPayoutMinor`/`commissionMinor` at completion (pricing stays server-authoritative). No date-range filter on the list API — period buckets are computed client-side over the bounded scan and labelled accordingly.
- **FCM projector scope estimate:** added §"Implementation scope estimate" to `FCM_RIDE_STATE_PROJECTOR_DESIGN.md` — token registration parameterization, recipient authz, event allowlist, outbox reuse, tests. Not implemented/deployed.
- **Verification:** 13 focused tests PASS (7 aggregator + 6 VM: completed-only queries, totals, missing fares, scan cap, refresh, error/retry); `ride_card_system_test` updated for honest captions; `flutter analyze lib/` clean; on-device SM-A325F via extended local stub (`driver` mode — approved profile + 3 completed rides, 1 fareless): Earnings renders Rs 1130 total, Today Rs 650/1 trip, 7-day Rs 1130/2 trips, missing-fare + payout-gap disclosures, error/retry state exercised. Evidence: `p3_driver_earnings.png`, `DRIVER_EARNINGS_CLOSEOUT.json`. Real staging data remains BLOCKED (billing closed).

**Addendum (2026-10-19, sixth session) — NOTIF-RS-PUSH ride-state FCM projector implemented (unit-tested, NOT deployed):**

- **Backend projector (IMPLEMENTED):** `src/delivery/ride_state_fcm_projector.ts` + `ride_state_types.ts` — mirrors D1 1:1 (PENDING-first scan with `eventType in` closed 13-event allowlist, expired-lease CLAIMED reclaim, `(leaseOwner, attemptCount)` CAS fencing on delivery + event docs, per-uid/per-token durable results, capped backoff, dead-letter at 10 attempts, invalid-token removal). Payload is identifiers-only `{type:'RIDE_UPDATE', rideId, eventId}` — exactly the shipped client contract. Recipients resolved server-side from `rides/{id}` (`passengerId`/`assignedDriverId`; `rideOffers/{offerId}.driverId` fallback for `offer.selected`) — never caller input.
- **Passenger token path (IMPLEMENTED):** new `passengerDeviceTokens` collection; `DeviceTokenService` gains `registerPassenger`/`clearPassenger`/`listTokensForPassenger`/`deletePassengerTokenByValue` (gate: `role=='passenger'`); new `POST/DELETE /v1/device-tokens` router mounted behind `requireAuth`+rate limit. Driver path byte-identical.
- **Worker route + scheduler:** `POST /v1/internal/outbox/ride-state-fcm-sweep` (same `X-Ora-Worker-Token` gate, `?limit`). `wire_staging_cloud_scheduler.sh` gained the run-job + `*/1` scheduler entries — **script edited only, not executed** (billing disabled).
- **Client (IMPLEMENTED):** `registerPassengerToken`/`clearPassengerToken` on the existing token data source; `DispatchFcmService.syncPassengerTokenRegistration` with per-role last-registration tracking (token refresh re-uses the correct role-gated path); `HomeShellView` post-frame sync for `role=='passenger'`; cleared on sign-out.
- **Tests:** `delivery_ride_state.test.ts` — 17 cases covering allowlist rejection, passenger-only/driver-only/both recipients, offer-doc fallback, no-token, duplicate idempotency, non-recipient exclusion, invalid-token cleanup, retry-then-partial-success, dead-letter, lease fencing, PENDING-first ordering, endpoint auth. Backend suite **457/457**; `tsc --noEmit` clean; `flutter analyze lib/` clean; 1 new client parse test for the `RIDE_UPDATE` contract.
- **Explicitly NOT verified:** no live FCM push — projector untested against a real backend/device (staging remains down, billing `false`). HTTP/DB ride state stays authoritative; push is refresh hint only.

**Addendum (2026-10-19, seventh session) — Driver payout/commission model audited + planned (decision-gated):**

- **Money flow traced:** `feePolicySnapshot` stub (`platformFeeType:'NONE'`) already stamped atomically at offer-select alongside `agreedFareMinor`/`agreedFareCurrency` — the snapshot plumbing exists; only the policy source + derived fields are missing.
- **Plan (not implemented):** `docs/design/DRIVER_PAYOUT_MODEL_PLAN.md` — derive `driverPayoutMinor`/`platformFeeMinor`/`payoutCurrency` inside the existing `selectOffer` tx from a new admin-only `feePolicies/{city}_{category}` store; completion stays a pure state transition; missing policy → honest `resolution:'UNAVAILABLE'` (selection never blocks on config); no backfill of historical rides.
- **Owner decisions enumerated (none invented):** fee model shape, policy scope, rounding rule, fee bearer, missing-policy behavior, settlement semantics, historical handling — implementation blocked pending approval; no payment-provider/wallet scope.

**Addendum (2026-10-19, eighth session) — Driver payout model implemented (launch policy, unit-tested):**

- **Approved launch rule shipped:** `src/pricing/fee_policy.ts` — fee NONE ⇒ `platformFeeMinor=0`, `driverPayoutMinor=agreedFareMinor` (valid fare+currency only); `PERCENT_BPS`/`FLAT_MINOR` shapes supported by the resolver but no non-zero policy activated. `selectOffer` reads `feePolicies/{city}_{category}`→`_global` inside the tx and writes the payout snapshot atomically with assignment; replay returns recorded values; completion never recomputes. No backfill — pre-model rides keep fields absent.
- **Surfaces:** `publicRide` adds `driverPayoutMinor`/`platformFeeMinor`/`payoutCurrency`/`feePolicyResolution`; client `Ride` entity + parser + earnings aggregator (`payoutRideCount`/`payoutMinor`/`fareOnlyMinor` per period) — hero shows "Driver payout" only for payout-backed rides, "Trip fares" otherwise.
- **Tests:** `fee_policy.test.ts` 11 cases (launch NONE, floor rounding, clamp, currency mismatch, invalid data, malformed policy, atomic select, select/completion replay) + 3 aggregator cases; backend 468/468, driver suite 131 pass, both analyzers clean.

**Addendum (2026-10-19, ninth session) — payout exposure hardened + Intercity service-type entry shipped:**

- **Payout API exposure (security fix):** `publicRide(ride, viewer)` now takes a server-derived viewer (`'driver'` iff `caller.uid == assignedDriverId`, or `queryRole` on list); `driverPayoutMinor`/`platformFeeMinor`/`payoutCurrency`/`feePolicyResolution` emit only for the driver. Passenger-facing select/select-replay bodies no longer carry payout internals; `agreedFareMinor` unchanged. Test 8b covers passenger GET/list absence + driver presence. Suite **469/469**.
- **Intercity service type (INTERCITY-ENTRY):** the audit's "Home Intercity → placeholder" gap closed without backend work — `estimate_service.ts` already validates `ride|courier|intercity|move` and `createRide`/`listRides`/serializers already persist+filter `serviceType`. Client: `RideRequestUiState.serviceType` → estimate + create bodies; `?service=intercity` deep-link param; `selectServiceType` invalidates pricing (stale-guard tracks `_estimateServiceType` — response doesn't echo it); `_ServiceTypeSelector` chips in compose + review; home Intercity promo/tile now enter compose instead of "Coming later". Courier/Move intentionally still unavailable.
- **Tests:** 5 new VM cases + 2 widget cases; `ride_request_view_model_test` 42/42, `ride_request_ui_test` 14/14, `analyze lib/` clean. Test-harness note: autoDispose `c.read(provider)` recreates a fresh instance after awaits — tests that assert across awaits must hold `c.listen` (existing pattern, line ~430).
- **E2E verification pass (same session):** traced Home → compose → estimate → review → create → history/driver surfaces. Gaps fixed: `createRide` now enum-validates `serviceType` and rejects `PRICING_SNAPSHOT_MISMATCH` (422) when the body's serviceType/category disagree with `snapshot.inputs` (skipped when absent — backward compatible); both active-ride trip cards now label the service (`Intercity · Category easy`). Client stale-estimate proof: submit blocked synchronously on service switch until refetch lands or fails. Backend **471/471**, VM tests **44/44**.

**Addendum (2026-10-19, tenth session) — pickup location naming + confidence UX (LOCN-NAME-UX):**

- **Problem:** GPS pickups rendered "Location selected" because Places reverse-geocoding is the only name source and the project's paid Maps calls are billing-blocked (§0 staging outage, current-state #14).
- **Implementation:** `DeviceGeocoderPort` + `GeocodingDeviceGeocoder` (native Android `Geocoder` via `geocoding ^5.0.0` — no API key, no GCP billing); `FallbackPlaceSearch` decorates Places at DI — Places result wins when usable, device label (composed from real placemark fields only, never invented) on throw/unlabeled, primary error rethrown on total failure. `ResolvedPassengerLocation.horizontalAccuracyMeters` threads `Position.accuracy` → proposal card "GPS fix accuracy ±N m" (only when reported, distinct from address confidence). Resolved names attach to original coords — the pin never moves; retry reuses the same fix.
- **On-device proof:** `integration_test/device_geocoder_smoke_test.dart` on SM-A325F (Android 13) — real implementation returned "Plot n, Sher Ali Road, Aitchison Society" for Lahore coords; no backend/staging/billing involved.
- **Tests:** 10 new (`devicePlacemarkLabel`, decorator fallback order/total-failure, VM accuracy propagation/coord-preservation/retry) + 1 widget; focused suite **69/69**, `analyze lib/` clean. Staging remains billing-blocked; Places key still 403 until owner re-links billing.

**Addendum (2026-10-19, thirteenth session) — driver open-rides browse filters (OPEN-RIDES-FILTERS):**

- **Gap:** drivers scrolled one chronological open-rides list with no service-type/category narrowing, despite `serviceType`+`category` already being on `OpenRide`.
- **Implementation:** `/v1/rides/open` query extended (`serviceType` enum, `category` string ≤64); exact-match filter before sort/cursor/page; **discovery cursor binding now includes the filter set** — cross-filter cursor replay → 400. Mobile plumbs params end-to-end; VM filter state refetches page 1 on change; view mirrors ride-history chip rows + filtered-empty state with Clear filters.
- **Tests:** backend open-discovery 24/24 (+7), backend suite 478/478, `slice_m_driver_test` 37/37 (+6), driver suite 137, `analyze lib/` clean.
- **Evidence boundary:** local automated only — memoryDb HTTP tests cover the server path; no Firestore/staging (billing), no device (adb offline).
- **Limitation:** the pre-existing 200-doc scan cap still bounds discovery; filtered matches beyond the cap are unreachable either way.

**Addendum (2026-10-19, twelfth session) — compose draft persistence (COMPOSE-DRAFT):**

- **Gap:** process death / navigating away mid-compose discarded all passenger work (pickup, destination, category, serviceType, offer draft). No roadmap item covered it; pure-client slice, zero billing/staging dependency.
- **Implementation:** `RideComposeDraft` (JSON + corruption-tolerant decode + 24h TTL) → `RideComposeDraftStore` port → `SecureRideComposeDraftStore` (uid-scoped `SecureStorage`, mirrors saved-places pattern). VM: build-time async restore into pristine-only compose; 600 ms debounced persist on every mutator; clear on emptied compose, stale draft, and successful create. Draft stores locations/text/category/serviceType/offer — **never** pricing snapshots; restored confirmed endpoints downgrade to proposals (fresh estimate still required, confirm semantics preserved).
- **Self-audit fixes:** (1) restore built next-state off a pre-invalidation snapshot → rebuilt on post-`_invalidatePricing` state; (2) uid was cached → now read fresh at write time so an account switch can't persist under the wrong key.
- **Tests:** `ride_compose_draft_test.dart` 9/9; focused regression set 76/76; `analyze lib/` clean.
- **Evidence boundary:** local automated only — no staging (billing still disabled), no physical process-death run claimed.

**Addendum (2026-10-19, eleventh session) — set-point-on-map pin adjust (MAP-PIN-ADJUST):**

- **Gap:** the previous slice's closeout recorded "no pin-drag/adjust path on the compose map — search-only" as the remaining honest-UX gap for pickup confidence.
- **Implementation:** explicit set-point mode — `pinAdjustTarget` state (pickup/destination) armed from an "Adjust on map" action on each proposal card → map auto-expands → `MapLibreMap.onMapClick` supplies tapped `LatLng` → `setPinFromMapTap` proposes it with `source: mapPin` and resolves a name via the existing Places→native-geocoder fallback. Naming failure → honest unresolved + name-only retry (destination parity added via `destinationNameUnresolved`/`retryDestinationNameLookup`). Target cleared on all competing paths + on map collapse; out-of-range taps rejected; coordinates never rewritten by naming.
- **Tests:** 7 VM + 1 widget (target arm/cancel, inert tap without target, coord+source preservation both endpoints, unresolved+retry both endpoints, invalid-coord rejection, stale-target clear). `ride_request_view_model_test` 51/51, `ride_request_ui_test` 16/16, `analyze lib/` clean.
- **Device:** `integration_test/map_pin_adjust_smoke_test.dart` (fake GPS only; real view + real naming fallback + real map tap) — attempted twice on SM-A325F; first run stalled awaiting first frame, second failed at install as the device's adb link dropped (`adb: device 'RF8R40ZQ1JH' not found`). Harness retained for the next stable session — physical map-tap proof PENDING, not claimed.

The §5/§6 ranking below predates these closures; the next-slice recommendation is revisited in the 2026-10-14 task report rather than here.

---

## 1. Executive verdict

Ora today is a **staging-capable, inDrive-style marketplace core** with a real Flutter passenger+driver app and Cloud Run backend:

- **Marketplace lifecycle** (create → offers → assign → EN_ROUTE → ARRIVED → STARTED → COMPLETED → CLOSED) has **remote staging two-actor GREEN** evidence (`REMOTE_STAGING_TWO_ACTOR_E2E_REPORT_2026-09-29.md`).
- **Pricing estimate + snapshot create (5A/4B/5B/5C)** is implemented; **5C physical GREEN** exists (`p5c_device_proof_report.json`). Passenger offer on create is still **auto-filled from recommended fare** — **no passenger fare-edit UI** despite product contract and Phase 4–5 acceptance item #8.
- **Maps/location:** MAP-1…MAP-2C + L1/L2 RTDB live location are **CLOSED / VERIFIED** with physical reports. **MAP-3** is **implemented + automated PASS**; **physical follow-up YELLOW** on SM-A325F (`MAP3_PHYSICAL_FOLLOWUP_REPORT.json`) — core gesture/Recenter/OD1/tick-stability **PASS**; soft gap only MAP-1 smoke Places miss. **Phase 5D passenger fare offer** is **CLOSED** (`PASSENGER_FARE_OFFER_*`). **Ride Request half-screen map** physical gate is **PASS** (`RIDE_REQUEST_MAP_HALFSCREEN_REPORT.json`) — freeze; do not reopen absent regression. **MapLibre PoC** is disposable, **performance INCONCLUSIVE**, **brandless production gate BLOCKED** on MapTiler ToS.
- **Dispatch/FCM (D1), N3/N4, schedulers, Secret Manager, production Cloud Run foundation, App Check wiring** have slice reports; **release identity / Play signing remains BLOCKED** (no owner keystore) and is **explicitly deferred** as a development priority.
- **Payments / safety / Intercity / Courier / Move** are stubs or “coming later” — not next-core.

**Bottom line:** The passenger→driver journey works on staging with fixed recommended fares. The largest **product-model gap still unfinished** is **passenger-set fare within server bounds** (documented as a separate slice after location foundation). That should be the next implementation slice after approval.

---

## 2. Feature status matrix

Status vocabulary per audit brief. Evidence paths are under repo root unless noted.

| Feature | Status | Evidence | Outstanding gap |
| ------- | ------ | -------- | --------------- |
| **Passenger auth / onboarding** | CLOSED / VERIFIED | Auth routes `backend/auth-service/src/routes/auth.ts`; Flutter auth feature; AUTH-001 / remote E2E auth PASS | Staging App Check off (`REQUIRE_APP_CHECK=false`) — ops/hardening, not product blocker |
| **Home + ride compose** | CLOSED / VERIFIED | `passenger_home_view.dart`, `ride_request_view.dart`; half-screen + remote E2E | Intercity/Courier/Move → `onUnavailable` placeholders |
| **Pickup GPS + Places destination** | CLOSED / VERIFIED | Phase 4A; `RC_PHYS_002_REVERSE_GEOCODE_PHYSICAL_VERIFICATION_REPORT.json` GREEN; MAP-1 physical | — |
| **Fare estimate + snapshot (5A/5B/5C)** | CLOSED / VERIFIED (estimate/create) | `pricing/` backend; Flutter estimate client; `p5c_device_proof_report.json` GREEN; remote E2E pricing PASS | Live demand/surge Redis still soft (docs); not blocking create |
| **Passenger fare proposal UI** | **CLOSED / VERIFIED** (2026-10-14; was PARTIAL at audit) | Editable offer shipped + physically proven: custom Rs 860 vs recommended Rs 850, durable create, driver-visible — `passenger_fare_offer_physical_followup_report.json`; see §0 addendum | — |
| **Ride create / errors** | CLOSED / VERIFIED | `ride_service.ts` create + snapshot validation; remote E2E create PASS; Flutter request UI | — |
| **Offers inbox + select** | CLOSED / VERIFIED | `offers_inbox_view.dart`; remote E2E offer select PASS | — |
| **Driver open discovery + offer (accept/counter)** | CLOSED / VERIFIED (MVP) | `GET /v1/rides/open`; `driver_open_rides_view.dart` Accept / Counteroffer; backend `DRIVER_COUNTEROFFER`; remote E2E offer PASS | Counter UX exists; passenger cannot set initial offer ≠ recommended |
| **Assignment + progression** | CLOSED / VERIFIED | Backend SM + Flutter active/driver assigned views; remote E2E through RIDE_CLOSED | — |
| **D1 FCM dispatch delivery** | CLOSED / VERIFIED (staging physical) | `D1_REAL_FCM_PHYSICAL_PROOF_REPORT.md` FINAL PASS; delivery module; **2026-10-14 ordering fix** — PENDING-first scan + leftover-budget CLAIMED reclaim (`dispatch_fcm_projector.ts`, tests S1–S8, `FCM_ORDERING_FIX_PHYSICAL_VERIFY_REPORT.json`) | Continuous prod ops separate from feature |
| **Driver location publish (L1)** | CLOSED / VERIFIED | `L1_PHYSICAL_VERIFICATION_REPORT.json` | — |
| **RTDB tripLocations + ACL (L2 / MAP-2A)** | CLOSED / VERIFIED | `backend/auth-service/src/rtdb/*`; `L2_STEP4_PHYSICAL_VERIFICATION_REPORT.json`; MAP-2A reports | Older CURRENT_STATE “N2B NOT IMPLEMENTED” is **obsolete** |
| **MAP-1 request map** | CLOSED / VERIFIED | `MAP1_PHYSICAL_VERIFICATION_REPORT.json` GREEN | Uncommitted half-screen layer on top — freeze after commit hygiene |
| **MAP-2B / MAP-2C** | CLOSED / VERIFIED | MAP2B/MAP2C physical GREEN reports | — |
| **MAP-3 gesture ownership** | **CLOSED / VERIFIED** (2026-10-14; was YELLOW) | `active_ride_map.dart`; `MAP3_IMPLEMENTATION_STATUS.json`; `MAP3_PHYSICAL_FOLLOWUP_REPORT.json` core PASS + **`MAP3_I_MAP1SMOKE_CLOSEOUT_REPORT.json` GREEN** — `I_map1Smoke` miss was a harness flake (a11y viewport clip / input-escape / stale predicate), not an app defect | Optional human-finger latch polish |
| **Ride Request half-screen map** | CLOSED / VERIFIED | `RIDE_REQUEST_MAP_HALFSCREEN_REPORT.json` PHYSICAL PASS; layout util + PopScope | Working tree still uncommitted — process, not reopen |
| **MapLibre PoC** | PARTIAL / BLOCKED (production) | `MAPLIBRE_POC_PHYSICAL_REPORT.json` — PoC COMPLETE, perf INCONCLUSIVE; brandless gate FAIL/BLOCKED on MapTiler | Keep Google production; no migration |
| **History** | CLOSED / VERIFIED (code + remote close) | `ride_history_view.dart`; remote E2E CLOSED; backend list | Dual physical history UX sparsely evidenced |
| **Ratings** | **CLOSED / VERIFIED (segmented)** (2026-10-14) | Backend 2N + `ride_rating_view.dart`; Vitest covered; **`TWO_ACTOR_LIFECYCLE_RATINGS_CLOSEOUT.json`** — both rating docs persisted on staging ride `5e1a8232-…` (passenger→driver 5★, driver→passenger 4★) | Proof segmented across 3 runs of one ride (emulator uiautomator fragility), not one uninterrupted run |
| **NO_SHOW / wait / expire sweeps** | CLOSED / VERIFIED (backend + schedulers) | Phase 2J–2M; `ORA_CLOUD_SCHEDULER_SLICE2_REPORT.md` | Passenger-facing wait-clock UX: **implemented + automated-tested (2026-10-19)**; physical proof BLOCKED — staging down (GCP billing disabled) |
| **Payments / wallet** | NOT STARTED | `mobile/lib/features/payments/payments.dart` library stub; Phase 11 docs | Intentionally later |
| **Safety** | NOT STARTED | `mobile/lib/features/safety/safety.dart` stub | Intentionally later |
| **Release signing / Play** | BLOCKED (deferred) | `ORA_RELEASE_IDENTITY_SLICE6_REPORT.md` BLOCKED — no keystore | Owner provisioning; not next feature |
| **Production Cloud Run foundation** | IMPLEMENTED (ops) | `ORA_PRODUCTION_CLOUD_RUN_SLICE3_REPORT.md` | Full prod mobile release still blocked on signing/App Check identity |
| **Docs CURRENT_STATE frontier** | **RECONCILED 2026-10-14** | `docs/ORA_CURRENT_STATE.md` updated: RTDB/N2B, outbox projector, 5C/5D, ratings proof | — |

---

## 3. Known failures and blockers

### Confirmed

| Item | Kind | Evidence |
| ---- | ---- | -------- |
| ~~Passenger cannot edit offered fare~~ → **RESOLVED 2026-10-14** | Was product gap | Now physically PASS — `passenger_fare_offer_physical_followup_report.json` (see §0) |
| ~~MAP-3 physical OD1 / Recenter~~ → **RESOLVED 2026-10-14** | Was soft residual | `I_map1Smoke` closed GREEN — harness flake fix (`MAP3_I_MAP1SMOKE_CLOSEOUT_REPORT.json`; see §0) |
| MapLibre brandless + GL FPS | BLOCKED / INCONCLUSIVE | `MAPLIBRE_POC_PHYSICAL_REPORT.json` |
| Production release signing | BLOCKED | Slice 6 — no `key.properties` / keystore |
| Home Intercity / Courier / Move | NOT STARTED (placeholders) | `passenger_home_view.dart` `onUnavailable` |
| Payments / safety features | NOT STARTED | Stub libraries only |

### Uncertain / UNKNOWN

| Item | Why UNKNOWN |
| ---- | ----------- |
| Current `ora-auth-service-staging` revision health vs Sept reports | Live GCP not re-probed this audit |
| Flutter full suite greenness today | Historical “1 FAIL mvvm_layer_test” not re-run |
| ~~NO_SHOW wait-clock UX on device~~ → **IMPLEMENTED + automated-tested 2026-10-19** | Wait-clock exists (server `arrivedAt` → 1 Hz "Waiting" label; NO_SHOW terminal copy). Physical attempt BLOCKED by staging billing outage — see §0 addendum |
| ~~Ratings E2E on two physical actors~~ → **RESOLVED 2026-10-14** | `TWO_ACTOR_LIFECYCLE_RATINGS_CLOSEOUT.json` — both ratings persisted (segmented runs; see §0) |
| ~~Profile-mode frame timing~~ → **CAPTURED 2026-10-19** | `PROFILE_FRAME_TIMING_MAP_REPORT.json` — 856 samples, SM-A325F profile build; prior zero caused by `ORA_FRAME_TIMING=1` vs `bool.fromEnvironment` |
| Whether uncommitted half-screen matches the PASS report APK | Report claims PASS; git still dirty — assume report APK had the slice |

### Not treated as regressions

- Ride-card current-location label — user-confirmed fixed; do not reopen.
- Half-screen map — physical PASS; do not reopen without regression evidence.

---

## 4. Completed work that must stay frozen

Do not reopen for style or speculative refactors:

- Ride/offer state machine, durable offers, select/assign, progression, close, expire, offer-expire, NO_SHOW, ratings **API**
- M0 open discovery; N1/N2A/N2C/N3/N4 matching semantics; D1 FCM delivery path
- Pricing snapshot authority (no client-fabricated `pricingSnapshotId`)
- MAP-1 / MAP-2A / MAP-2B / MAP-2C physical-closed behaviors; L1 publish / L2 RTDB ACL+cleanup
- Ride Request half-screen expand/collapse (just closed)
- Compact ride cards + reverse-geocode physical (RC-PHYS-001/002)
- Remote staging two-actor lifecycle GREEN (2026-09-29)
- Production hardening slices 1–4 as ops baselines (do not casually undo Secret Manager / scheduler / App Check wiring)

---

## 5. Top next-slice candidates (ranked)

| Rank | Candidate | Why | Dependencies | Why not #1 |
| ---- | --------- | --- | ------------ | ---------- |
| ~~1~~ | ~~Passenger fare proposal / edit within bounds (“5D”)~~ | **CLOSED 2026-10-14** — physical PASS (`passenger_fare_offer_physical_followup_report.json`) | — | — |
| ~~2~~ | ~~MAP-3 physical gesture/Recenter close~~ | **CLOSED 2026-10-14** — `I_map1Smoke` GREEN (`MAP3_I_MAP1SMOKE_CLOSEOUT_REPORT.json`) | — | — |
| ~~3~~ | ~~Two-actor ratings physical proof~~ | **CLOSED 2026-10-14** — GREEN_SEGMENTED (`TWO_ACTOR_LIFECYCLE_RATINGS_CLOSEOUT.json`) | — | — |
| 4 | Commit/hygiene for half-screen + PoC | Process | None | Not a product capability |
| ~~4b~~ | ~~Profile-mode frame timing~~ — **CLOSED 2026-10-19** | `PROFILE_FRAME_TIMING_MAP_REPORT.json` — 856 samples; raster p95 18.84ms | `flutter build apk --profile --dart-define=ORA_FRAME_TIMING=true` + map gestures | — |
| 5 | MapLibre production evaluation | Long-term maps cost/brand | Licensing / Sales letter / perf metrics | Explicitly BLOCKED; Google remains production |
| 6 | Payments / Intercity | Expansion | Product freeze | Not core journey blockers |
| 7 | Release signing | Store ship | Owner keystore | **Deferred by instruction** |

---

## 6. Recommended next slice (exactly one)

> **Superseded 2026-10-14:** this recommendation was executed and physically verified PASS (`passenger_fare_offer_physical_followup_report.json`; see §0). The section is retained for history; the current next-slice recommendation is in the 2026-10-14 closeout report.

### Name

**Passenger fare proposal (edit offer within server bounds) — Phase 5D**

### User problem and desired outcome

Passengers see a recommended fare and an offer range but **cannot set their own offer**. Drivers can accept or counter, yet the passenger side of negotiation is incomplete versus Ora’s P2P fare model.

**Outcome:** On Ride Request review, passenger can edit **Your offer** within snapshot `offerBoundMinMinor`–`offerBoundMaxMinor`, see validation, and create the ride with that `passengerOfferMinor`. Out-of-bounds offers never reach durable SUCCESS without server rejection.

### Current root cause / missing behavior (evidence)

- `RideRequestViewModel` sets `passengerOfferMinor` from `estimate.recommendedFareMinor` only (`ride_request_view_model.dart`).
- Review UI renders estimate + “Offer range …” with **no editor** (`ride_request_view.dart`).
- Product contract shows Edit fare UI and states: *“Implement as a separate passenger fare-editing slice after location foundation is closed”* (`docs/product/passenger-flow.md`).
- Phase 4–5 real-device criteria item **8**: “Passenger sets offer within bounds” (`phase-4-5-location-pricing-decision.md` §22).
- Backend already validates offer vs snapshot bounds on create (`ride_service` + OfferBoundPolicy) — gap is **client UX + wiring**, not fare engine redesign.

### Likely in-scope files/components

- `mobile/lib/features/ride/presentation/views/ride_request_view.dart` (review fare card / editor)
- `mobile/lib/features/ride/presentation/view_models/ride_request_view_model.dart` (`setPassengerOfferMinor` / clamp / clear)
- Possibly small shared formatters under `presentation/offers/` or theme inputs
- Focused tests: `mobile/test/features/ride/ride_request_ui_test.dart` (+ new unit tests for offer clamp)

### Explicit out of scope

- MAP-1/2/3, half-screen map, MapLibre, ActiveRideMap
- Backend fare formula, Routes, snapshot schema, OfferBoundPolicy redesign
- Driver counteroffer redesign, dispatch/N3/N4/D1
- Payments, surge/demand Redis live multipliers, Intercity
- Release signing / Play

### API / data / architecture impact

- **None required** if create already sends `passengerOfferMinor` + `pricingSnapshotId` (verify in VM submit path — already present).
- Server remains authoritative for bounds.

### Acceptance criteria

1. Review shows recommended fare, bounds, and editable **Your offer** (default = recommended).
2. Passenger can change offer within min–max; UI blocks or clearly errors outside bounds before submit.
3. Create ride persists passenger-chosen `passengerOfferMinor` (Firestore / API proof).
4. Server still rejects out-of-bounds / expired snapshot (existing behavior; regression test).
5. No fabricate snapshot IDs; no map/dispatch changes.
6. Focused Flutter tests PASS; analyze clean on touched files.
7. Physical or staging proof: set non-recommended in-bound offer → SEARCHING with that amount visible to driver open-ride card.

### Tests

- Unit: clamp / clear / default-from-estimate
- Widget: edit field, out-of-bounds CTA disabled or error, create payload amount
- Regression: existing `ride_request_ui_test` pricing/create paths

### Staging / physical proof

- Staging APK on SM-A325F (or remote staging): estimate → edit offer ≠ recommended but in range → create → driver open list shows passenger offer amount.
- Optional: out-of-bounds attempt → no successful create.

### Risks / containment / closure

- **Risk:** Confusing “estimated” vs “your offer” copy — use Ora typography patterns; keep estimate as guidance.
- **Rollback:** Feature is UI+VM; revert Flutter files; backend unchanged.
- **Closure:** AC above + report artifact under `mobile/.e2e_artifacts/` (e.g. `PASSENGER_FARE_OFFER_SLICE_REPORT.json`); do not claim GREEN without amount proof on create.

---

## 7. Deferred work

| Item | Reason |
| ---- | ------ |
| Production release keystore / Play upload / store testing | Owner-provisioned; Slice 6 BLOCKED; **not** next engineering slice per instruction |
| MapLibre production migration | Licensing/brand + FPS inconclusive; Google remains production |
| Payments / wallet / JazzCash etc. | Phase 11; stubs only |
| Safety / SOS | Phase 12; stub |
| Intercity / Courier / Move | Explicit “coming later” home placeholders |
| Demand multiplier / surge live Redis | Softened in pricing docs; not required for fare-edit slice |
| MAP-3 physical GREEN close | Valuable verification follow-up **after** or parallel to fare slice — not higher than marketplace fare gap |
| Doc-only CURRENT_STATE refresh | Recommended hygiene; not a product feature |

---

## 8. Confidence and evidence gaps

| Area | Confidence | Gap |
| ---- | ---------- | --- |
| Backend marketplace core | High | Relies on Sept remote E2E + Vitest artifacts; not re-executed this session |
| Maps MAP-1–2C + half-screen | High | Physical reports on disk; half-screen uncommitted in git |
| MAP-3 | High (2026-10-14) | Physical GREEN via `MAP3_I_MAP1SMOKE_CLOSEOUT_REPORT.json` |
| Passenger fare edit gap | Closed (2026-10-14) | Physical PASS — `passenger_fare_offer_physical_followup_report.json` |
| Live staging revision / scheduler health today | Medium (2026-10-14) | Staging API live-probed + exercised end-to-end in two-actor run |
| Ratings two-actor physical | High (2026-10-14) | GREEN_SEGMENTED — `TWO_ACTOR_LIFECYCLE_RATINGS_CLOSEOUT.json` |
| NO_SHOW wait-clock UX physical | Medium (2026-10-19) | Feature implemented + automated-tested; physical run attempted but blocked — staging 503/500 (GCP billing disabled) |
| Full Flutter CI health | Medium | Historical FAIL note not revalidated |

---

## Audit constraints honored

- Read-only; no code/config/infra/dependency changes  
- No secrets printed  
- Working tree left intact  
- Half-screen map and ride-card current-location **not** reopened  
- Release signing **not** prioritized  
- **One** recommended next slice: **Passenger fare proposal within bounds (5D)**  

**Awaiting approval before any implementation.**
