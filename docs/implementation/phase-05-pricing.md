# Phase 5 — Pricing Engine

**Status:** **5A IMPLEMENTED**; **4B/5B IMPLEMENTED / VERIFIED** (Google Routes + `POST /v1/pricing/estimate`); **5C NOT STARTED**  
**Dependencies:** Phase **4A** coordinates; **5A** calculator/rules  
**Decision freeze (authoritative):** [`phase-4-5-location-pricing-decision.md`](phase-4-5-location-pricing-decision.md)

> **2026-09-22:** Slice order: **5A** → **4B/5B** estimate → **5C** Flutter.  
> **5A (done):** pure `calculateFare` + `PricingRulesRepository`.  
> **4B/5B (done):** `GoogleRoutesProvider` + `POST /v1/pricing/estimate` writes immutable `pricingSnapshots` (10 min TTL). Client must never fabricate snapshot IDs.  
> Proofs: `npm run test:phase-5b-unit-proof`, `npm run test:phase-5b-live-proof` (requires `GOOGLE_MAPS_SERVER_KEY`).

## Objectives

Server-side fare calculation, pricing snapshot, passenger fare offer confirmation.

## Key Implementation Points

- Pricing Service deployed as Cloud Run service
- `POST /v1/pricing/estimate` calls Google Routes API for distance + duration
- Fare formula implemented exactly as per `docs/algorithms/fare-engine.md`
- `pricingRules` loaded from Firestore (cached 1 hour in Redis)
- Demand multiplier computed from Redis zone counters
- Historical median computed from last 30 completed rides (same zone/category)
- Response includes `recommendedFareMinor`, optional bound hints, `pricingSnapshotId`
- Bounds come from `OfferBoundPolicy` if configured — they are not the fare model
- On ride create: server re-validates snapshot and passenger offer
- Snapshot stored in Firestore `pricingSnapshots` (immutable)
- Client cannot modify snapshot; only references it by ID
- Snapshot expires 10 minutes after creation
- On ride create: server re-validates snapshotId not expired and fare within bounds

## Acceptance Criteria

### 5A (calculator + rules) — VERIFIED

- [x] Fare formula unit tests (distance/time, category mult, min/max, Rs-10 round, paisas, OfferBoundPolicy, version, fail-closed)
- [x] Fare rounded to nearest Rs 10 (then clamp)
- [x] Demand multiplier MVP = 1.0; formula clamp [1.0, 1.8] preserved
- [x] Pricing rules version stamped on every calculation
- [x] Missing/inactive/malformed rules → fail closed (`PRICING_UNAVAILABLE`)
- [x] Client cannot write/read `pricingRules` (existing Firestore deny rules unchanged)

### 5B (estimate + Routes + snapshot) — VERIFIED

- [x] `POST /v1/pricing/estimate` (auth + validation + Google Routes + 5A fare + snapshot write)
- [x] Snapshot immutable write; 10 min `expiresAt`
- [x] Missing rules / Routes failure fail closed
- [x] Live Google Routes proof (`test:phase-5b-live-proof`)
- [x] Client cannot write/read `pricingSnapshots` (Firestore deny unchanged)

### 5C (Flutter) — NOT STARTED

- [ ] Flutter estimate + offer UI + city on create + capabilities
- [ ] Night adjustment applies exactly 23:00–05:00
- [ ] Live Redis demand / historical median
