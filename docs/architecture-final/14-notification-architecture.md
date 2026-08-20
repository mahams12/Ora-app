# Notification Architecture (RTDB + FCM, Best-Effort)

Authoritative sources:
- `docs/architecture/realtime-architecture.md`
- `docs/architecture-review/outbox-design.md`
- `docs/architecture-review/event-contracts.md`
- `docs/operations/observability.md`

## Delivery Channels

1. **In-app realtime (RTDB)**
   - Ride signals / assignment invalidation: `rideSignals/{rideId}`
   - Pending request cards: `rideRequests/{driverId}/pending/{rideId}`
   - Live GPS: `tripLocations/{rideId}`

2. **Push fallback (FCM)**
   - Data-only messages to wake app when RTDB listener is missing/not connected
   - Example types include: `NEW_RIDE_REQUEST`, `RIDE_ASSIGNED`

## Delivery Priority

Correctness-critical updates must be recoverable from Firestore:
- RTDB/FCM are never correctness truth for assignment/payment.
- FCM is a wake-up; client always re-reads Firestore on receipt/open.

## Deduplication

- Durable side effects driven from outbox events must be deduped by `eventId`.
- FCM can deliver duplicates; client must ignore duplicates using `messageId` caching per session (implementation strategy in stale-event handling docs).

## Collapse / Expiration

- Outbox projection records include publish state and attempt counts.
- Notifications are scheduled/retried independently; failures should move to dead-letter per outbox design with ops alerting.

## Security / Privacy

- Push payload must not contain sensitive fields (tokens, payment secrets, full PII).
- Prefer rideId/driverId/seq references; never include access tokens.

## Phase 1.6 Freeze

Trip-sharing token lifecycle and browser-access privacy boundaries are now frozen in:
`docs/architecture-final/24-phase-1.6-condition-closure.md` section 5D.

