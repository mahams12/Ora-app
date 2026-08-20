# ADR-003: Firestore Transaction is the Assignment Barrier

## Status
Accepted / Locked.

## Decision
Driver Accept / Counter creates **pending offers**.
Passenger selecting an offer commits the authoritative assignment using a Firestore conditional transaction.
Redis locks are optional and never correctness authority.

## Context
P2P offered-fare marketplace requires deterministic exactly-one assignment under concurrency.

## Consequences
- Correctness survives Redis loss, expiration, and retries.
- RTDB/FCM are projections/notifications only.

