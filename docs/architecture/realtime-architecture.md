# ORA — Realtime Architecture

## Overview

Two realtime channels serve different purposes:

| Channel | Technology | Use Case | Write Authority |
|---|---|---|---|
| State channel | Firestore listeners | Ride state, driver info, booking updates | Server (Admin SDK) only |
| Signal channel | RTDB listeners | Assignment invalidation, presence, GPS projections | Server (Admin SDK) for ride-scoped data; driver for own presence only |
| Push fallback | FCM | When app is in background or listener not connected | Server via FCM Admin SDK |

## Ride Request Delivery to Drivers

```
1. POST /rides created → Ride Engine queries Redis GEO
2. Dispatch Wave 1 candidate set identified
3. For each candidate in the active wave:
   a. Write to RTDB: rideRequests/{driverId}/pending/{rideId} = {rideDetails}
   b. Send FCM data message: { type: "NEW_RIDE_REQUEST", rideId }
4. Driver app:
   a. RTDB listener fires (< 200ms typical)
   b. OR FCM message arrives (background fallback)
   c. Displays ride request card with 15-second countdown
```

## Assignment Invalidation — Exact Flow

Assignment happens when the **passenger selects an offer**, not when a driver accepts.

```
Time  │ Event
──────┼──────────────────────────────────────────────────────────
T0    │ Ride #123 in SEARCHING
      │ Drivers A, B, C all have pending request in RTDB
T1    │ Driver A taps Accept → POST /v1/rides/123/offers
T2    │ Server writes rideOffers/offerA status=PENDING
      │ Ride may become OFFERS_AVAILABLE
      │ Driver A waits; NOT assigned
T3    │ Drivers B and C also create pending offers (accept or counter)
T4    │ Passenger selects offerB: POST /v1/rides/123/offers/offerB/select
T5    │ Optional Redis SETNX lock:ride:123 passengerId NX EX 30 (select contention only)
T6    │ Firestore.runTransaction():
      │   assert passenger owns ride
      │   assert state in {SEARCHING, OFFERS_AVAILABLE}
      │   assert assignedDriverId == null
      │   assert offerB PENDING, not expired, requestVersion match, driver eligible
      │   write: DRIVER_ASSIGNED, assignedDriverId=B, agreedFareMinor=offerB.amountMinor
      │   offerB SELECTED; sibling offers SUPERSEDED
      │   outbox ride.assigned + ride.offer.selected
T7    │ Firestore commit → assignment is authoritative; agreedFare immutable
T8    │ Projector:
      │   rideSignals/123 = { DRIVER_ASSIGNED, driverId: B, aggregateVersion, eventSequence }
      │   delete pending cards for A and C; replace B's card with assigned trip UI
T9    │ Passenger Firestore listener: driver info shown
T10   │ Driver B: navigate to pickup
T11   │ Late Accept from D after T7 → 409 ALREADY_ASSIGNED (creates no offer)
      │ Select of expired offer → 422 OFFER_EXPIRED; no assignment
```

Pending RTDB request cards remain until: driver declined, card TTL, offer withdrawn, ride expired/cancelled, or assignment.

## Sequence Numbers & Staleness

Every RTDB ride signal carries:
```json
{
  "state": "DRIVER_ASSIGNED",
  "aggregateVersion": 6,
  "eventSequence": 991,
  "ts": 1724035800000
}
```

Client rules:
- If `aggregateVersion < localRideVersion` → discard
- If `aggregateVersion == localRideVersion` and `eventSequence <= lastAppliedEventSequence` → discard
- If `ts < (now - 8000ms)` → discard (stale packet)
- Otherwise → apply

## Reconnect Handling

### Driver reconnects during SEARCHING
1. RTDB `.onDisconnect()` handler fires: marks driver offline in presence
2. Driver eligible pool: removed from Redis GEO index on next server sweep (30s TTL)
3. On reconnect: driver app re-registers presence; re-added to GEO index
4. If ride still SEARCHING and driver still eligible: new request card delivered

### Passenger reconnects during DRIVER_EN_ROUTE
1. App reads Firestore ride document (single snapshot — no listener gap)
2. Firestore returns current state (version N)
3. RTDB listener reattaches; gets latest driver location
4. UI renders correctly from snapshot; no race condition

### Both offline
1. Ride state held in Firestore (durable)
2. Server TTL sweeper handles expiry per state rules
3. Both read correct state on reconnect from Firestore

## RTDB Schema

```
root/
├── driverPresence/
│   └── {driverId}/
│       ├── online: boolean
│       ├── lastSeen: timestamp
│       ├── city: string
│       └── connectedAt: timestamp
│
├── rideAccess/
│   └── {rideId}/
│       └── {uid}: true
│
├── tripLocations/
│   └── {rideId}/
│       ├── latest/
│       │   ├── lat: number
│       │   ├── lng: number
│       │   ├── accuracy: number
│       │   ├── heading: number
│       │   ├── speed: number
│       │   ├── locationSeq: number
│       │   ├── locationStreamId: string
│       │   └── ts: timestamp
│       └── recent/
│           └── {eventSequence}/...
│
├── rideSignals/
│   └── {rideId}/
│       ├── state: string
│       ├── driverId: string | null
│       ├── aggregateVersion: number
│       ├── eventSequence: number
│       └── ts: timestamp
│
└── rideRequests/
    └── {driverId}/
        └── pending/
            └── {rideId}/
                ├── pickup: { lat, lng, address }
                ├── destination: { lat, lng, address }
                ├── passengerOfferMinor: number
                ├── recommendedFareMinor: number
                ├── requestVersion: number
                ├── category: string
                ├── passengerRating: number
                └── expiresAt: timestamp
```

## FCM Message Structure

```json
// Data-only message (works in foreground + background)
{
  "data": {
    "type": "RIDE_ASSIGNED",
    "rideId": "abc123",
    "driverId": "drv456",
    "seq": "6",
    "ts": "1724035800000"
  },
  "android": {
    "priority": "high"
  },
  "apns": {
    "headers": { "apns-priority": "10" }
  }
}
```

App handles FCM message:
- Foreground: RTDB listener already active; FCM is secondary confirmation
- Background: FCM wakes app; app reads Firestore for authoritative state
- Killed: FCM system notification shown; on tap → app opens and reads Firestore
