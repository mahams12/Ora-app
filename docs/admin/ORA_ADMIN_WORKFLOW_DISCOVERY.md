# ORA Admin Platform — Workflow & Feature Discovery

**Status:** DRAFT for review — reconciled 2026-11-24
**Evidence base:** source code in `backend/auth-service/src`, `firestore.rules`, `firestore.indexes.json`, `mobile/lib`, `docs/` (authoritative snapshot `docs/ORA_CURRENT_STATE.md`, engineering register `docs/engineering/ORA_ENGINEERING_DECISION_REGISTER.md`).
**Rule applied:** code + executable proofs outrank historical markdown. Where a schema doc describes a collection that no code writes, it is classified **PLANNED**, not Implemented.

Status vocabulary: **IMPLEMENTED** / **PARTIAL** / **PLANNED** / **MISSING** / **N/A**.

> **Reconciliation note (2026-11-24):** this document was re-verified against source during the admin planning reconciliation. Corrections vs the first draft: (1) ride progression endpoints were verified NOT to re-check `driverStatus` mid-ride (see §6); (2) the one-active-ride-per-passenger invariant is an **approved product decision (DR-008) whose backend enforcement is NOT yet implemented** — admin planning must not assume it exists; (3) manual driver approval is a **confirmed product requirement** — auto-approve must only be disabled after the admin review workflow ships; (4) KYC document *image* uploads are **deferred** — paid Firebase Storage is not approved; V1 is text-based KYC review only.

---

## 1. System shape (what the admin platform sits on top of)

| Concern | Reality | Evidence |
|---|---|---|
| Backend | Single Express 4 modular monolith `ora-auth-service` (TypeScript → `dist/`), Cloud Run, port 8080 | `backend/auth-service/src/app.ts`, `src/index.ts`, `scripts/deploy_*_cloud_run.sh` |
| AuthN | Firebase Auth ID token via `auth.verifyIdToken(token, true)` (revocation check ON). Caller = `{uid, phoneNumber, email, disabled}` — **no roles/claims are read from the token**; decoded token does carry `auth_time` (usable for step-up freshness) | `src/middleware/auth.ts:85-104` |
| App Check | Optional per env; production requires it (`REQUIRE_APP_CHECK=true`); verification is `getAppCheck().verifyToken()` — works for any attested client, **but no web/App Check provider is configured for an admin web app today**. **D-05 approved (Option A):** enforcement deferred for `/v1/admin` in V1; mobile/production enforcement unchanged; namespace scoping to verify before implementation | `src/index.ts:173-177`, `src/config/production_guards.ts` |
| Authorization today | None. No `requireAdmin`, no permission checks. Role gates that exist: `role==='driver'`+`driverStatus==='approved'` (device tokens, location, nearby, availability, offer create, invite accept, select-offer re-check); `role==='passenger'` (passenger device tokens) | `src/delivery/device_token_service.ts`, `src/location/location_update_service.ts:317`, `src/drivers/nearby_service.ts:783`, `src/rides/ride_service.ts:1734,1827,2454-2465` |
| Machine auth precedent | `/v1/internal/*` gated by shared static `X-Ora-Worker-Token` (`ORA_INTERNAL_WORKER_TOKEN`, min 16 chars) | `src/middleware/internal_worker.ts`, `src/routes/internal.ts` |
| Data SoT | Firestore (Admin SDK only for everything except `users` self-read and `savedPlaces`). RTDB for trip locations + optional geo/streams. Redis removed 2026-10-21 — geo is Firestore `geoDrivers` | `firestore.rules` (deny-all default), `src/redis/firestore_geo_client.ts` |
| Firestore rules | Fail-closed deny-all. Already reserves client-denied collections: `adminAuditLogs`, `moderationCases`, `reports`, `supportTickets(+Messages)`, `safetyEvents`, `blocks`, `disputes`, `consentRecords`, `notificationReceipts`, `tripShareTokens`, plus all payment/wallet collections | `firestore.rules:49-177` |
| Deployment | Cloud Run `ora-auth-service` (prod) / `ora-auth-service-staging`; min 0 / max 10, 512Mi/1CPU; Cloud Scheduler → Cloud Run Jobs → `/v1/internal/*` sweeps | `scripts/deploy_production_cloud_run.sh`, `scripts/wire_*_cloud_scheduler.sh` |

