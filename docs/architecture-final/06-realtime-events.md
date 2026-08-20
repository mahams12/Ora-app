# Realtime Event & Projection Contracts

Authoritative sources:
- `docs/architecture/realtime-architecture.md`
- `docs/architecture-review/event-contracts.md`
- `docs/architecture-review/outbox-design.md`
- `docs/architecture-review/consistency-model.md`
- `docs/algorithms/stale-event-handling.md`

## Channels & Write Authority

- **Firestore listeners**: authoritative ride state projection (server/Admin only writes)
- **RTDB rideSignals**: server projection of assignment/ride state (server only writes)
- **RTDB tripLocations**: server projection of validated driver GPS (server only writes)
- **RTDB rideRequests**: server writes per-driver pending cards
- **FCM**: best-effort fallback notifications (server via outbox)
- **Pub/Sub**: async durable events for notification/analytics/background jobs

## Durable Event Types (Outbox → Pub/Sub/Projectors)

From `docs/architecture-review/event-contracts.md`:

Ride aggregate:
- `ride.created`
- `ride.searching.started`
- `ride.offer.created`
- `ride.offer.received`
- `ride.offer.withdrawn`
- `ride.offer.expired`
- `ride.offer.selected`
- `ride.assigned`
- `ride.driver.en_route`
- `ride.driver.arrived`
- `ride.started`
- `ride.completed`
- `ride.cancelled`
- `ride.expired`
- `ride.no_show`

Payment aggregate:
- `payment.intent.created`
- `payment.attempt.started`
- `payment.authorized`
- `payment.captured`
- `payment.cash.collected`
- `payment.failed`
- `payment.refunded`
- `payment.callback.received`

Safety aggregate:
- `safety.sos.triggered`
- `safety.route_deviation.detected`
- `safety.driver_mismatch.reported`

Envelope requirements (for all durable events):
- `eventId` stable
- `aggregateVersion` monotonic
- `schemaVersion` with compatibility rules defined in `docs/architecture-final/24-phase-1.6-condition-closure.md` section 9

## RTDB Projection Contracts (Best-Effort)

1. **Ride assignment & invalidation**
   - On `ride.assigned`, projector:
     - writes `rideSignals/{rideId}` with `{state, driverId, aggregateVersion, eventSequence, ts}`
     - deletes remaining `rideRequests/{otherDriverId}/pending/{rideId}` cards
     - deletes winner pending card and replaces UI state via client reconciliation

2. **Dispatching ride request cards**
   - On `ride.created` and while ride is `SEARCHING`/`OFFERS_AVAILABLE`, projector:
     - writes per-driver pending request cards to `rideRequests/{driverId}/pending/{rideId}`
     - may emit FCM data message `NEW_RIDE_REQUEST` per driver

3. **Live location**
   - From validated GPS writes:
     - projector updates `tripLocations/{rideId}/latest` (and bounded `recent`)

## FCM Message Contracts (Best-Effort)

FCM data payloads example from `docs/architecture/realtime-architecture.md`:
```
{
  "data": {
    "type": "RIDE_ASSIGNED",
    "rideId": "...",
    "driverId": "...",
    "seq": "6",
    "ts": "..."
  }
}
```

Client behaviour:
- FCM is a wake-up; it must **not** override Firestore state.
- On FCM open/background wake, client must re-read authoritative Firestore ride state.

## Ordering, Deduplication, Retry, Dead-Letter

- Consumers must dedupe by `eventId`.
- Stateful projections must also reject stale events by `aggregateVersion` and `eventSequence`.
- Retry uses the frozen outbox delivery rules in `docs/architecture-final/24-phase-1.6-condition-closure.md` section 3.
- Dead letters must include envelope + failure details and require ops investigation.

## Phase 1.6 Freeze

Per-subscriber delivery tracking, lease semantics, retry ceilings, dead-letter thresholds, and replay rules are now frozen in:
`docs/architecture-final/24-phase-1.6-condition-closure.md` section 3.

