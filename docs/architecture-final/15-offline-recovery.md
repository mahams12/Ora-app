# Offline & Recovery Architecture

Authoritative sources:
- `docs/architecture-review/consistency-model.md`
- `docs/architecture-review/event-contracts.md`
- `docs/algorithms/stale-event-handling.md`
- `docs/operations/disaster-recovery.md`

## Core Rule

When durable state and realtime projection disagree, **durable Firestore / durable financial records win**.

## Offline Scenarios

### Offline before request
- Client may show cached UI state, but ride creation must fail or be queued (Gap: offline queuing semantics are not defined).
- On reconnect, client must call `POST /rides` with fresh requestVersion/pricingSnapshotId.

### Offline during SEARCHING / OFFERS_AVAILABLE
- Driver/passenger reconnect must re-read ride from Firestore.
- Pending offer cards must be reconciled from Firestore; never “promote” stale cards to assignment.

### Offline during assignment / select
- If REST mutation succeeded but device disconnects:
  - On reconnect, fetch ride from Firestore to determine assignment.
- Client must discard RTDB signals with versions <= current local versions.

### Offline during active ride (live location)
- Marker updates degrade until RTDB listener reconnects.
- Passenger should reattach listeners; if sequence gaps or stale signals detected, refresh from Firestore snapshot.

### Offline during payment
- Payment state is read from payment aggregates in Firestore.
- Client must show `PENDING` / `CAPTURE_PENDING` / `RECONCILIATION_REQUIRED` states based on server data.

### App killed and restarted
- Consistency model requires read-repair:
  1. Re-read ride aggregate from Firestore
  2. Attach RTDB listeners
  3. Discard stale events using version + sequence counters

## Token expiry / auth outage

- On 401/APP_CHECK errors: client must refresh or re-auth.
- Disaster recovery runbook defines cached token usage up to expiry.

## Reconnect Behaviour Protocol (from consistency-model)

Passenger:
1. re-read active ride from Firestore
2. attach RTDB listeners for live location + signals
3. discard stale signals by aggregateVersion/eventSequence

Driver:
1. restore presence in RTDB
2. resync active assignment from Firestore
3. if pending card exists locally, validate against Firestore before offering (since accept != assignment)

## Replay/ordering protection

- stale-event-handling defines monotonic discard rules:
  - ride version/eventSequence
  - GPS locationSeq