**Headline finding:** Ora has a rich server-authoritative domain model but **zero administrative surface**. Enforcement fields already exist and are checked at every *new-work* eligibility gate — the admin platform's job is to add authorized write paths, review workflows, audit, and configuration management.

**Admin identity (reconciled):** admin authority will live **only** in a new `adminOperators/{uid}` collection. `users/{uid}.role` remains the *application* role (`passenger`/`driver`) and must never be overwritten to grant admin access — an admin who is also a driver keeps `role='driver'`. The `'admin'` literal in `UserRole` (`src/types.ts:2`) stays unused/vestigial. Details in `ORA_ADMIN_BACKEND_ARCHITECTURE.md` §2 and `ORA_ADMIN_DATA_MODEL.md` §1.1.

---

## 2. User types & account model

| Item | Status | Evidence |
|---|---|---|
| Passenger accounts | IMPLEMENTED | `POST /v1/auth/register` creates `users/{uid}` with `role:'passenger'`, `driverStatus:'none'`, `isActive:true`, `banned:false` — `src/services/users.ts` (`registerUser`) |
| Driver accounts | IMPLEMENTED (capability model) | `role='driver'` granted on onboarding approval; `activeMode` passenger⇄driver switch — `src/types.ts:1-10`, `POST /v1/auth/mode` |
| Admin identity | PLANNED | `adminOperators/{uid}` collection (new); `users.role='admin'` literal exists but unused — **admin identity is independent of app role** |
| Vendor identity | PLANNED | Marketplace plan: vendor state lives in `vendors/*` docs, NOT `users.role` — `docs/implementation/marketplace/ORA_MARKETPLACE_AUDIT_AND_PLAN.md` §1.4/§2.2 |
| Account disable enforcement | IMPLEMENTED | `isActive===false \|\| banned===true` → `ACCOUNT_DISABLED` 403 on register/me/profile/mode/onboarding — `src/routes/auth.ts:95,150,201`, `src/services/users.ts`, `src/drivers/driver_onboarding_service.ts:185` |
| Ban/suspend writers | MISSING | Fields `banned`, `isActive`, `driverStatus:'suspended'` are only ever *read*; no mutation path exists |
| Profile fields | PARTIAL | Implemented: `displayName`, `avatarData` (base64 data-URL — public profile avatar, existing pattern). Schema-doc-only: `email`, `rating`, `totalTrips`, `bannedReason`, `referralCode`, `preferredLanguage`, `notificationsEnabled` |
| Driver-facing application status | PARTIAL | `GET /v1/auth/me` returns `driverStatus` (`none\|pending\|approved\|suspended`) — enough for "approved/pending" but NOT for review detail (info-requested reason, rejection feedback, resubmission state). A dedicated driver-facing status endpoint is required — see API spec §3.4 |

---

## 3. Driver domain

