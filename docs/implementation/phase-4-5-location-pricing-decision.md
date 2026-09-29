# Phase 4 Location/Routes + Phase 5 Pricing — Architecture Decision Freeze

**Status:** ARCHITECTURE FROZEN (docs only) — **2026-09-22**  
**Authority:** This document + verified code in `backend/auth-service` and `mobile/`  
**Implementation:** **5C CODE COMPLETE (2026-09-22)** — Flutter estimate client + review UI + city on create + capabilities from live estimate. **Physical-device proof pending** (Samsung not attached at close). Do not fabricate fares or `pricingSnapshotId`. Do not start 5D until 5C device proof is audited.

**Related (do not contradict):**

| Artifact | Role |
| -------- | ---- |
| [`ADR-004`](../architecture-final/ADRs/ADR-004-Redis-GEO-Optimization.md) | Redis GEO = candidate generation only |
| [`ADR-007`](../architecture-final/ADRs/ADR-007-P2P-Offer-Fare-Model.md) | Offered-fare marketplace |
| [`ADR-011`](../architecture-final/ADRs/ADR-011-Location-Architecture.md) | Driver GPS untrusted; N2A validation |
| [`CITY-PARTITION-STRATEGY-DECISION.md`](n-series/CITY-PARTITION-STRATEGY-DECISION.md) | Coordinate-primary matching |
| [`RIDE-CITY-SCHEMA.md`](n-series/RIDE-CITY-SCHEMA.md) | `rides.city` metadata; create still requires `city` today |
| [`N3-nearby-planning.md`](n-series/N3-nearby-planning.md) / [`N4-dispatch-planning.md`](n-series/N4-dispatch-planning.md) | Pickup lat/lng → nearby / dispatch |
| [`fare-engine.md`](../algorithms/fare-engine.md) | Recommended-fare formula + snapshot shape (intent) |
| [`ORA_CURRENT_STATE.md`](../ORA_CURRENT_STATE.md) | Live shipped status |

**Legend for claims below:**

| Tag | Meaning |
| --- | ------- |
| **CODE** | Verified in repository |
| **DOC** | Existing Ora documentation (may be aspirational) |
| **PROVIDER** | Official third-party documentation (cited) |
| **FREEZE** | Decision locked by this document |

---

## 1. Executive Summary

Passenger Ride Request on the physical Android device is blocked by **two independent product gaps**, not by a network misconfiguration:

1. **Phase 4 gap (CODE):** Flutter pickup/destination are **text-only**; `RideRequestCapabilities.resolvedPickup/Destination` are empty; create body never gets lat/lng.
2. **Phase 5 gap (CODE):** There is **no** `POST /v1/pricing/estimate` (or any pricing route). `pricingSnapshots` are created only by **test/fixture seeds**. The UI shows **"Pricing unavailable"** from a **local capability gate** before any HTTP call.

**This freeze selects:**

| Area | Decision |
| ---- | -------- |
| Maps / Places / Routes provider | **Google Maps Platform** as production provider for Phase 4–5 |
| Abstraction | Minimal **`RoutingProvider`** + **`PlaceResolution`** ports (server); Flutter uses Places/GPS/map for resolution UX |
| Pricing API | **`POST /v1/pricing/estimate`** (name confirmed to match docs + `/v1` convention) |
| Snapshot authority | **Server-only** create of `pricingSnapshots/{id}`; client **never** fabricates IDs |
| Distance/time | Computed **server-side** via Routes; client must **not** supply trusted D/T for fare |
| City | Remains **create metadata** (still required by API today); **not** matching key; soft-deprecation is a **separate** API slice |
| N3/N4 | **Unchanged** — continue to consume durable `ride.pickup.lat/lng` |

**Next implementation slice after this freeze:** **Phase 4A — Passenger pickup/destination coordinate resolution** (Flutter). Pricing estimate cannot run without coordinates.

---

## 2. Verified Current State

### A. Flutter pickup/destination today (**CODE**)

