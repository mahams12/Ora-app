# Phase 5 — Pricing Engine

**Status:** NOT STARTED  
**Dependencies:** Phase 4

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

- [ ] `POST /pricing/estimate` returns in < 400ms P95
- [ ] Fare formula unit tests: all categories, night adjustment, demand multiplier, min/max
- [ ] Fare rounded to nearest Rs 10
- [ ] `pricingSnapshot` written to Firestore on ride create
- [ ] Snapshot is immutable (Firestore rules + Admin SDK only)
- [ ] Expired snapshot → 422 `PRICING_SNAPSHOT_EXPIRED`
- [ ] Out-of-bounds fare offer → 422 `FARE_OUT_OF_BOUNDS`
- [ ] Demand multiplier clamped to [1.0, 1.8]
- [ ] Night adjustment applies exactly 23:00–05:00
- [ ] Pricing rules version stamped on every snapshot
