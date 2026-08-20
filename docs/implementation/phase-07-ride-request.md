# Phase 7 — Ride Request (Passenger Booking Flow)

**Status:** NOT STARTED  
**Dependencies:** Phase 4, Phase 5

## Objectives

Complete passenger booking flow: destination → vehicle selection → fare offer → request creation → searching state.

## Key Implementation Points

- Destination screen: autocomplete + saved places + recents
- Vehicle selection: list of categories with ETAs and recommended fares
- Fare confirmation: passenger enters **offer price**; recommended fare is guidance
- Server may enforce configurable OfferBoundPolicy (anti-abuse, not the pricing model)
- Searching view + offer inbox (no Direct Mode / auto-assign)
- `POST /v1/rides` with idempotency key
- Searching screen: radar animation; countdown; cancel option
- Cancel during searching: `POST /v1/rides/{id}/cancel`
- Expiry handling: server sends signal; passenger shown "No drivers found"
- All 4 service types: City Rides, Intercity, Courier, Move (stubbed in Phase 7; full in later phases)

## Acceptance Criteria

- [ ] Destination autocomplete shows results in < 300ms
- [ ] Saved places load correctly (from cache)
- [ ] Vehicle selection shows correct categories and recommended fares
- [ ] Fare offer input enforces [allowedMin, allowedMax] bounds
- [ ] `POST /rides` completes in < 500ms
- [ ] Ride document appears in Firestore with correct state = SEARCHING
- [ ] Searching screen animates correctly
- [ ] Cancel works and transitions to CANCELLED
- [ ] Expiry: after 5 minutes → EXPIRED state shown to passenger
- [ ] Idempotency: duplicate POST returns same rideId
- [ ] Integration test: complete booking flow
- [ ] Integration test: expired ride handling