- Compose UI stores **strings only** (`pickupText`, `destinationText`) — `ride_request_view_model.dart`.
- Map chrome is decorative (`RideLocationPlaceholder`: “Live maps and GPS open in a later build”).
- Copy: “Location unresolved — text only for now”.
- Categories show **`Price TBD`** (`ride_category_option.dart`).
- `rideRequestCapabilitiesProvider` returns **`const RideRequestCapabilities()`** — empty pricing + empty coords.
- Submit gate order: incomplete text → **`pricingUnavailable`** → **`locationUnavailable`**.
- Sheet title **"Pricing unavailable"** is UI mapping of `RideRequestBlockReason.pricingUnavailable` (`ride_request_view.dart`).
- When create is eventually allowed, body would send `{ pickup: {lat,lng,address?}, destination: {...}, category, serviceType, passengerOfferMinor, pricingSnapshotId, paymentMethod, passengerCount }` — **no `city` field yet** in Flutter create body (**CODE** mismatch vs backend).

### B. Coordinates in passenger flow (**CODE**)

- **None** in production passenger compose path.
- Domain type `LatLngPoint { lat, lng, address? }` exists for API projections / tests only.
- Device GPS / Maps / Places packages: **absent** from `mobile/pubspec.yaml` (no `geolocator`, `google_maps_flutter`, Places).

### C. Backend ride create requirements (**CODE**)

`POST /v1/rides` (`ride_service.createRide`):

| Field | Rule |
| ----- | ---- |
| `pickup` / `destination` | Objects with numeric `lat`/`lng` (WGS84 range); optional `address` string |
| `city` | **Required** today (`normalizeCitySlug`); matching **not** gated on it |
| `category` | Required string |
| `passengerOfferMinor` | Positive integer minor units |
| `pricingSnapshotId` | Required; loaded via `loadPricingSnapshot` |
| `paymentMethod` | `CASH` \| `WALLET` \| `ONLINE_PAYMENT` |
| `passengerCount` | 1–6 (default 1) |
| Idempotency | `Idempotency-Key` header required |

### D. How `pricingSnapshotId` is validated (**CODE**)

`pricing_snapshot.ts` → `loadPricingSnapshot`:

- Doc must exist in `pricingSnapshots/{id}`
- `expiresAt` must be in the future
- `recommendedFareMinor`, `offerBoundMinMinor`, `offerBoundMaxMinor` numeric; `currency === 'PKR'`
- `assertOfferWithinBounds(passengerOfferMinor, snapshot)` or `422 FARE_OUT_OF_BOUNDS`
- Missing/expired → `422 PRICING_SNAPSHOT_EXPIRED`

### E. Where snapshots are created today (**CODE**)

- **Only** test helpers / proof scripts: `db.seed('pricingSnapshots', …)` or Admin SDK `.set(...)` in concurrency scripts.
- **No** production writer path in `src/` outside ride create **readers**.

### F. Production API that creates snapshots (**CODE**)

- **None.** `POST /v1/pricing/estimate` and `GET /v1/pricing/rules` return **404** (`API_CONTRACT_INDEX` “Not registered”; live probe confirmed during pricing investigation).

### G. Snapshot fields today (**CODE** + **DOC**)

**Implemented `PricingSnapshotDoc` (**CODE**):**

```ts
snapshotId, recommendedFareMinor, offerBoundMinMinor, offerBoundMaxMinor,
currency, pricingRulesVersion, computedAt, expiresAt, inputs?
```

**Fare-engine intent (**DOC**)** adds richer `inputs` (distanceKm, durationMin, categoryId, zoneId, demandMult, …). Create path already copies `inputs.distanceKm` / `inputs.durationMin` onto the ride when present (**CODE**).

### H. Distance/time expectations (**CODE**)

- Create does **not** require client-supplied distance/duration.
- Ride stores `distanceKm` / `estimatedDurationMin` from snapshot `inputs` when present; else `null`.
- N3/N4 do **not** use distance/duration for candidate generation (pickup lat/lng + fixed radius).

### I. City role (**CODE** + frozen n-series)

| Concern | Status |
| ------- | ------ |
| Matching (N3/N4) | **Coordinate-primary** — city **not** a gate |
| Create API | **`city` required** today |
| Flutter | No city selector; create body omits city |
| PBS city catalog | Licensing-blocked; **not** Phase 4/5 matching dependency |

### J. N3 pickup consumption (**CODE**)

`NearbyDriversService.findNearby({ lat, lng, radiusKm, … })` → Redis `GEORADIUS` on `geo:drivers`. Internal HTTP requires `lat`/`lng`.

### K. N4 pickup consumption (**CODE**)

`dispatch_wave_service` reads `ride.pickup.lat/lng` → `findNearby` with frozen **10 km** radius. City not used for candidate search after coordinate-primary resync.

### L. Existing provider abstraction (**CODE**)

