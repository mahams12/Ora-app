# Location & Map Architecture (Contract)

Authoritative sources:
- `docs/architecture/location-architecture.md`
- `docs/architecture/location-architecture.md` (trust and validation)
- `docs/architecture-review/location-trust-model.md`
- `docs/database/realtime-schema.md`
- `docs/database/firestore-schema.md` (ride geo and TTL)
- `docs/algorithms/stale-event-handling.md`

## GPS Acquisition

Sampling frequency (per mode):
- Idle/online driver: `5s`, distance filter `20m`, accuracy BALANCED
- Searching: `5s`, distance filter `10m`, accuracy BALANCED
- En route to pickup: `2s`, distance filter `5m`, accuracy HIGH
- Active trip: `1s`, distance filter `5m`, accuracy BEST
- Passenger: not streamed; rendered from RTDB trip projections

## Client Upload Payload (contract fields)
- `rideId`
- `driverId`
- `locationSeq` (monotonic per ride-stream)
- `locationStreamId` (scoping for restart/sequence reset negotiation)
- `lat`, `lng`
- `accuracy`, `heading`, `speed`
- `timestamp`
- `provider`

## Server Validation (authoritative)
Client GPS is **untrusted input**; server validates:
- JWT/App Check auth for driver
- `locationSeq` strictly greater than last accepted for the same ride-stream scope
- timestamp freshness within `now - 15s .. now + 5s`
- horizontal accuracy constraints (reject > 50m; may upload with `lowAccuracy=true` for UX warning modes)
- speed plausibility (reject > 200 km/h)
- plausibility based on distance/time vs previous point
- geofence: arrival/completion requires pickup/destination authorization zones

On valid input:
- Redis GEOADD update for dispatch/matching support
- RTDB write to `tripLocations/{rideId}/latest` and bounded `recent`

On invalid input:
- return 422 (`INVALID_LOCATION`, `STALE_LOCATION`, `SEQUENCE_VIOLATION`)
- do not update Redis GEO with bad data

## Stale/Out-of-Order Handling
- Passenger/client must discard out-of-order location updates using `locationSeq` monotonic rules.
- Marker on passenger map never moves backward (independent ordering domain from ride `aggregateVersion`).
- GPS freezes: server classifies stale if no accepted update for `> 15s` and flags presence/health; active trip triggers passenger warnings.

## Reconnect / Offline Behavior
- Driver reconnect mid-trip:
  1. fetch current active ride state from Firestore
  2. request resume cursor/stream negotiation state
  3. resume location upload with correct (or negotiated) `locationStreamId`
- If network disappears during upload:
  - server accepts no new GPS; client keeps last known marker
  - stale detection via scheduler marks stale and can warn passenger

## Impossible GPS Jumps
- Server rejects teleportation based on speed plausibility and distance/time plausibility.
- repeated violations can generate safety events or deviation logs (Phase 14+).

## GPS/Network Failure Outcomes (explicit)
- GPS inaccurate: upload may be flagged low accuracy; avoid hard-fraud enforcement solely from smoothing.
- GPS unavailable/permission denied: UI warning; server does not accept updates; state progression still requires server validations (arrival/completion).
- Ride route deviation:
  - detected via server-side route vs trajectory checks
  - sends notification/safety events according to safety flow

## Maps / Rendering Constraints
- Out-of-order discard: guaranteed via `locationSeq` monotonic checks.
- Latest-only rendering: passenger primarily reads `tripLocations/{rideId}/latest` to avoid expensive reads.

## Phase 1.6 Freeze

The `locationStreamId` lifecycle, active-stream acceptance rule, stream replacement on app restart, and stale old-stream rejection semantics are now frozen in:
`docs/architecture-final/24-phase-1.6-condition-closure.md` section 6.