| Item | Status | Evidence |
|---|---|---|
| Driver onboarding submission | IMPLEMENTED | `POST /v1/drivers/onboarding` → `DriverOnboardingService.submit` — validates fullName, CNIC (`#####-#######-#`), homeCity, licenseNumber, licenseExpiry (≥ today UTC), vehicleCategory, vehicle make/model/year/color, plate — `src/drivers/driver_onboarding_service.ts`, route `src/drivers/routes.ts:37` |
| Auto-approval | IMPLEMENTED (default ON) | `DRIVER_AUTO_APPROVE` env, default `true` (`src/config/driver_auto_approve.ts`); writes `role='driver'`, `driverStatus='approved'`, `driverApprovalSource='auto'` — comment: *"Auto-approves until admin review exists"* (`routes.ts:35`) |
| **Manual approval requirement** | **CONFIRMED PRODUCT REQUIREMENT** | Phone verification must NOT auto-approve; admin review required before activation. Rollout rule: do **not** set `DRIVER_AUTO_APPROVE=false` in production until the admin review workflow is deployed **and tested** |
| Manual review queue | MISSING | `driverStatus='pending'` path exists in code but is unreachable by default; no reviewer API/UI |
| Rejection / info-request / resubmission | MISSING | `drivers.rejectionReason`, `approvedBy`, `suspensionReason`, `suspendedUntil` exist only in schema doc — zero code writers |
| Document upload & verification | **DEFERRED — D-04 Option A approved** | V1 = text-based KYC + manual review (no images, no bucket, no upload/preview endpoints, no paid Storage/Blaze, no Base64-in-Firestore). Option B (Firebase Storage) is a future conditional option requiring explicit billing approval. `driverDocuments`/`vehicles` collections are schema-doc + rules-deny only. Avatar (`users.avatarData` base64) is a separate, existing public-profile mechanism — not KYC |
| Vehicle categories | IMPLEMENTED (hardcoded) | `DRIVER_VEHICLE_CATEGORIES = ['zip','trio','easy','breeze','premium','executive']` — `driver_onboarding_service.ts:8-15`. UI maps to Bike/Rickshaw/Mini/AC/Premium/Business (`mobile/lib/features/super_app/domain/ride_type_catalogue.dart`) |
| Driver↔category matching | MISSING | `ride.category` is never checked against `vehicle.category`/`preferredCategories` in dispatch/offer code — category only validated against `pricingRules` at ride create |
| Availability | IMPLEMENTED | `POST /v1/drivers/go-online|go-offline`, `GET /v1/drivers/availability`; durable `drivers.availabilityState ∈ offline|online` (+ `busy`/`suspended` schema-only); geo projection upserted/removed — `src/drivers/driver_availability_service.ts` |
| Eligibility gates (suspension enforcement) | IMPLEMENTED for NEW work | Every *new-work* gate requires `driverStatus==='approved'`: nearby (`nearby_service.ts:783`), offer create (`ride_service.ts:1827-1828`), invite accept (`:1734-1735`), select-offer re-check (`:2454-2465`), eligibility (`rides/eligibility.ts:55-63`), location update (`location_update_service.ts:317`), availability (`driver_availability_service.ts:95`) |
| **Mid-ride progression vs suspension** | **VERIFIED — does NOT re-check `driverStatus`** | `progressAssignedRide` (`ride_service.ts:3104+`) authorizes via `ride.assignedDriverId === caller.uid` + state machine only (`:3276-3301`). A suspended driver with an in-flight ride CAN complete `en-route→arrived→start→complete`. This is the desired behavior — suspension blocks new work, never strands a live trip |
| Ride history per driver | IMPLEMENTED (data) | `rides.assignedDriverId` + `GET /v1/rides` (owner-scoped only; no cross-user admin query) |
| Ratings per driver | PARTIAL | `ratings` collection implemented (stars only, one per direction per ride); **no aggregate rating write-back** to `drivers.rating`/`users.rating` |
| Driver location history | MISSING (by design) | No persisted GPS history; only transient geo markers + RTDB `tripLocations` during active trips (deleted on terminal) — `src/rtdb/ride_location_lifecycle.ts` |

---

## 4. Vendor / marketplace domain

| Item | Status | Evidence |
|---|---|---|
| Vendor backend (registration, listings, orders) | MISSING — NOT STARTED | `docs/ORA_CURRENT_STATE.md:101`: "Vendor registration, admin, Storage, marketplace booking backend — NOT STARTED — needs approval (Storage requires Blaze)" |
| Frontend catalogue browse | IMPLEMENTED (frontend only) | `mobile/lib/features/marketplace/*`, `assets/marketplace/catalogue_v1.json` (Logistics 8/42, Services 11/88, Rental 8/37); quote CTAs disabled; honest empty states |
| Planned vendor model | PLANNED | Marketplace plan §2.2: `vendors/{uid}_{kind}`, `kind ∈ rental|service|logistics`, `status ∈ pending|under_review|info_requested|approved|rejected|suspended`, plus `vendorPrivate`, `vendorDocuments`, `rentalListings`, `serviceOfferings`, `marketplaceInquiries`, `marketplaceReviews`, `favorites` |
| Vendor role placement | PLANNED constraint | Marketplace plan §1.4 #3: vendor roles must NOT go in `users.role`; separate docs; `users/{uid}` untouched |
| Vendor document storage | BLOCKED | Marketplace plan requires Firebase Storage (Blaze). **Paid storage is NOT approved** — vendor KYC documents deferred with driver KYC images |