- **None.** No Maps/Geocoding/Routes SDK or adapter in auth-service dependencies (`express`, `firebase-admin`, `ioredis`, `uuid` only).
- Planning docs assume Google (**DOC**); not implemented.

### Additional verified facts

| Fact | Evidence |
| ---- | -------- |
| Phase 5 doc status | `phase-05-pricing.md` — **NOT STARTED**; depends Phase 4 |
| Phase 4 doc status | `phase-04-maps-location.md` — **NOT STARTED**; broad Maps UX scope |
| Firestore rules | `pricingSnapshots` / `pricingRules`: client **read/write deny** |
| Real-device evidence | Home → Ride Request → Clifton/Saddar → Request → **"Pricing unavailable"**; **no** pricing HTTP; estimate curl **404** |

---

## 3. Problem / Blocker

```text
Passenger wants: text/search/GPS → coords → route → estimate → offer → POST /v1/rides → SEARCHING
Today:          text only → local pricing gate → STOP
Also missing:   server estimate writer, Flutter city on create, Maps packages
```

Fabricating a client `pricingSnapshotId` or hardcoding a fare **violates** ADR-007 / fare-engine / Firestore rules and will fail create (`PRICING_SNAPSHOT_EXPIRED`) unless someone illegally seeds Firestore. **Forbidden.**

---

## 4. Phase 4 Location Architecture

### Goal (**FREEZE**)

Produce **passenger-confirmed** pickup and destination points that satisfy the existing create contract:

```ts
{ lat: number, lng: number, address?: string }
```

These durable coordinates become:

- Pricing / routing inputs (server re-routes from lat/lng)
- `rides.pickup` / `rides.destination` (**immutable** for that `requestVersion` after create — no Phase 4/5 redesign of ride SM)
- N3/N4 spatial input (pickup only)

### Scope split (**FREEZE**)

| Slice | In scope | Out of scope |
| ----- | -------- | ------------ |
| **4A** | Resolve pickup + destination to lat/lng (+ display address); confirmation UX | Full nav, driver tracking, N2B RTDB |
| **4B** | Server `RoutingProvider` using Google Routes (distanceMeters, duration) | Client-trusted distance; Distance Matrix for matching |

Phase 4 planning doc’s full Maps polish (Kalman, BGGeo, custom style completeness) is **deferred** beyond 4A/4B MVP needed for create.

---

## 5. Pickup Resolution

### Decision (**FREEZE**): Combination model

Pickup resolution supports, in priority for MVP:

1. **Use current location** (device GPS via a future `geolocator` dependency — not added in this freeze).
2. **Place / address search** (Places Autocomplete / Place Details).
3. **Map pin adjust** (optional but recommended once Maps SDK exists): drag marker after GPS or search.

### Canonical objects (**FREEZE**)

**Server / durable ride point** (already implemented):

```ts
type RideLatLng = { lat: number; lng: number; address?: string };
```

**Client-resolved location** (Flutter presentation; may be richer than durable write):

```ts
// Conceptual — implement in Phase 4A; do not invent fields on ride create beyond RideLatLng
type ResolvedPassengerLocation = {
  lat: number;
  lng: number;
  address?: string;       // human label for UI + optional create.address
  placeId?: string;       // provider place id for sessioning / re-fetch; NOT required on create
  source: 'gps' | 'place' | 'map_pin' | 'saved_place'; // telemetry / UX only
};
```

### Confirmation (**FREEZE**)

- Passenger must **explicitly confirm** pickup before estimate.
- GPS alone is **proposed**, not final, until confirm (aligns with marketplace UX; avoids silent wrong pin).

---

## 6. Destination Resolution

### Decision (**FREEZE**)

Same resolution toolkit as pickup, with emphasis on **search + confirm**:

- Places Autocomplete (session tokens) → Place Details → lat/lng + formatted address.
- Optional map pin refine.
- Pakistan-first UX (Lahore and other major cities): bias autocomplete to device locale / viewport when available (**PROVIDER** Places best practices); do not hardcode city as matching shard.

### Client vs server trust (**FREEZE**)

| Data | Client may hold | Server trusts |
| ---- | --------------- | ------------- |
| Display address / placeId | Yes | Optional `address` string only |
| lat/lng for estimate/create | Yes (passenger-confirmed) | Re-validates WGS84 range; uses as routing origin/destination |
| Route distance/duration | Display only if returned by estimate | **Server-computed** only for fare |
| Fare / snapshot id | From estimate response | Re-loads snapshot on create |

