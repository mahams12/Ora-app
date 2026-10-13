# Ora — Master Roadmap Audit

**Type:** Read-only audit (no code, config, infra, or dependency changes)  
**Generated:** 2026-10-12T09:50:00Z  
**Git tip inspected:** `master` @ `66a07f0` (`partial working on maps`)  
**Working tree:** Dirty — uncommitted half-screen map UX + MapLibre PoC + related tests/artifacts (not discarded; not treated as merged until committed)  
**Authority rule:** Code + executable proofs in-repo outrank stale narrative docs. `docs/ORA_CURRENT_STATE.md` (2026-09-21) is **stale** relative to MAP/L1–L2/half-screen/staging E2E evidence and must not be used as the live frontier without reconciliation.

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
| **Passenger fare proposal UI** | **PARTIAL** | VM auto-sets `passengerOfferMinor` from `recommendedFareMinor` (`ride_request_view_model.dart`); review shows estimate + bounds only (`ride_request_view.dart` ~850–888); **no Edit fare control**. Product mock in `docs/product/passenger-flow.md` § fare edit; Phase 4–5 criteria item **8** “Passenger sets offer within bounds” | **Missing editable offer within `offerBoundMin/Max`** |
| **Ride create / errors** | CLOSED / VERIFIED | `ride_service.ts` create + snapshot validation; remote E2E create PASS; Flutter request UI | — |
| **Offers inbox + select** | CLOSED / VERIFIED | `offers_inbox_view.dart`; remote E2E offer select PASS | — |
| **Driver open discovery + offer (accept/counter)** | CLOSED / VERIFIED (MVP) | `GET /v1/rides/open`; `driver_open_rides_view.dart` Accept / Counteroffer; backend `DRIVER_COUNTEROFFER`; remote E2E offer PASS | Counter UX exists; passenger cannot set initial offer ≠ recommended |
| **Assignment + progression** | CLOSED / VERIFIED | Backend SM + Flutter active/driver assigned views; remote E2E through RIDE_CLOSED | — |
| **D1 FCM dispatch delivery** | CLOSED / VERIFIED (staging physical) | `D1_REAL_FCM_PHYSICAL_PROOF_REPORT.md` FINAL PASS; delivery module | Continuous prod ops separate from feature |
| **Driver location publish (L1)** | CLOSED / VERIFIED | `L1_PHYSICAL_VERIFICATION_REPORT.json` | — |
| **RTDB tripLocations + ACL (L2 / MAP-2A)** | CLOSED / VERIFIED | `backend/auth-service/src/rtdb/*`; `L2_STEP4_PHYSICAL_VERIFICATION_REPORT.json`; MAP-2A reports | Older CURRENT_STATE “N2B NOT IMPLEMENTED” is **obsolete** |
| **MAP-1 request map** | CLOSED / VERIFIED | `MAP1_PHYSICAL_VERIFICATION_REPORT.json` GREEN | Uncommitted half-screen layer on top — freeze after commit hygiene |
| **MAP-2B / MAP-2C** | CLOSED / VERIFIED | MAP2B/MAP2C physical GREEN reports | — |
| **MAP-3 gesture ownership** | IMPLEMENTED / PHYSICAL FOLLOW-UP YELLOW (core PASS) | `active_ride_map.dart`; `MAP3_IMPLEMENTATION_STATUS.json`; focused suite 45 PASS; **`MAP3_PHYSICAL_FOLLOWUP_REPORT.json` YELLOW** (ride `2ee3fa76-…`, SM-A325F) — Recenter/OD1/G ticks PASS; soft `I_map1Smoke` only | Optional human-finger latch polish; MAP-1 smoke Places harness flake |
| **Ride Request half-screen map** | CLOSED / VERIFIED | `RIDE_REQUEST_MAP_HALFSCREEN_REPORT.json` PHYSICAL PASS; layout util + PopScope | Working tree still uncommitted — process, not reopen |
| **MapLibre PoC** | PARTIAL / BLOCKED (production) | `MAPLIBRE_POC_PHYSICAL_REPORT.json` — PoC COMPLETE, perf INCONCLUSIVE; brandless gate FAIL/BLOCKED on MapTiler | Keep Google production; no migration |
| **History** | CLOSED / VERIFIED (code + remote close) | `ride_history_view.dart`; remote E2E CLOSED; backend list | Dual physical history UX sparsely evidenced |
| **Ratings** | IMPLEMENTED / PHYSICAL VERIFICATION PENDING | Backend 2N + `ride_rating_view.dart`; Vitest covered; **no `*rating*` physical report found** | Two-actor ratings on device not proven in artifacts |
| **NO_SHOW / wait / expire sweeps** | CLOSED / VERIFIED (backend + schedulers) | Phase 2J–2M; `ORA_CLOUD_SCHEDULER_SLICE2_REPORT.md` | Passenger-facing wait-clock UX physical: UNKNOWN |
| **Payments / wallet** | NOT STARTED | `mobile/lib/features/payments/payments.dart` library stub; Phase 11 docs | Intentionally later |
| **Safety** | NOT STARTED | `mobile/lib/features/safety/safety.dart` stub | Intentionally later |
| **Release signing / Play** | BLOCKED (deferred) | `ORA_RELEASE_IDENTITY_SLICE6_REPORT.md` BLOCKED — no keystore | Owner provisioning; not next feature |
| **Production Cloud Run foundation** | IMPLEMENTED (ops) | `ORA_PRODUCTION_CLOUD_RUN_SLICE3_REPORT.md` | Full prod mobile release still blocked on signing/App Check identity |
| **Docs CURRENT_STATE frontier** | PARTIAL (doc debt) | `docs/ORA_CURRENT_STATE.md` still says 5C pending / N2B not implemented | Reconcile doc — not an app slice |