**Consequence:** vendor admin modules are specified in the API doc (deferred section) but are **Phase 3+**, gated on marketplace backend approval (D-02 — spec approved, build deferred) AND a zero/low-cost document strategy. The admin platform adopts the marketplace plan's `vendors` status machine — no parallel logic.

---

## 5. Registration & approval workflows

| Flow | Status | Detail |
|---|---|---|
| Passenger registration | IMPLEMENTED | Phone OTP (Firebase Auth, client) → `POST /v1/auth/register` (idempotent, `Idempotency-Key: register_{uid}`) → `users/{uid}` passenger → profile completion (`displayName` required for `profileComplete`) |
| Driver registration | PARTIAL | Same auth bootstrap → `POST /v1/drivers/onboarding` → **auto-approve** (default) or `pending` (if `DRIVER_AUTO_APPROVE=false`). **Target state (confirmed requirement): manual admin review before activation** |
| Driver review states | PLANNED (this design) | Review lifecycle on `drivers.driverStatus`: `pending → under_review → info_requested → approved | rejected`; resubmission increments `applicationVersion`. Capability flag `users.driverStatus` stays `none|pending|approved|suspended` — see Data Model §2.2 for the authoritative split |
| Vendor registration | PLANNED | See §4 |
| Account status transitions | PARTIAL | `none→pending→approved` implemented; `suspended` read-only; `isActive`/`banned` flags exist with no writers |
| Duplicate application prevention | PARTIAL | Onboarding re-submit while `approved` returns approved; `pending` re-submits overwrite; `suspended` → 403. No dedicated application entity — application state lives on `drivers/{uid}` + `users.driverStatus`. `applicationVersion` (proposed) guards stale reviews |
| Stale-review protection | PLANNED (required) | Review mutations must carry `expectedApplicationVersion`; transaction rejects mismatches with 409 — concurrent reviewers cannot silently overwrite |
| Audit of decisions | MISSING | `adminAuditLogs` collection reserved in rules; nothing writes it. `rideEvents` is ride-scoped only |
| Driver-facing status UX | MISSING (backend) | Driver needs: current status, info-requested notice + what to fix, rejection reason, resubmission path. Requires new driver-facing endpoint (API spec §3.4) — not FCM-dependent |

---

## 6. Ride booking, dispatch & operations

| Item | Status | Evidence |
|---|---|---|
| Ride state machine | IMPLEMENTED | 14 states in `src/rides/types.ts:1-16`; transitions enforced in `src/rides/state_machine.ts` + `ride_service.ts` transactions; `docs/ORA_STATE_MACHINE.md` |
| Offer/dispatch model | IMPLEMENTED | N4 waves (max 3, radii 10/15/25km, caps 5/10/15, 5s cadence) → driver accepts invite → `rideOffers` → passenger `selectOffer` assigns atomically — `dispatch_wave_service.ts`, `ride_service.ts` |
| **One active ride per passenger** | **APPROVED — NOT YET IMPLEMENTED** | DR-008 approved 2026-11-24 (backend tx enforcement in `createRide`); audit confirms "NOT yet coded" (`docs/engineering/ORA_ENGINEERING_DECISION_REGISTER.md` DR-008). Admin planning assumes it as an invariant but must not claim it exists |
| Driver busy check | IMPLEMENTED | `createOffer` queries `rides WHERE assignedDriverId==uid AND state IN busy set` (`ride_service.ts:~1928`) — one active ride per driver already enforced transactionally |
| Admin ride visibility | MISSING | `GET /v1/rides` is owner-scoped (`passengerId`/`assignedDriverId == caller`); no admin cross-user query endpoint |
| Admin ride intervention | MISSING | No force-cancel/force-transition/manual-assign. State machine doc floats "admin-only `force_transition`" as design intent (`ORA_STATE_MACHINE.md:185`) — not built |
| Cancellation rules | IMPLEMENTED | Pre-assign: passenger only. Post-assign: passenger or assigned driver. Courier: forbidden once parcel in custody. `cancellationFeeMinor` always 0 — `ride_service.ts:2654` |
| Ride categories / serviceTypes | IMPLEMENTED | `category` validated vs `pricingRules/{city}_{category}`; `serviceType ∈ ride|courier|buy_deliver|intercity|move` — `rides/types.ts`, `pricing_rules_repository.ts` |
| Courier v2 | IMPLEMENTED | Multi-stop, OTP, settlement (driver-reported cash), quotes, disputes — `ride_service.ts` courier methods |