### Failure UX (align existing tone) (**FREEZE**)

| Failure | Passenger message (intent) |
| ------- | -------------------------- |
| Unresolved / empty search | Keep current incomplete gate |
| Ambiguous places | Require explicit selection from suggestions |
| Geocode/Places outage | “Location lookup isn’t available right now. Try again.” |
| Invalid / impossible pin | “We couldn’t use that location. Pick another point.” |

---

## 7. Coordinate Trust Model

### Boundaries (**FREEZE**)

| Actor | Trust |
| ----- | ----- |
| **Driver** live GPS (`POST /v1/location/update`) | **Untrusted** — ADR-011 / N2A (accuracy, staleness, seq). **Unchanged.** |
| **Passenger** pickup/destination at request time | **Passenger-confirmed proposal** — server validates numeric ranges (`parseLatLng`); does **not** require N2A stream semantics for passengers in Phase 4/5 |
| **Durable ride pickup/destination** | Copied at create; used thereafter for N3/N4; treat as **immutable** for that ride requestVersion (no silent rewrite) |
| **Pricing coordinates** | Same confirmed lat/lng passed into estimate; server routes from those points |
| **N3 / N4** | **Only** `ride.pickup.lat/lng` (already frozen) |

### Server validation minimum for passenger points (**FREEZE**)

- Keep existing WGS84 checks.
- Phase 4/5 **may** add a coarse Pakistan bbox / service-area check later; **not** required to start 4A.
- Do **not** invent geofence matching that reintroduces city shards.

### Consistency with closed ADRs (**FREEZE**)

- Redis remains non-authoritative (ADR-004).
- Assignment remains Firestore (ADR-003 / closed ride SM).
- No change to N2C write path or N3 query contract.

---

## 8. Routing Architecture

### Decision (**FREEZE**)

