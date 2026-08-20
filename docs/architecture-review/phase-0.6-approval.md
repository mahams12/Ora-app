# ORA — Phase 0.6 Approval

## Documents Changed

- `docs/ORA_MASTER_PLAN.md`
- `docs/ORA_TECH_STACK.md`
- `docs/ORA_STATE_MACHINE.md`
- `docs/ORA_SECURITY_MODEL.md`
- `docs/ORA_LATENCY_SLO.md`
- `docs/architecture/system-overview.md`
- `docs/architecture/backend-architecture.md`
- `docs/architecture/realtime-architecture.md`
- `docs/architecture/location-architecture.md`
- `docs/algorithms/ride-assignment.md`
- `docs/algorithms/idempotency.md`
- `docs/algorithms/matching-engine.md`
- `docs/algorithms/stale-event-handling.md`
- `docs/database/firestore-schema.md`
- `docs/database/realtime-schema.md`
- `docs/database/redis-schema.md`
- `docs/api/api-contract.md`
- `docs/api/ride-api.md`
- `docs/api/error-codes.md`
- `docs/product/payment-flow.md`
- `docs/product/ride-lifecycle.md`
- `docs/product/passenger-flow.md`
- `docs/product/safety-flow.md`
- `docs/security/security-model.md`
- `docs/security/authorization-matrix.md`
- `docs/security/threat-model.md`
- `docs/operations/disaster-recovery.md`
- `docs/implementation/phase-10-trip.md`
- `docs/implementation/phase-11-payments.md`
- `docs/testing/test-strategy.md`
- `docs/architecture-review/event-contracts.md`
- `docs/architecture-review/payment-ledger-design.md`
- `docs/architecture-review/phase-0.6-changelog.md`

## BLOCKER Issues Resolved

1. Assignment authority corrected to Firestore transaction semantics.
2. Durable outbox introduced for state-change side effects.
3. Durable idempotency model defined for business-critical mutations.
4. Payment architecture promoted to first-class durable aggregates with immutable ledger.
5. Ride and payment lifecycles separated.

## HIGH Issues Resolved

1. Source-of-truth ownership clarified across Firestore, RTDB, and Redis.
2. Version, event ordering, and GPS sequencing separated.
3. RTDB authorization tightened to participant-scoped access.
4. Location trust model corrected to treat client GPS as untrusted input.
5. Simultaneous top-30 dispatch replaced with deterministic waves.
6. Redis degraded-mode claims made implementable and explicit.

## MEDIUM Issues Resolved

1. Foreground-only latency wording clarified for fast-path SLOs.
2. Matching score updated to use prior-adjusted rating logic.
3. Ride aggregate history bounded; full audit moved to event log.
4. Monetary persistence standardized around integer minor units.

## Remaining LOW / INFO Issues

- RTDB long-trip history sizing remains an implementation tuning concern, but the architecture now uses `latest` plus bounded `recent`.
- Background geolocation licensing/procurement remains an operational planning item.

## New Architecture Decisions

- Firestore conditional transaction is the single authoritative assignment barrier.
- Durable outbox is mandatory for important state-change side effects.
- Payment is a separate aggregate from ride lifecycle.
- Wallet balance is a projection; immutable ledger is financial truth.
- RTDB ride access is participant-scoped through server-managed access projection.
- Dispatch uses deterministic waves rather than blanket simultaneous fan-out.

## Remaining Risks

- Implementation quality still matters; the corrected documentation reduces architecture risk but does not replace robust tests.
- Payment-provider-specific operational behavior will still need sandbox validation in Phase 11.

## Phase 1 Readiness

BLOCKER = 0  
HIGH correctness/security issues = 0

PHASE 0.6 STATUS:

APPROVED FOR PHASE 1