---

## 7. Payments, commissions, transactions

| Item | Status | Evidence |
|---|---|---|
| Fare engine | IMPLEMENTED | `src/pricing/fare_calculator.ts`; `POST /v1/pricing/estimate` + `pricingSnapshots` (10-min TTL) |
| Pricing rules admin-seeding | PARTIAL | `pricingRules/{city}_{category}` docs, client-denied; seeded via `buildPricingRuleSeed()` + scripts — **no HTTP admin API** (`pricing_rules_repository.ts:239`) |
| Fee/commission policy | PARTIAL | `feePolicies` collection + `src/pricing/fee_policy.ts`; launch policy = fee NONE → `driverPayoutMinor = agreedFareMinor`; snapshot frozen on ride at offer-select |
| Payment intents/attempts/wallet/ledger/payouts/refunds/reconciliation | PLANNED | Collections in schema doc + rules deny; **zero code writes them** |
| Cash settlement (courier) | IMPLEMENTED | Driver-reported `settlement` + customer `acknowledge` — never verified, by design |
| Admin financial oversight | MISSING | No read APIs for fares/payouts; `driverPayoutMinor`/`platformFeeMinor`/`feePolicySnapshot` exist on ride docs |

---

## 8. Ratings, reviews, complaints, safety

| Item | Status | Evidence |
|---|---|---|
| Ride ratings | IMPLEMENTED | `POST/GET /v1/rides/:rideId/ratings`; `ratings/{rideId}_{type}`; stars 1–5; one per direction; only after `RIDE_COMPLETED|RIDE_CLOSED|RETURNED`; outbox event emitted. **No tags/comments, no aggregate scores** |
| Courier disputes | PARTIAL | `POST /v1/rides/:rideId/disputes` (courier v2 only, 48h window via `deliveryConfig.disputeWindowHours`); statuses `OPEN|RESOLVED|DISMISSED` defined but **no resolve/dismiss endpoint exists** |
| General reports / complaints / moderation | MISSING | `reports`, `moderationCases`, `supportTickets`, `supportTicketMessages`, `safetyEvents`, `blocks` — all rules-denied, zero code |
| Safety features (SOS, share-trip, verify-driver) | PLANNED | `docs/product/safety-flow.md`; mobile `features/safety` is a stub |

---

## 9. Notifications & communication

| Item | Status | Evidence |
|---|---|---|
| FCM push pipeline | IMPLEMENTED | Durable `outboxEvents` → `outboxDeliveries` (lease/CAS, retries, dead-letter) → projectors `DispatchFcmProjector` + `RideStateFcmProjector` (13-event allowlist, identifiers-only) → sweeps via `/v1/internal/outbox/*-sweep` on Cloud Scheduler |
| Device tokens | IMPLEMENTED | `driverDeviceTokens` (approved drivers), `passengerDeviceTokens` (passengers); register/clear endpoints |
| Admin-initiated notifications / broadcast | MISSING | No mechanism for ad-hoc push; payloads identifiers-only by design |
| Driver application status push | MISSING | No `driver.application.*` outbox event types exist; driver status UX must work **without** push (in-app status screen is the reliable channel) |
| Email / SMS / in-app inbox | MISSING | No email/SMS backend; no `notifications` collection/inbox |

---

## 10. Platform configuration

| Item | Status | Evidence |
|---|---|---|
| City catalog | PARTIAL | `cities/{cityId}` + `CityCatalogService` (Admin SDK upsert; client-denied); import blocked by licensing gate `PRODUCTION_IMPORT_STATUS='BLOCKED_PENDING_LICENSING_REVIEW'` |
| Delivery config | IMPLEMENTED (read) | `deliveryConfig/global` via `GET /v1/delivery-config`; **no write API** |
| Pricing rules | PARTIAL | See §7 — seed-only, no admin CRUD |
| Feature flags | PARTIAL | Env flags only; no runtime-config collection |
| Fee policies | PARTIAL | Collection exists, launch default; no admin CRUD |

