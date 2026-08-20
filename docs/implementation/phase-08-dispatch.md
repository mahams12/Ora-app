# Phase 8 — Dispatch Engine

**Status:** NOT STARTED  
**Dependencies:** Phase 6, Phase 7

## Objectives

Server-side matching engine: candidate generation, filtering, ranking, notification to drivers.

## Key Implementation Points

- Matching runs in Ride Engine Cloud Run (triggered on ride create)
- Redis GEORADIUS for candidate generation
- All 8 filters applied (online, approved, category, active ride, freshness, accuracy, service area, preferences)
- Composite ranking score computed per candidate
- Google Distance Matrix API for ETA (top 10 candidates)
- RTDB write for each notified driver (`rideRequests/{driverId}/pending/{rideId}`)
- FCM data message to each notified driver
- `dispatch:notified:{rideId}` Redis list stored for cleanup
- Driver app: incoming request card with countdown timer
- Driver: Accept / Counter / Decline creates offer or miss — **does not assign**
- Offer inbox on passenger after first pending offer

## Acceptance Criteria

- [ ] Eligible drivers receive request within 900ms of ride creation (P95)
- [ ] Non-eligible drivers do NOT receive request
- [ ] Ranking: driver closest with best rating appears first
- [ ] Maximum 30 drivers notified per request
- [ ] Request card disappears after 15 seconds (timeout)
- [ ] Request card shows correct fare, pickup, destination, passenger rating
- [ ] Driver can Accept, Counter, or Decline
- [ ] Accept creates PENDING offer; ride is not DRIVER_ASSIGNED
- [ ] Integration test: 3 drivers receive request simultaneously
- [ ] Integration test: non-eligible driver (wrong category) does not receive
- [ ] Integration test: stale driver (>15s no GPS) not included in candidates
