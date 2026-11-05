# ORA Super-App Expansion: Audit and Implementation Plan

**Status:** Steps 1–2 approved (frontend only). Step 1 implemented (PR #2). Steps 3+ (vendor, admin, Storage, marketplace booking backend) not started and need separate approval.

**Progress log**
- Local `cost-optimization-local` work backed up to `backup/cost-optimization-local-2026-11-04` (142 files; `google-services.test.json` excluded). Baseline on that branch: 23 passenger-home / ride-request Flutter tests fail that pass on `master` (`pumpAndSettle` timeouts), so Steps 1–2 are built on `master` (latest verified code) until that is resolved.
- Step 1: `OraModuleGrid` on home, `/rides` hub (City + Intercity unchanged; Courier + Move remain Coming later), placeholder `/logistics` `/rental` `/services`. analyze: no new issues; flutter test: 789 pass / 1 pre-existing master failure.
**Audited revision:** `master` @ `7449cc7` (GitHub). Your local branch `cost-optimization-local` (143 uncommitted files, not pushed) was **not** audited. See §0.

---

## 0. Blockers and decisions needed before implementation

| # | Issue | Why it matters | Recommendation |
|---|-------|----------------|----------------|
| 1 | Local branch `cost-optimization-local` is unpushed (143 files: geo client, presence publisher, pricing, indexes, deploy scripts) | New work branched from `master` would conflict with it, and I can't see those changes | Commit and push it as its own branch (or merge to `master`) first. I'll then branch every marketplace PR from it. `master` stays untouched until you merge. |
| 2 | **No admin panel exists.** Drivers get approved by scripts writing `users.driverStatus`. `UserRole` already includes `'admin'`, but nothing uses it | Phase 7 means building an admin panel, not extending one | **Option A (recommended):** an in-app Admin section in the Flutter app, shown only when `/me` says `role=admin`. It reuses Firebase Auth, App Check and the backend, with no new hosting. **Option B:** a separate Flutter Web admin build on Firebase Hosting (free tier), which also needs web App Check setup. |
| 3 | **Firebase Cloud Storage needs the Blaze (billing-enabled) plan** for new buckets (Firebase pricing change, 2024; I'll re-check the current terms before provisioning) | Vendor documents and property/portfolio photos need file storage. There is no zero-cost alternative inside Firebase. | Enable it only on staging, with a budget alert. The Blaze no-cost quotas still apply (see §8). Until it's approved, upload steps ship disabled and are labelled "Uploads available after setup". |
| 4 | **Staging is down.** Both GCP projects have `billingEnabled=false` (per `ORA_CURRENT_STATE.md` #30), so Cloud Run is suspended | "Test in staging first" can't happen until billing is restored. Restoring billing also restarts the leftover Memorystore and VPC connector (~$84/mo) unless you delete them first. | Test against local Firebase emulators plus the local backend (free). Delete the Redis/VPC leftovers **before** re-enabling billing (owner-approved operation). |
| 5 | The full app needs `google-services.json` (gitignored) to run on the emulator for screenshots | Without it I can only render screens in a Firebase-free preview harness | Give it to me as a secret, or I'll screenshot through a preview entrypoint, as was done for chat (`main_chat_preview.dart`). |
| 6 | Chat UI lives on the unmerged branch `devin/chat-ui-1793706006` (23 files, needs Flutter 3.47 / Dart 3.13; has a known build_runner incompatibility) | The vendor-customer contact feature can't rely on it yet | Use lightweight inquiry threads (backend plus FCM nudge, no live listeners) in v1. Move to the chat UI once it's merged. |

---

## 1. Codebase audit (current state)

### 1.1 Mobile (Flutter, Riverpod, go_router, MVVM)
- **Features:** `auth`, `onboarding`, `passenger`, `ride`, `driver`, `maps`, `saved_places`. `payments` and `safety` are empty placeholders.
- **Routes** (`lib/app/router/routes.dart`): `/`, `/auth/phone`, `/auth/otp`, `/onboarding`, `/home`, `/rides/request`, `/rides/requested`, `/rides/:id/{offers,active,detail,rate}`, `/driver`, `/driver/{open,rides,rides/:id,offer}`, `/devtools/maplibre-poc`.
- **Guard** (`route_guards.dart`): auth-status state machine. `/driver/*` requires `isApprovedDriver` from server `/me`.
- **Home** (`passenger_home_view.dart`, 864 lines): hero header with drawer and avatar, "Where are you headed?", promo card, "Earn on ORA", **Services grid** (`_ServicesGrid`, 4 image tiles), "Choose a ride" (6 categories: zip, trio, easy, breeze, executive, premium), Saved places (static Home/Work rows), Quick actions (My rides, Wallet *(coming later)*, Safety *(coming later)*).
- **Services grid status today:**

  | Tile | Behaviour | Backend |
  |------|-----------|---------|
  | City rides | `/rides/request` | Working |
  | Intercity | `/rides/request?service=intercity` | Working (`serviceType=intercity`) |
  | Courier | "Coming later" sheet | `serviceType=courier` is accepted by validation, but the UI is not exposed |
  | Move | "Coming later" sheet | Same as Courier (`move`) |

- **Drawer** (`home_shell_view.dart`): Home, My rides, Saved places / Wallet / Refer / Safety / Settings / Help *(all coming later)*, Switch to driver mode (re-fetches `/me`), MapLibre PoC, Log out.
- **Design system** (`lib/app/theme/`): `OraColors`, typography (Sora + Inter), spacing, radius, elevation, motion, and widgets (`OraCard`, `OraButton`, `OraChip`, `OraBottomSheet`, `OraDrawer`, `OraEmptyState`, `OraErrorState`, `OraStarRating`, `OraTextField`, `OraSectionHeader`, `OraListRow`, `OraLoadingIndicator`). The new modules will reuse all of these.
- **Not present:** `cloud_firestore` (all data goes through the backend API), `firebase_storage`, image picker, network-image cache, chat.
- **Tests:** about 776 Flutter tests (last recorded full run 776/776), plus 2 integration tests.

### 1.2 Backend (`backend/auth-service`, Express modular monolith on Cloud Run)
- **Routers:** `/v1/auth` (register, me, profile), `/v1/rides` (create, offers, select, progression, close, history, open, invites), `/v1/drivers` (availability, nearby, tokens), `/v1/location`, `/v1/pricing` (estimate), `/v1/internal` (sweepers).
- **Identity:** Firebase ID token through Admin SDK. `users/{uid}` holds `role` (`passenger|driver|admin`) and `driverStatus`. Clients can never write role fields.
- **Matching:** Firestore-native geo (`geoDrivers`, bounding box), N3 busy-prefetch, N4 waves `[10,15,25]` km, invites with a 20s TTL. **Frozen: this plan does not touch it.**
- **Outbox → FCM projector** for notifications. This is reusable for vendor and booking notifications.
- **Tests:** about 521 backend tests, plus rules tests (`test/firestore.rules.test.mjs`).

### 1.3 Firebase
- **Firestore rules:** fail-closed. Clients can read only their own `users/{uid}` and own `savedPlaces`. Everything else, including `rides`, `drivers`, `ratings`, `reports`, `moderationCases` and `adminAuditLogs`, is denied, and all access goes through the Admin SDK. `reports`, `moderationCases` and `adminAuditLogs` are declared but **unused in code**, so they can be adopted safely.
- **Indexes:** 17 composite indexes.
- **RTDB:** trip-location projection only.
- **Storage:** none (no `storage.rules`, no SDK).

### 1.4 Breaking-change risks found
1. `_ServicesGrid` owns the only entry points for City and Intercity. Moving them must keep the exact same `_openRideRequest(category, serviceType)` calls.
2. Courier and Move are already valid backend `serviceType` values. Exposing them in the UI would create real rides in the matching pipeline, so they **stay "Coming later"**.
3. Adding a vendor role to `users.role` would break the driver gate (`role=='driver'`). Vendor roles must live in **separate docs**, never in `users.role`.
4. `firestore.rules` is deny-all. New collections need explicit deny blocks (documentation and contract tests), not "allow" rules.
5. The analyze/codegen toolchain is pinned (Flutter 3.35.6 in CI). New code must not require newer SDKs, and Freezed codegen must keep working.

---

## 2. Architecture

### 2.1 Principles
- **API-mediated everything** (same as rides): the mobile app calls new `/v1/marketplace/*` endpoints, and Firestore rules stay deny-all for every new collection. Admin approval is enforced by the backend **and** by the rules (clients can't write anything), so hidden buttons are never the only control. This avoids adding `cloud_firestore` to the app (smaller app, no listeners).
- **Static catalogues are bundled** (Logistics: 8 categories / 42 types; Services: 11 categories / 88 subcategories) as one versioned JSON (`catalogue_v1.json`). The app reads it as an asset, and the backend imports the same IDs for validation. A contract test fails if the two copies drift. Browsing and searching the catalogues costs **0 Firestore reads**.
- **One shared vendor system, three business models.** Each vendor profile is keyed `vendors/{uid}_{kind}` with `kind ∈ rental|service|logistics`, so one user can hold several roles and duplicate profiles are impossible. Passenger and driver data in `users/{uid}` is never modified.
- **Uploads through backend-issued V4 signed URLs:** the client PUTs with the existing `dio`, so no Storage SDK is needed. Storage rules deny all client access to `vendor-private/**`. Public listing images live under `listing-public/**` with authenticated read only.
- **Notifications:** new outbox event types (`vendor.status_changed`, `booking.*`, `inquiry.message`) go through the existing FCM projector. No polling and no live listeners. Lists refresh on screen open and pull-to-refresh.
- **Concurrency:** bookings use deterministic lock docs written in a Firestore transaction (`rentalNightLocks/{listingId}_{yyyymmdd}`, `providerSlotLocks/{vendorId}_{yyyymmddHH}`). Two overlapping confirmations can't both commit. Every create needs an `Idempotency-Key`, reusing the existing `idempotencyRecords` pattern.
- **Honesty:** ratings, reviews, completed-job counts and availability are computed only server-side from real completed bookings. Empty states replace fake data. Any test fixtures exist only in the emulator and are labelled "TEST DATA".

### 2.2 Proposed Firestore schema (all collections: client read/write = deny)

| Collection | Key fields | Notes |
|------------|-----------|-------|
| `vendors/{uid}_{kind}` | `ownerUid, kind, status (pending, under_review, info_requested, approved, rejected, suspended), displayName, businessName?, city, serviceAreas[], avatarPath, publicContactConsent, ratingAvg, ratingCount, completedJobs, createdAt, updatedAt` | Public-safe fields only |
| `vendors/{id}/statusEvents/{e}` | `from, to, actorUid, reason, at` | Approval history |
| `vendorPrivate/{vendorId}` | `legalName, cnicLast4, phone, email, businessRegNo?, reviewerNotes` | Sensitive data; admin API only |
| `vendorDocuments/{docId}` | `vendorId, type (cnic_front, cnic_back, ownership_proof, business_reg, license, qualification), storagePath, status, reviewedBy` | Files in `vendor-private/{uid}/...` |
| `rentalListings/{id}` | `vendorId, status (draft, pending_review, active, paused, rejected, suspended), title, propertyType, description, city, area, address, lat, lng, priceMinor, currency=PKR, priceUnit (night, day, month), maxGuests, bedrooms, amenities[], rules[], images[{path,w,h}], ratingAvg, ratingCount, searchTokens[], updatedAt` | Only `active` listings from `approved` vendors are publicly listable |
| `rentalBookings/{id}` | `listingId, vendorId, guestUid, checkIn, checkOut, guests, priceSnapshot, state (requested, accepted, confirmed, declined, cancelled, completed)` | |
| `rentalNightLocks/{listingId}_{date}` | `bookingId` | Created in the confirm transaction, so overlaps are impossible |
| `serviceOfferings/{id}` | `vendorId, categoryId, subcategoryId, title, priceType (fixed, hourly, quote), priceMinor?, city, onlineAvailable, status, searchTokens[]` | |
| `serviceBookings/{id}` | `offeringId, vendorId, customerUid, scheduledAt, address or online, requirements, photos[], quoteMinor?, state (requested, quoted, accepted, scheduled, in_progress, completed, cancelled, declined)` | |
| `providerSlotLocks/{vendorId}_{slot}` | `bookingId` | Prevents double booking |
| `logisticsRequests/{id}` | `customerUid, vehicleTypeId, pickup, dropoff, stops[], scheduledAt, cargo{description, weightKg, dims, qty}, loadingHelp, handling[], photos[], contact, mode=quote, state (submitted, quoted, accepted, cancelled, completed)` | |
| `logisticsQuotes/{id}` | `requestId, vendorId, amountMinor, validUntil, notes, state` | Only approved logistics operators can quote |
| `marketplaceInquiries/{threadId}` + `/messages` | `targetType, targetId, customerUid, vendorId, lastMessageAt` | Contact without exposing phone numbers |
| `marketplaceReviews/{bookingId}` | `targetType, vendorId, listingOrOfferingId, authorUid, stars, text, status` | Doc id = booking id: one verified review per completed booking |
| `favorites/{uid}_{type}_{targetId}` | `uid, targetType, targetId, createdAt` | |
| `reports`, `moderationCases`, `adminAuditLogs` (existing, unused) | Adopted for complaints, moderation and the audit trail | Every admin mutation writes `adminAuditLogs` in the same transaction |

Search uses `searchTokens` (normalized lowercase words, prefixes and synonyms generated by the backend at write time) with `array-contains` + `city ==` + `status ==` + `limit 20` + cursor pagination. Price, rating and sort options map to explicit composite indexes, about 8 new ones. Search is server-side text-token search, not full-text search; this is a documented limitation.

### 2.3 Admin authorization
A `requireAdmin` middleware loads `users/{uid}.role === 'admin'`, the same source as the driver gate. Roles are set by script and never by a client. Each admin action records `{actorUid, action, targetRef, before, after, reason, requestId}` in `adminAuditLogs`. Document viewing returns **short-lived (5 min) signed read URLs** and logs every view.

---

## 3. Feature classification

| Class | Features |
|-------|----------|
| **A. Frontend-only** | 4-module home cards; Rides hub (re-hosting existing City/Intercity entries, with Courier/Move/Logistics labelled honestly); Logistics catalogue browse (8 categories / 42 types); Services catalogue browse plus local debounced search with synonyms (11 / 88); marketplace widget kit; Rental UI shell with honest empty and "coming soon" states |
| **B. Existing backend only** | Rides hub City and Intercity flows (unchanged); profile and drawer; FCM projector reused for new events |
| **C. New backend, collections, rules, indexes, admin** | Vendor onboarding and approval; admin section; rental listings, search, detail, favorites; rental booking requests plus transactional confirmation; inquiries; service offerings, provider search, bookings, quotes, reviews; logistics quote requests and operator quotes; reports and moderation |
| **D. External or operational approval** | Cloud Storage (Blaze); restoring staging billing; payments and wallet (none implemented, so bookings are "pay vendor directly" and labelled as such); CNIC verification against NADRA (manual admin review only, with no automated KYC); licence checks for regulated services (manual admin review); instant dispatch for logistics road vehicles (needs vehicle-type eligibility in matching, which is frozen and needs separate approval); air, rail and sea freight (quote-only, no real providers) |

**Logistics booking honesty:** in v1 **every** logistics type is a **quotation request** answered by approved logistics operators. No type is shown as "instant booking", because instant dispatch would need vehicle-type eligibility in the frozen matching engine.

---

## 4. UI design approach
- **Illustrations:** **Microsoft Fluent Emoji 3D** (MIT licence, free) covers every module and category visual in one consistent 3D style. Examples: car, delivery truck, house, toolbox, wrench, high voltage, broom/bucket, lipstick, stethoscope, ship, airplane, helicopter, locomotive, crane, auto-rickshaw, bicycle, motorcycle, pickup. Exported as **WebP** at 1x/2x/3x (about 4–12 KB each) and bundled locally, with the licence file included. Individual services get Material Symbols icons tinted in category colours, so 88 extra bitmaps aren't needed.
- **Module cards:** 2×2 grid, rounded `OraRadius`, existing ORA navy/gold palette with a gradient per module, `OraElevation` shadow, 3D illustration overflowing the top-right corner, scale-on-press of 0.97 over 120 ms (`OraMotion`). The rest of the home screen (header, search, promo, Earn, Choose a ride, Saved places, Quick actions) is **unchanged**.
- **Services module:** follows the reference service app (search bar, category carousel, "Popular services" carousel, featured and nearby providers once real ones exist), with a module bottom nav: Explore · Bookings · Inbox · Saved · Profile.
- **Rental module:** Booking.com-style cards (large image, heart, title, rating badge, review count, location line, short description, price per unit, View details / Contact vendor), plus a filter sheet and sort.
- **Performance:** `ListView.builder`/slivers, `cached_network_image` (free, widely used) with `memCacheWidth`, server-generated thumbnails (backend resizes on upload confirm), 20-item pages with infinite scroll, and 300 ms debounce on search.

---

## 5. Phased implementation (one PR per step, each on its own branch; `master` untouched until you merge)

| Step | PR | Contents | Class |
|------|----|----------|-------|
| 1 | **Home + Rides hub** | Replace `_ServicesGrid` with `OraModuleGrid` (Rides, Logistics, Rental, Services). New `/rides` hub with City, Intercity (same calls as today), Courier (still Coming later), Logistics (→ catalogue). New routes `/logistics`, `/rental`, `/services` (shells). Widget tests for every tile's navigation. | A, B |
| 2 | **Catalogues** | `catalogue_v1.json`; Logistics home → category → vehicle type → quote-request form (submit disabled with "Available soon" until Step 6); Services home → category → subcategory → provider list (honest empty state); unified local search with synonyms (tests: "AC gas", "pipe leakage", "wedding"); shared marketplace widget kit | A |
| 3 | **Vendor foundation + Admin** | Backend: `vendors`, `vendorPrivate`, `vendorDocuments`, signed upload URLs, `storage.rules`, `requireAdmin`, audit log, `/me` additive `vendorRoles[]`. Mobile: shared onboarding stepper (kind-parameterized), status screen, drawer entry "Become a host / provider / operator", Admin section (applications, documents, approve / reject / request info / suspend). Rules and contract tests. | C, D(Storage) |
| 4 | **Rental listings** | Vendor listing editor and image upload, admin listing moderation, public list/search/filter/sort/detail APIs with pagination and indexes, favorites; wire the Rental UI | C |
| 5 | **Rental booking + inquiries** | Availability calendar, booking request → vendor accept → transactional confirm with night locks, cancellation, inquiry threads, vendor dashboard (properties, requests, inquiries), FCM events, concurrency tests | C |
| 6 | **Services + Logistics bookings** | Offerings, provider profiles, search tokens, service booking (package/quote → schedule → status), slot locks, verified reviews; logistics quote requests and operator quotes | C |
| 7 | **Moderation + docs + regression** | Reports and complaints, review moderation, admin dashboards; updated `ORA_CURRENT_STATE.md` and a new `docs/architecture/MARKETPLACE_ARCHITECTURE.md`; full regression run | C |

Each PR includes: `flutter analyze`, the full Flutter test suite, backend `npm test` plus `tsc`, rules tests in the emulator, screenshots, and a per-feature backend-status table.

---

## 6. Files to create and modify (planned)

**Modify (additive only):**
`mobile/lib/app/router/{routes,app_router,route_guards}.dart`; `mobile/lib/features/passenger/presentation/views/passenger_home_view.dart` (only `_ServicesGrid` → module grid); `home_shell_view.dart` (new drawer items); `mobile/lib/features/auth/.../session_user_profile.dart` (optional `vendorRoles`, `isAdmin`); `mobile/pubspec.yaml` (assets, `cached_network_image`, `image_picker`); `backend/auth-service/src/app.ts` (mount routers); `src/services/profile.ts` (`/me` additive fields); `firestore.rules` (explicit deny blocks); `firestore.indexes.json`; `firebase.json` (+storage); `test/firestore.rules.test.mjs`; docs.

**Create (mobile):**
- `lib/features/marketplace_shared/` (module card, listing card, provider card, image gallery, rating summary, status badge, debounced search field, document upload tile, contact bar, empty and coming-soon states, API client)
- `lib/features/rides_hub/`
- `lib/features/logistics/{domain/catalogue, presentation}`
- `lib/features/services/{domain/catalogue, domain/search, presentation}`
- `lib/features/rental/`
- `lib/features/vendor/` (onboarding, status, dashboard, listing editor)
- `lib/features/admin/`
- `assets/marketplace/{modules,logistics,services}/*.webp`
- `assets/marketplace/catalogue_v1.json`
- Tests mirroring each feature

**Create (backend):**
- `src/marketplace/catalogue/`
- `src/marketplace/shared/` (uploads, search tokens, reviews, inquiries, favorites, locks)
- `src/vendors/`
- `src/marketplace/{rental,services,logistics}/`
- `src/admin/` (routes, `requireAdmin`, audit)
- `storage.rules`
- Tests and Firestore emulator proofs for each

---

## 7. Regression and test plan
- **Automated:** the existing Flutter suite (about 776) and backend suite (about 521) must stay green. New tests: route-guard tests (admin and vendor gates), home-tile navigation, catalogue integrity (88 subcategories, 42 vehicle types, unique IDs, JSON contract between app and backend), search synonyms, vendor state-machine transitions, ownership checks (a vendor can't edit another vendor's listing), admin-only endpoints (403 for others), booking concurrency (parallel confirms on overlapping nights → exactly 1 succeeds), idempotency replays, and rules tests (all new collections denied to clients).
- **Device (Android emulator on my VM; iOS via a macOS session if you want it):** login/OTP, passenger home, City and Intercity compose, driver mode switch and availability, offers, wallet/profile placeholders, all new module routes, and small and large screen sizes.
- **Staging:** blocked until billing is restored (§0 #4). Meanwhile, Firebase emulators plus the local backend.

---

## 8. Firebase cost assessment (estimates; rates vary by region, I'll verify on the pricing page before enabling anything)

No-cost quotas: Firestore 50k reads, 20k writes, 20k deletes per day and 1 GiB stored. Cloud Run 2M requests per month (it already scales to zero). Cloud Storage on Blaze has a small no-cost tier (about 5 GB stored plus a free download allowance in eligible US regions); beyond that, roughly $0.026/GB-month stored and about $0.12/GB egress.

| Activity | Reads | Writes | Notes |
|----------|-------|--------|-------|
| Home, catalogues, service search | 0 | 0 | Bundled JSON |
| Listing / provider page (20 cards) | 20 | 0 | Cursor pagination |
| Listing detail (+vendor, 10 reviews) | ~12 | 0 | |
| Booking request → confirm (3 nights) | ~6 | ~8 | Booking, locks, outbox, audit |
| Vendor application | ~3 | ~6 | Plus 4–8 document uploads |

- **100 DAU** (test scale): about 15–20k reads/day, which is **inside the free tier**. Storage for about 200 listings × 8 images × 150 KB ≈ 240 MB, also inside the free tier.
- **1,000 DAU:** about 170k reads/day, roughly $1–3/month for Firestore. Image egress is the main cost: 1,000 × 30 thumbnails × 60 KB ≈ 1.8 GB/day ≈ $5–7/month, reduced by the on-device cache and WebP thumbnails.
- **No new always-on infrastructure:** no Redis, no VPC, no schedulers beyond the existing (paused) ones.

---

## 9. Backend integration status (target after each step)

| Feature | After Step 1–2 | Final |
|---------|----------------|-------|
| City rides / Intercity | Working (unchanged) | Working |
| Courier / Move | Coming later (unchanged) | Coming later until separately approved |
| Logistics catalogue browse | Working (local) | Working |
| Logistics booking | Form shown, submit disabled ("Available soon") | Quote request, real backend |
| Services catalogue + search | Working (local) | Working |
| Service providers / booking | Honest empty state | Real backend, approved providers only |
| Rental listings / detail | Honest empty state | Real backend |
| Rental booking | Not available | Request → confirm, transactional |
| Vendor onboarding / admin | Not available | Real backend (uploads need Storage approval) |
| Payments / wallet | Coming later | Coming later ("pay vendor directly" shown) |
