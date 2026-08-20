# Phase 10 — Trip (Live Navigation & Completion)

**Status:** NOT STARTED  
**Dependencies:** Phase 9

## Objectives

Full live trip experience: driver en route, arrived, ride started, navigation, completion, receipt, rating.

## Key Implementation Points

- Passenger: live map with driver marker (RTDB GPS); ETA countdown; driver info card
- Driver: navigate to pickup (Google Maps deeplink or in-app)
- Arrival: server geofence or driver tap; proximity validation (< 100m)
- Ride start: driver tap; server validates proximity
- Active trip: driver GPS at 1s/5m interval; RTDB stream; passenger map updates
- Route deviation detection (server, every 60s)
- End ride: driver tap at destination; server validates proximity (< 200m)
- Receipt: breakdown shown to both; rating screens
- Driver marker heading animation (smooth rotation)
- Safety SOS accessible during trip
- Verify driver: plate + photo check screen

## Acceptance Criteria

- [ ] Driver marker moves smoothly on passenger map (never backward)
- [ ] ETA countdown updates every 30 seconds
- [ ] All ride state transitions: EN_ROUTE → ARRIVED → STARTED → RIDE_COMPLETED → RIDE_CLOSED
- [ ] Proximity validation enforced (not just client tap)
- [ ] Receipt breakdown matches pricingSnapshot inputs
- [ ] Rating: both parties can rate after completion
- [ ] Route deviation > 300m logged; > 1km → passenger alert
- [ ] E2E test on two physical devices (full happy path)
- [ ] Integration test: driver at wrong location tries to end ride → 422 PROXIMITY_VIOLATION
