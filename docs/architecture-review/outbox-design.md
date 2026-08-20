# ORA — Outbox Design

## Why It Is Required

Firestore transaction success is not atomic with:
- RTDB cleanup
- Pub/Sub publish
- FCM delivery
- analytics side effects

Without an outbox, authoritative state can change while downstream consumers never learn about it.

## Proposed Durable Flow

```text
Command arrives
  ↓
Firestore transaction:
  - update aggregate
  - append durable outbox record
  ↓
transaction commits
  ↓
Outbox publisher polls unpublished records
  ↓
Publish to Pub/Sub
  ↓
Projection/notification workers:
  - RTDB cleanup / signals
  - FCM sends
  - analytics sinks
  ↓
Mark outbox record delivered per subscriber
```

## Outbox Schema

Collection: `outboxEvents`

```json
{
  "eventId": "evt_01J...",
  "aggregateType": "ride",
  "aggregateId": "ride_abc123",
  "aggregateVersion": 6,
  "eventType": "ride.assigned",
  "schemaVersion": 1,
  "occurredAt": "2026-08-18T07:30:00Z",
  "correlationId": "req_abc123",
  "causationId": "cmd_accept_01J...",
  "payload": {},
  "publishState": "PENDING",
  "attemptCount": 0,
  "nextAttemptAt": "2026-08-18T07:30:00Z",
  "lastError": null
}
```

## Retry Policy

- initial retry: immediate or sub-second
- exponential backoff with jitter
- hard ceiling
- move to dead-letter after threshold

## Subscriber Delivery Tracking

If one event feeds multiple consumers, record delivery state per consumer:
- `pubsub_published`
- `rtdb_projection_applied`
- `fcm_sent_passenger`
- `fcm_sent_drivers`

This can be:
- embedded in outbox event
- or stored in separate `outboxDeliveries`

## Minimum Consumers

1. Pub/Sub publisher
2. RTDB assignment/cleanup projector
3. Notification dispatcher

## Design Rule

RTDB signal writes and stale-card deletes should be driven from durable events, not only inline request handlers.
