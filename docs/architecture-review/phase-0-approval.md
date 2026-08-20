# ORA — Phase 0 Approval

## Review Summary

- Documents reviewed: 52
- Major contradictions found: 12
- Blocker issues: 5
- High issues: 6
- Medium issues: 4
- Low issues: 2

## Must Be Resolved Before Phase 1

1. Assignment correctness must be formally anchored in Firestore transaction semantics, not Redis wording.
2. Durable outbox/retry design for Firestore-to-RTDB/Pub/Sub/FCM side effects.
3. Durable idempotency design for ride creation, assignment, and payments.
4. Explicit payment entities and immutable ledger/reconciliation model.
5. Separation of ride lifecycle from payment lifecycle.
6. RTDB authorization tightening for ride signals and trip locations.
7. Formal source-of-truth map and reconciliation owner for availability/presence.
8. Formal separation of ride version, event ordering, and GPS sequence systems.
9. Dispatch strategy should be revised away from blanket simultaneous top-30 fan-out.
10. Redis degraded-mode promises must be made implementable, not aspirational.

## Approval Result

PHASE 0 STATUS:

BLOCKED
