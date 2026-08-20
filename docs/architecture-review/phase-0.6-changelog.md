# ORA — Phase 0.6 Correction Changelog

## Correction 1

**Issue**  
Assignment authority was over-attributed to Redis.

**Old design**  
Redis `SETNX` was described as the mechanism that guarantees one winner.

**New design**  
Firestore conditional transaction is the authoritative correctness barrier. Redis is documented only as an optional contention reducer.

**Reason**  
Durable correctness must survive Redis loss, expiry, and process crashes.

**Affected documents**  
`ORA_MASTER_PLAN.md`, `ORA_STATE_MACHINE.md`, `ORA_SECURITY_MODEL.md`, `architecture/system-overview.md`, `architecture/backend-architecture.md`, `architecture/realtime-architecture.md`, `algorithms/ride-assignment.md`, `security/security-model.md`, `security/threat-model.md`

**Implementation impact**  
Phase 8 and Phase 9 must implement transaction predicates exactly and treat Redis as optional.

**Status**  
RESOLVED

## Correction 2

**Issue**  
No durable recovery path existed for Firestore success with RTDB / Pub/Sub / FCM failure.

**Old design**  
State change and downstream side effects were implied to happen in one reliable linear flow.

**New design**  
State changes now require an outbox event record written in the same Firestore transaction, then asynchronous projection/publication with retry and dead-letter behavior.

**Reason**  
Firestore and Pub/Sub are not one atomic transaction.

**Affected documents**  
`ORA_MASTER_PLAN.md`, `architecture/backend-architecture.md`, `architecture/realtime-architecture.md`, `architecture/system-overview.md`, `operations/disaster-recovery.md`, `architecture-review/event-contracts.md`, `architecture-review/outbox-design.md`, `architecture-review/consistency-model.md`

**Implementation impact**  
Ride-engine, RTDB projector, notification dispatcher, and observability pipelines must consume durable outbox events idempotently.

**Status**  
RESOLVED

## Correction 3

**Issue**  
Idempotency was incomplete, partly invalid, and too Redis-dependent.

**Old design**  
Redis-only idempotency with invalid `GETSET ... NX EX` semantics.

**New design**  
Durable `idempotencyRecords` with `idempotencyKey`, `requestHash`, `actorId`, `operation`, `resourceId`, `status`, `responseSnapshot`, `createdAt`, `expiresAt`.

**Reason**  
Ride creation, assignment, and payment mutations need durable replay and timeout recovery.

**Affected documents**  
`algorithms/idempotency.md`, `architecture/backend-architecture.md`, `api/api-contract.md`, `api/ride-api.md`, `product/payment-flow.md`, `database/redis-schema.md`, `architecture-review/idempotency-matrix.md`

**Implementation impact**  
All critical mutation handlers must persist durable idempotency records and reject same-key different-payload reuse.

**Status**  
RESOLVED

## Correction 4

**Issue**  
Payment architecture was under-modeled and financially unsafe.

**Old design**  
Wallet balance and ride state carried too much implied payment truth.

**New design**  
First-class payment entities: `PaymentIntent`, `PaymentAttempt`, `PaymentProviderCallback`, `DriverPayout`, `Refund`, `WalletLedgerEntry`, `ReconciliationRecord`, with immutable ledger and derived balance projection.

**Reason**  
Financial correctness, callback replay safety, and reconciliation require explicit durable models.

**Affected documents**  
`ORA_MASTER_PLAN.md`, `ORA_SECURITY_MODEL.md`, `database/firestore-schema.md`, `product/payment-flow.md`, `product/ride-lifecycle.md`, `api/error-codes.md`, `implementation/phase-11-payments.md`, `architecture-review/payment-ledger-design.md`

**Implementation impact**  
Phase 11 must be built around immutable ledger posting and separate payment aggregates.

**Status**  
RESOLVED

## Correction 5

**Issue**  
Ride lifecycle and payment lifecycle were conflated.

**Old design**  
Ride states included `PAYMENT_PENDING`, `PAYMENT_FAILED`, and `COMPLETED`.

