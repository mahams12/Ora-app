# ADR-005: Durable Outbox for Firestore → Side Effects

## Status
Accepted / Locked.

## Decision
For any Firestore state change that requires downstream side effects (RTDB projection, Pub/Sub publication, FCM notifications), write a durable outbox record in the same Firestore transaction.
Publish/dispatch asynchronously via an outbox projector with at-least-once delivery and dead-letter handling.