---

## 11. Existing admin-related functionality

| Item | Status | Evidence |
|---|---|---|
| Admin role type | PLANNED | `UserRole` includes `'admin'` (`src/types.ts:2`); never assigned/checked. **Reconciled: admin authority = `adminOperators` collection, independent of `users.role`** |
| Admin audit collection | PLANNED | `adminAuditLogs` deny-all in rules (`firestore.rules:151`); zero writers |
| Ops scripts (write-capable) | IMPLEMENTED (manual) | ~90 scripts; `seed_e2e_driver_profile.ts` sets `role:'driver',driverStatus:'approved'` on real users; `seed_device_test_accounts.ts` emulator-only; city import dry-run; pricing seed helpers. Guard `assertScriptFirebaseTarget` exists after a past prod-write incident |
| Firebase Console dependency today | MISSING | All admin mutations currently require Console/scripts — exactly what the admin platform must replace |

---

## 12. Feature classification summary

| Domain | Implemented | Partial | Planned | Missing |
|---|---|---|---|---|
| Accounts/auth | register, me, profile, mode switch | — | adminOperators identity | ban/suspend/deactivate writers, admin session model |
| Driver lifecycle | onboarding submit, auto-approve, availability, geo | pending state unreachable | **manual review (CONFIRMED req)**, doc text-KYC | approve/reject/info-request/resubmit writers, suspension writer, driver-facing status endpoint |
| Driver mid-ride vs suspension | — | — | — | VERIFIED: progression does not re-check driverStatus (desired) |
| Vendor | — | frontend catalogues | full backend per marketplace plan | everything backend + admin; doc storage blocked on cost decision |
| Categories | hardcoded 6 vehicle categories + pricingRules keys | — | admin-managed collection | category CRUD, assignment, visibility |
| Rides/dispatch | full state machine, waves, offers, courier v2 | — | one-active-ride guard (approved, uncoded) | admin read/override/cancel, manual dispatch |
| Payments | fare engine, fee-policy snapshot, cash settlement | feePolicies unused | intents/wallet/ledger/payouts/refunds | all payment admin + most processing |
| Ratings/reviews | stars per ride | — | aggregates, tags/comments | rating moderation, aggregates |
| Complaints/disputes | courier dispute open | no resolve path | general reports/tickets | dispute resolution, reports, moderation, support |
| Notifications | FCM outbox projectors | ride-state projector undeployed | admin broadcast events | broadcast, admin notifications, in-app inbox, email/SMS |
| Config | cities (gated), deliveryConfig read | pricingRules seed-only | runtime feature flags | admin CRUD for all config |
| Audit | rideEvents (ride-scoped), outboxEvents | — | adminAuditLogs reserved | admin action audit trail |

---

## 13. What this means for admin scope

1. **The enforcement half already exists for new work.** Suspension blocks new offers/invites/location/availability immediately; **verified** that in-flight ride progression does not re-check `driverStatus`, so suspending a driver mid-trip cannot strand the ride — matches the "don't bypass trip safety rules" requirement.
2. **Manual driver approval is a confirmed requirement.** The safe rollout is: ship admin review endpoints → test on staging → only then set `DRIVER_AUTO_APPROVE=false`. Until then auto-approve remains the production behavior.
3. **The review half does not exist.** `driverStatus='pending'` is unreachable by default; the admin platform must ship approval/rejection/info-request/resubmission **before** auto-approve is disabled.
4. **KYC is text-only in V1.** Document *images* require paid Firebase Storage — **not approved**. V1 reviews CNIC/license *numbers* + vehicle details manually. Public avatar (`avatarData` base64) is unrelated existing functionality.
5. **Vendors are a planned domain**, blocked on marketplace backend + a zero-additional-cost document strategy.
6. **Financial admin is mostly future.** Only fare/payout snapshot fields exist on rides; commissions modeled but unexercised (launch fee = 0).
7. **Moderation surface is greenfield** but collections are already reserved deny-all in rules.
8. **One-active-ride-per-passenger is approved but uncoded** — admin ride tooling must be designed so force-cancel remains safe whether or not the guard has shipped; never rely on it existing.
