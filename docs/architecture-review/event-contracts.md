# ORA — Event Contracts

## Durable Event Envelope

Every important event should use this envelope:

```json
{
  "eventId": "evt_01J...",
  "eventType": "ride.assigned",
  "aggregateType": "ride",
  "aggregateId": "ride_abc123",
  "aggregateVersion": 6,
  "schemaVersion": 1,
  "occurredAt": "2026-08-18T07:30:00Z",
  "producer": "ride-engine",
  "correlationId": "req_abc123",
  "causationId": "cmd_select_offer_01J...",
  "status": "PENDING",
  "attemptCount": 0,
  "nextAttemptAt": "2026-08-18T07:30:00Z",
  "payload": {}
}
```

## Required Durable Event Types

### Ride aggregate
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
- `ride.closed`
- `ride.cancelled`
- `ride.expired`
- `ride.no_show`
- `ride.rating.submitted`

There is no durable `ride.driver.selected` public state. Selection is `ride.offer.selected` + `ride.assigned`.

### Payment aggregate
- `payment.intent.created`
- `payment.attempt.started`
- `payment.authorized`
- `payment.captured`
- `payment.cash.collected`
- `payment.failed`
- `payment.refunded`
- `payment.callback.received`
- `payout.requested`
- `payout.completed`

### Safety aggregate
- `safety.sos.triggered`
- `safety.route_deviation.detected`
- `safety.driver_mismatch.reported`

## Delivery Model

| Channel | Delivery | Consumer Requirement |
|---|---|---|
| Outbox | durable | publisher must mark delivered or retry |
| Pub/Sub | at-least-once | idempotent consumers required |
| RTDB | best-effort projection | clients must read-repair from Firestore |
| FCM | best-effort notification | clients must not rely on exactly-once |

## Consumer Idempotency

Consumers must dedupe by `eventId`.  
Stateful projection consumers must also reject older `aggregateVersion`.

## Dead-Letter Requirement

If a publisher or consumer repeatedly fails:
- increment attempt counter
- back off exponentially
- move to dead-letter store after threshold
- alert ops

Dead-letter record needs:
- original event envelope
- failure reason
- failed consumer
- attempts
- firstFailedAt
- lastFailedAt