- **Authoritative** distance + duration for pricing: **server-side** Google Routes API `computeRoutes`.
- Travel mode for MVP ride categories: **`DRIVE`** (two-wheeler/rickshaw categories may later request alternate modes — **deferred**).
- Prefer `routingPreference: TRAFFIC_AWARE` when billing/SKU allows; otherwise traffic-unaware fallback with explicit logging (**PROVIDER**: [Compute Routes](https://developers.google.com/maps/documentation/routes/compute_route_directions)).
- Request only needed fields via field mask (e.g. `routes.duration`, `routes.distanceMeters`, optional encoded polyline for later UI) to control cost (**PROVIDER**: Routes field mask / billing).
- Polyline storage on ride at create may remain `null` until a later Maps UI slice; estimate **may** return polyline for preview without requiring ride schema change.

### Client must not (**FREEZE**)

- Send self-computed haversine as fare input.
- Bypass estimate by stuffing `distanceKm` into create.

---

## 9. Provider Evaluation

### Candidates considered

| Provider | Role evaluated | Notes |
| -------- | -------------- | ----- |
| **Google Maps Platform** | Maps SDK, Places, Geocoding, Routes | Already assumed throughout Ora docs; Firebase/Android alignment |
| **Mapbox** | Geocoding, Directions, maps | Strong alternative; Directions traffic list includes **Pakistan** (**PROVIDER**: [Mapbox Directions traffic coverage](https://docs.mapbox.com/help/dive-deeper/directions/)) |
| **HERE / TomTom** | Routing/geocode | Viable industry options; **no** existing Ora doc/SDK commitment |
| **OSRM / self-host** | Routing only | Ops burden; weak geocoding/Places parity; **rejected for MVP** |

### Evaluation dimensions (summary)

| Dimension | Google | Mapbox | Self-host OSRM |
| --------- | ------ | ------ | -------------- |
| Pakistan routing / traffic | Broad Maps Platform availability; verify GCP project enablement | Traffic coverage list includes Pakistan (**PROVIDER**) | OSM quality varies |
| Geocoding / Places UX | Places Autocomplete + Details mature | Search/Geocoding APIs mature | Weak for product search UX |
| Flutter map SDK | `google_maps_flutter` (planned in tech stack **DOC**; not in pubspec **CODE**) | Mapbox Maps Flutter | Custom tiles |
| Backend HTTP | Routes `computeRoutes` REST (**PROVIDER**) | Directions API | Self-manage |
| Key security model | Android package+SHA; server IP/API restriction (**PROVIDER**: [API security best practices](https://developers.google.com/maps/api-security-best-practices)) | Token URL restrictions | N/A |
| Doc alignment with Ora | **Strong** (`maps-architecture.md`, `phase-04`, `phase-05`, fare-engine) | Would rewrite planning docs | Conflicts |
| Switching cost | Abstraction ports (below) | Same ports | Same ports |

### Pricing / quotas (**PROVIDER** — do not hardcode dollar amounts here)

- Google Routes: pay-as-you-go SKUs; QPM limits documented on [Routes usage and billing](https://developers.google.com/maps/documentation/routes/usage-and-billing). Exact SKU tiers depend on traffic/tolls features — implement with **minimal field mask**.
- Mapbox: usage-based Directions + Temporary/Permanent Geocoding ([Mapbox pricing](https://www.mapbox.com/pricing)); permanent storage of geocodes has separate rules — relevant if caching addresses server-side.

---

## 10. Provider Decision

### **FREEZE: Google Maps Platform** for Phase 4–5 production

**Reasons (ordered):**

1. **CODE/DOC continuity** — fare-engine, phase-04/05, maps-architecture, error-codes (`PRICING_UNAVAILABLE` ↔ Routes outage) already specify Google.
2. **Single vendor** for Places (client search) + Routes (server D/T) + optional Maps SDK display.
3. **Android key restriction model** well-documented for package `com.ora.ora` + SHA-1.
4. Mapbox remains the **documented replacement candidate** behind ports (Section 25).

**Not chosen now:** Mapbox (capable; would fork all planning), HERE/TomTom (no leverage), OSRM (ops).

**Project setup risk:** GCP billing + API enablement (Routes, Places, Geocoding, Maps SDK) must be completed before 4B/5B live proofs — **environment**, not architecture redesign.

---

## 11. Provider Abstraction

### Minimum viable ports (**FREEZE**)

Do **not** build a generic multi-cloud framework. Introduce thin server interfaces in auth-service (names illustrative):

```ts
interface RoutingProvider {
  computeDriveRoute(input: {
    origin: { lat: number; lng: number };
    destination: { lat: number; lng: number };
  }): Promise<{
    distanceKm: number;
    durationMin: number;
    encodedPolyline?: string;
    provider: 'google_routes';
    rawRequestId?: string;
  }>;
}

// Optional server-side helpers (reverse geocode for city suggestion / address fill)
interface GeocodingProvider {
  reverse(input: { lat: number; lng: number }): Promise<{
    formattedAddress?: string;
    locality?: string; // suggestion only — not matching key
  }>;
}
```

- **One** production implementation: `GoogleRoutingProvider` / `GoogleGeocodingProvider`.
- Pricing engine depends on **ports**, not on Google types.
- Flutter Places/GPS stay client-side; **no** requirement that Flutter share the server port types.

---

## 12. City Metadata Decision

### **FREEZE**

1. **Matching:** City is **not** a matching key (coordinate-primary). **Do not** reopen N3/N4.
2. **Create API:** Keep **`city` required** until a dedicated soft-deprecation slice (per `RIDE-CITY-SCHEMA.md`). Phase 4/5 **must not** silently drop the field.
3. **Flutter Phase 4/5:** Must send `city` on create. Allowed interim sources (in order of preference for honesty):
   - Explicit catalog selection when catalog UX ships.
   - **Suggested** locality from reverse geocode / Places address components, normalized with `normalizeCitySlug`, shown to the user for confirm.
   - Do **not** invent city from IP.
4. **PBS catalog import:** Remains licensing-gated; **not** a Phase 4/5 blocker for coordinate resolution or pricing.
5. **Estimate API:** May accept optional `city` for **pricingRules** lookup keying (`pricingRules/{city}_{category}` per fare-engine **DOC**). If rules are national MVP defaults, city may be unused by the calculator but still accepted.

---

## 13. Phase 5 Pricing Architecture

### Endpoint (**FREEZE**)

```http
POST /v1/pricing/estimate
Authorization: Bearer <Firebase ID token>
```

Name matches existing architecture docs and `/v1` convention. Register in `app.ts` when implementing; update `API_CONTRACT_INDEX` at implementation time.

### Request (**FREEZE** — minimal)

```json
{
  "pickup": { "lat": 31.52, "lng": 74.35, "address": "optional" },
  "destination": { "lat": 31.56, "lng": 74.31, "address": "optional" },
  "category": "easy",
  "city": "lahore",
  "serviceType": "ride"
}
```

- **Required:** pickup lat/lng, destination lat/lng, category.
- **`city`:** required while create requires city / while rules are city-keyed; revisit with soft-deprecation.
- **Forbidden:** client `distanceKm`, `durationMin`, `recommendedFareMinor`, `pricingSnapshotId`.

### Response (**FREEZE** — align create + `PricingSnapshotDoc`)

```json
{
  "data": {
    "pricingSnapshotId": "ps_…",
    "recommendedFareMinor": 34000,
    "offerBoundMinMinor": 23800,
    "offerBoundMaxMinor": 85000,
    "currency": "PKR",
    "pricingRulesVersion": "…",
    "computedAt": "ISO-8601",
    "expiresAt": "ISO-8601",
    "distanceKm": 5.8,
    "durationMin": 14,
    "category": "easy"
  },
  "requestId": "…",
  "timestamp": "…"
}
```

Optional later: `encodedPolyline` for map preview (non-authoritative display).

### Side effects (**FREEZE**)

- Writes immutable `pricingSnapshots/{pricingSnapshotId}` via Admin SDK.
- TTL / expiry: **10 minutes** from `computedAt` (fare-engine **DOC**; create already enforces `expiresAt`).

---

## 14. Pricing Engine Decision

### What exists today (**CODE**)

- Snapshot **loader** + bounds assert.
- **No** `pricingRules` reader, **no** fare formula implementation, **no** demand/night calculators in runtime code.
- Categories exist on Flutter as UI ids (`zip`, `trio`, `easy`, …); backend accepts opaque `category` string.

### Minimum production model for Phase 5 (**FREEZE**)

Implement **`docs/algorithms/fare-engine.md`** recommended-fare formula at MVP depth:

| Include in 5A/5B | Defer |
| ---------------- | ----- |
| Base `B`, `rKm`, `rMin`, `catMult`, `minFare`/`maxFare` clamps, round-to-Rs-10, persist paisas | Live Redis demandMult (use `1.0` MVP) |
| OfferBoundPolicy ratios → `offerBoundMinMinor` / `offerBoundMaxMinor` | Historical median |
| `pricingRulesVersion` stamp | Full admin UI |
| Tolls/airport | `0` until Routes toll SKU explicitly enabled |

**Bootstrap `pricingRules`:** seed via Admin/ops (not client). Missing rules → estimate fails closed (`PRICING_UNAVAILABLE` or `VALIDATION_ERROR` — pick one code in implementation freeze notes; prefer **`PRICING_UNAVAILABLE`** for provider/config outage, **`VALIDATION_ERROR`** for bad category).

**Do not** ship random/fixed PKR without rules version + snapshot.

---

## 15. Pricing Snapshot Contract

| Rule | **FREEZE** |
| ---- | ---------- |
| Who creates | Auth-service pricing estimate path only (Admin SDK) |
| When | On successful estimate after route + fare compute |
| What | Recommended fare, offer bounds, currency PKR, rules version, timestamps, inputs including distanceKm/durationMin/category |
| Validity | Until `expiresAt` (10 min) |
| Immutability | No updates; new estimate → new id |
| Client modify | **Forbidden** (rules deny; create re-loads server doc) |
| Create re-validate | Existing `loadPricingSnapshot` + bounds — **keep** |
| Route binding | Snapshot `inputs` bind D/T used for that recommendation |
| Fabrication | **Forbidden** — no debug hardcode IDs in Flutter |

---

## 16. Offered Fare Bounds

Aligned with ADR-007 + existing create (**FREEZE**):

| Field | Role |
| ----- | ---- |
| `recommendedFareMinor` | Guidance from snapshot |
| `offerBoundMinMinor` / `offerBoundMaxMinor` | Anti-abuse window (OfferBoundPolicy), **not** the product price |
| `passengerOfferMinor` | Passenger proposal on **create** (and UI); must lie in bounds |
| `agreedFareMinor` | Set at offer select — **unchanged** |

Rules:

- Integer **paisas** (`amountMinor`).
- Reject ≤ 0.
- Expired snapshot → re-estimate; passenger must confirm new offer.
- Changing category / either coordinate → **new** estimate (invalidate prior snapshot in UI).

---

## 17. Pricing Failure Semantics

| Condition | HTTP / code (target) | Client behavior |
| --------- | -------------------- | --------------- |
| Places/GPS fail (client) | N/A | Block estimate; location messaging |
| Routes failure / timeout | `503 PRICING_UNAVAILABLE` (**DOC** error-codes) | Retry; keep “Pricing isn’t available…” tone |
| No pricing rules | `503 PRICING_UNAVAILABLE` or `400 VALIDATION_ERROR` | Do not invent fare |
| Impossible / zero route | `422` domain error (define `ROUTE_UNAVAILABLE` at impl if needed) | “Unable to determine a route…” |
| Expired snapshot on create | `422 PRICING_SNAPSHOT_EXPIRED` (**CODE**) | Re-estimate |
| Out of bounds offer | `422 FARE_OUT_OF_BOUNDS` (**CODE**) | Adjust offer |
| Unsupported area (future) | Explicit error | Different destination |

Do not collapse all failures into silent success.

---

## 18. Security / API Key Model

### **FREEZE**

| Key | Location | Restriction |
| --- | -------- | ----------- |
| Maps SDK (Android/iOS) | Mobile (restricted) | Package + SHA; Maps SDK only (**PROVIDER**) |
| Places (mobile) | Mobile (restricted) | Package + SHA; Places only; **session tokens** |
| Routes / Geocoding (server) | Secret Manager / env (`GOOGLE_MAPS_SERVER_KEY` or equivalent) | **Never** in Flutter; API + IP/service restrict |
| Firebase Auth | Existing | Unchanged |
| Pricing snapshot write | Admin SDK only | Client rules deny |

Abuse controls: reuse existing auth rate limiter patterns; add estimate-specific rate limit (docs mention ~10/min/user — implement when wiring).

App Check: **not** a hard dependency to start Phase 4/5 (matches current local device posture) but remains recommended for production abuse.

---

## 19. Cost / Rate-Limit Controls

### Smallest safe approach (**FREEZE**)

| Control | MVP |
| ------- | --- |
| Flutter debounce | Autocomplete input debounce; cancel in-flight Places |
| Estimate trigger | Only after **both** points confirmed + category selected; explicit “Get fare” or auto-once — **not** on every keystroke |
| Server | Field-mask Routes; no Matrix fan-out in Phase 5 |
| Caching | Optional short TTL cache keyed by rounded lat/lng + category (**defer** if complex); do not cache forever (traffic) |
| Dedup | Idempotent UX: ignore duplicate taps while in-flight |
| Rate limit | Per-uid estimate cap |

---

## 20. Dependency Graph

```text
[Closed] Auth / Ride SM / M0 / N3 / N4 / D1(arch)
                │
                ▼
        ┌───────────────┐
        │ Phase 4A      │  Passenger resolve lat/lng (+ address)
        └───────┬───────┘
                │
                ▼
        ┌───────────────┐
        │ Phase 5A      │  pricingRules bootstrap + fare calculator (unit-testable)
        └───────┬───────┘
                │
                ▼
        ┌───────────────┐
        │ Phase 4B+5B   │  Google RoutingProvider + POST /v1/pricing/estimate
        └───────┬───────┘
                │
                ▼
        ┌───────────────┐
        │ Phase 5C      │  Flutter estimate + offer UI + city on create + capabilities
        └───────┬───────┘
                │
                ▼
        Real-device: estimate → create → SEARCHING → M0/N3/N4 consumers
```

**Note:** 4B is intentionally coupled to 5B (routing exists to serve pricing). Do not ship client-only haversine “pricing.”

---

## 21. Implementation Slices

| ID | Name | Deliverable | Explicit non-goals |
| -- | ---- | ----------- | ------------------ |
| **4A** | Passenger location resolution | GPS + Places (+ optional map pin); `ResolvedPassengerLocation`; confirmation; wire into capabilities coords | Estimate API; N2B; BGGeo |
| **5A** | Fare calculator + rules | Pure function + Firestore `pricingRules` read; version stamp; OfferBoundPolicy | Live demand Redis |
| **4B/5B** | Estimate API | `RoutingProvider` + `POST /v1/pricing/estimate` + snapshot write | Change create SM; N3/N4 |
| **5C** | Flutter pricing integration | Call estimate; show recommended + bounds; set `passengerOfferMinor`; pass `pricingSnapshotId` + `city`; unlock create when coords+snapshot present | Payments; dispatch UI redesign |
| **E2E** | Device proof | Physical Android path §22 | Offers/dispatch deep dive beyond create visibility |

---

## 22. Real-Device Acceptance Criteria

Must eventually prove on physical device (implementation phases — **not** this freeze):

1. Clean install / known session  
2. Login + onboarding (already CLOSED — do not regress)  
3. Home  
4. Request ride  
5. Pickup resolves to confirmed lat/lng  
6. Destination resolves to confirmed lat/lng  
7. Estimate returns `pricingSnapshotId` + fares (backend log + Flutter)  
8. Passenger sets offer within bounds  
9. `POST /v1/rides` → `SEARCHING` with durable pickup/destination  
10. Passenger sees active request  
11. M0 open list can see ride (driver)  
12. N3 query using that pickup lat/lng returns candidates when drivers online  
13. N4 can tick against those coordinates  

**Pass evidence:** HTTP status, rideId, Firestore ride doc fields (`pricingSnapshotId`, `requestVersion`, pickup/destination, `city`), no duplicate create for same idempotency key.

---

## 23. Non-Goals

- Payments / wallet / ledger / commission / tax  
- Turn-by-turn / driver navigation  
- Full background GPS tracking / BGGeo  
- N2B RTDB tripLocations  
- WebSockets / invite-poll API redesign  
- Auto-assignment / changing offer select  
- Redesign N3, N4, D1, Redis GEO schema  
- City-based matching / PBS import unblocking  
- Fabricated snapshots or fixed fake fares  
- Unrelated Flutter visual redesign  
- Soft-deprecating `city` in the same slice as estimate (separate API freeze)

---

## 24. Risks / Deferred Items

| Risk | Mitigation |
| ---- | ---------- |
| Google Places quality for Pakistani informal addresses | Confirm pin on map; allow map adjust |
| Routes SKU cost / traffic | Minimal field mask; start without tolls |
| Flutter still missing `city` | 5C must send city; otherwise create 400 |
| Dual gate (pricing then location) | 4A before 5C; both required for create |
| Temporary fixture temptation | **Forbidden** for passenger builds |
| Phase 4 planning doc overscope | Follow 4A/4B only |
| Master plan stale frontier text | Prefer CURRENT_STATE + this freeze |

---

## 25. Rollback / Provider Replacement Strategy

1. Keep `RoutingProvider` / `GeocodingProvider` ports.  
2. Swap Google → Mapbox (or other) by new adapter + secrets.  
3. Snapshot schema and fare calculator **unchanged**.  
4. Flutter Places may need parallel swap (Places SDK vs Mapbox Search) — isolate behind a client `PlaceSearchPort`.  
5. Feature-flag estimate provider name in logs for incident response.

---

## 26. Explicit Architecture Freeze

**Locked as of 2026-09-22:**

1. Unblock path is **Phase 4 location resolution + Phase 5 server estimate**, not client hacks.  
2. **Google Maps Platform** is the production provider for 4–5.  
3. **`POST /v1/pricing/estimate`** is the estimate contract name.  
4. Snapshots are **server-authored**, **10-minute**, **immutable**, **PKR minor units**, bounds via OfferBoundPolicy.  
5. Distance/time for fare are **server Routes**-derived.  
6. N3/N4 continue to use **durable pickup lat/lng**; city remains **metadata**.  
7. **Next slice to implement:** **Phase 4A** (coords). Do **not** start coding in this docs-only task.  
8. **Do not** fabricate `pricingSnapshotId`, fixed fares, or silent GPS fakes.

---

## Appendix A — Q&A crosswalk (investigation)

| Question | Answer |
| -------- | ------ |
| Backend pricing API exists? | **No** estimate route; snapshot **load** only |
| Flutter calls pricing? | **No** |
| Expected endpoint | `POST /v1/pricing/estimate` |
| Why “Pricing unavailable”? | Empty `RideRequestCapabilities` local gate |
| Snapshot required on create? | **Yes** |
| Authoritative pricing source | Server `pricingSnapshots` from estimate |
| PBS deferred? | City catalog licensing — **orthogonal** to fare engine |
| New architectural slice? | **Yes** — this freeze |

## Appendix B — Citations (provider)

- Google Routes `computeRoutes`: https://developers.google.com/maps/documentation/routes/compute_route_directions  
- Google Routes billing: https://developers.google.com/maps/documentation/routes/usage-and-billing  
- Google API key security: https://developers.google.com/maps/api-security-best-practices  
- Mapbox Directions traffic coverage (includes Pakistan): https://docs.mapbox.com/help/dive-deeper/directions/  
- Mapbox pricing: https://www.mapbox.com/pricing  