---

## 3. Known failures and blockers

### Confirmed

| Item | Kind | Evidence |
| ---- | ---- | -------- |
| Passenger cannot edit offered fare (always recommended) | Product gap / PARTIAL | No fare editor in `ride_request_view.dart`; auto-assign in VM; `passenger-flow.md` defers fare-edit slice; Phase 4–5 AC #8 unmet |
| MAP-3 physical OD1 / Recenter | Soft residual only | Follow-up `MAP3_PHYSICAL_FOLLOWUP_REPORT.json` core PASS; soft `I_map1Smoke` |
| MapLibre brandless + GL FPS | BLOCKED / INCONCLUSIVE | `MAPLIBRE_POC_PHYSICAL_REPORT.json` |
| Production release signing | BLOCKED | Slice 6 — no `key.properties` / keystore |
| Home Intercity / Courier / Move | NOT STARTED (placeholders) | `passenger_home_view.dart` `onUnavailable` |
| Payments / safety features | NOT STARTED | Stub libraries only |

### Uncertain / UNKNOWN

| Item | Why UNKNOWN |
| ---- | ----------- |
| Current `ora-auth-service-staging` revision health vs Sept reports | Live GCP not re-probed this audit |
| Flutter full suite greenness today | Historical “1 FAIL mvvm_layer_test” not re-run |
| NO_SHOW wait-clock UX on device | No dedicated physical report found |
| Ratings E2E on two physical actors | No ratings physical artifact |
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
| **1** | **Passenger fare proposal / edit within bounds (“5D”)** | Core inDrive differentiator missing; AC #8 explicit; location/maps foundation closed | Existing estimate bounds + create validation already server-side | — |
| 2 | MAP-3 physical gesture/Recenter close | Closes YELLOW verification | SM-A325F + assigned ride with live map | Implementation already done; not blocking marketplace fare negotiation |
| 3 | Two-actor ratings physical proof | Completes post-ride trust loop evidence | Two accounts / devices | Feature implemented; proof gap only |
| 4 | Commit/hygiene for half-screen + PoC | Process | None | Not a product capability |
| 5 | MapLibre production evaluation | Long-term maps cost/brand | Licensing / Sales letter / perf metrics | Explicitly BLOCKED; Google remains production |
| 6 | Payments / Intercity | Expansion | Product freeze | Not core journey blockers |
| 7 | Release signing | Store ship | Owner keystore | **Deferred by instruction** |

---

## 6. Recommended next slice (exactly one)

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
| MAP-3 | Medium | Code+tests strong; physical YELLOW |
| Passenger fare edit gap | High | Direct code + product/phase docs |
| Live staging revision / scheduler health today | Low–medium | Not live-probed |
| Ratings / NO_SHOW UX physical | Low | Missing dedicated physical reports |
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
