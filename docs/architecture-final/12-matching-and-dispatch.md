# Matching & Dispatch Architecture (Redis GEO + Deterministic Waves)

Authoritative sources:
- `docs/algorithms/matching-engine.md`
- `docs/architecture-review/dispatch-wave-design.md`
- `docs/architecture/realtime-architecture.md`
- `docs/database/realtime-schema.md`

## Candidate Generation

- Redis GEO index: `geo:drivers:{city}`
- Query: `GEORADIUS ... 10km ASC WITHCOORD WITHDIST COUNT 100` (initial)
- If insufficient eligible drivers, expand per configured waves.

## Filtering (eligibility gates)

Server applies (in order):
1. Driver online (RTDB driverPresence + Redis backup)
2. Driver approved (Firestore drivers.driverStatus == approved)
3. Vehicle approved for category
4. No active ride (activeRideId == null + ride state check if needed)
5. Location fresh (`lastLocationTs > now-15s`)
6. Location accurate (`<50m`)
7. In service area polygon
8. Driver preferences / blocks (server-side)

## Ranking

Deterministic scoring using:
- ETA normalized
- rating normalized
- distance normalized
- cancellation/no-show reliability metrics
- completed rides bonus

Ranking score defined in `docs/algorithms/matching-engine.md`.

## Dispatch in Waves

Wave dispatch contract (deterministic; assignment is not accept):
- Wave 1: top 5 drivers, wait 4–6s
- Wave 2: next 10 drivers only if still unresolved
- Wave 3: next 15 drivers only if still unresolved

Operational rule:
- Later waves stop immediately when assignment occurs or ride cancels/expires.

## Delivery Mechanism

For each driver in the active wave:
- write dispatch card: `RTDB rideRequests/{driverId}/pending/{rideId}`
- send FCM wake-up as fallback data message
- record dispatched IDs: `Redis dispatch:notified:{rideId}`

## Expiration & Cleanup

- ride request cards expire with `expiresAt` and are cleaned by server TTL sweeps
- RTDB pending cards are deleted by assignment projector for losing drivers