**New design**  
Ride lifecycle ends at `RIDE_COMPLETED` / `RIDE_CLOSED`; payment is a separate aggregate with its own states.

**Reason**  
Operational trip completion and financial settlement are not the same concern.

**Affected documents**  
`ORA_STATE_MACHINE.md`, `ORA_MASTER_PLAN.md`, `product/ride-lifecycle.md`, `product/payment-flow.md`, `implementation/phase-10-trip.md`, `testing/test-strategy.md`, `api/ride-api.md`

**Implementation impact**  
Trip completion and payment settlement can now fail or reconcile independently without corrupting ride terminality.

**Status**  
RESOLVED

## Correction 6

**Issue**  
RTDB authorization was too broad.

**Old design**  
Some docs allowed any authenticated user to read ride signals or trip locations.

**New design**  
RTDB ride-scoped reads are gated by a server-managed `rideAccess/{rideId}/{uid}` projection; drivers can write only their own presence.

**Reason**  
Realtime privacy must remain resource-scoped.

**Affected documents**  
`ORA_SECURITY_MODEL.md`, `database/realtime-schema.md`, `security/authorization-matrix.md`, `architecture/realtime-architecture.md`

**Implementation impact**  
RTDB rules and realtime projections must be participant-scoped.

**Status**  
RESOLVED

## Correction 7

**Issue**  
Driver availability, presence, and location had competing authorities.

**Old design**  
Firestore, RTDB, and Redis all looked authoritative for operational online state.

**New design**  
Durable driver business availability lives on the driver aggregate; ephemeral presence lives in RTDB; Redis is an ephemeral dispatch cache.

**Reason**  
One owner per concept is required for recovery and reconciliation.

**Affected documents**  
`ORA_MASTER_PLAN.md`, `database/firestore-schema.md`, `database/realtime-schema.md`, `database/redis-schema.md`, `architecture-review/consistency-model.md`

**Implementation impact**  
Matching and admin views must treat Redis and RTDB as projections around a clear ownership model.

**Status**  
RESOLVED

## Correction 8

**Issue**  
Ride version, event ordering, and GPS sequence were mixed.

**Old design**  
`seq` and `sequenceNumber` were used ambiguously across rides, signals, and location.

**New design**  
Formal separation of `rideVersion`, `eventSequence`, and `locationSeq`, with stream scope and reconnect rules.

**Reason**  
Stale-event rejection and reconnect safety depend on distinct ordering domains.

**Affected documents**  
`ORA_STATE_MACHINE.md`, `architecture/realtime-architecture.md`, `architecture/location-architecture.md`, `algorithms/stale-event-handling.md`, `database/realtime-schema.md`, `architecture-review/system-invariants.md`

**Implementation impact**  
Client and server must compare the correct counters for the correct domains.

**Status**  
RESOLVED

## Correction 9

**Issue**  
Dispatch fan-out was too aggressive.

**Old design**  
Top 30 drivers notified simultaneously.

**New design**  
Deterministic wave dispatch with expanding candidate sets and time windows.

**Reason**  
Reduces notification spam, contention, and cost while preserving deterministic behavior.

**Affected documents**  
`ORA_MASTER_PLAN.md`, `algorithms/matching-engine.md`, `architecture/realtime-architecture.md`, `architecture-review/dispatch-wave-design.md`

**Implementation impact**  
Phase 8 dispatch must schedule waves and cancel later waves on assignment.

**Status**  
RESOLVED

## Correction 10

**Issue**  
Redis degraded-mode promises were unrealistic.

**Old design**  
Fallbacks implied undefined or unsafe behavior.

**New design**  
Dispatch may explicitly degrade when Redis GEO is unavailable; Firestore remains the correctness barrier; durable idempotency remains available without Redis.

**Reason**  
Architecture must state safe degraded behavior, not aspirational behavior.

**Affected documents**  
`database/redis-schema.md`, `operations/disaster-recovery.md`, `ORA_MASTER_PLAN.md`

**Implementation impact**  
Operational runbooks and feature flags must support degraded dispatch states.

**Status**  
RESOLVED
