# Testing Matrix (Before Production)

Authoritative sources:
- `docs/testing/test-strategy.md`
- `docs/testing/race-condition-tests.md`
- `docs/architecture-review/consistency-model.md`
- `docs/architecture-review/idempotency-matrix.md`

## Test Types

- Unit tests: fare engine, ride state machine transitions, authorization predicates, idempotency behavior, location validation
- Widget tests: design system primitives + error/empty/loading states (Phase 2+ screens)
- Integration tests: ride lifecycle using emulators; simultaneous select/accept; outbox retry
- API/repository tests: endpoint contract + error codes mapping
- Security tests: authorization rules coverage + RTDB read/write gating

## Required Test Categories (Coverage Targets)

Per `docs/testing/test-strategy.md` and `docs/testing/race-condition-tests.md`:

1. Concurrency tests
   - 3-driver accept race → 3 PENDING offers, 0 assigned
   - concurrent passenger selects → exactly 1 assignment
2. Stale/ordering tests
   - out-of-order RTDB / GPS packets discarded by sequence checks
3. Idempotency tests
   - duplicate create/offer/select/cancel returns stable outcome via durable idempotency
4. Offline/reconnect tests
   - reconcile from Firestore snapshot on reconnect
5. Payment tests
   - duplicate PSP webhooks create no duplicate ledger effects
6. Outbox retry & dead-letter
   - projector crash recovery and at-least-once publisher correctness

## Phase 1 Flutter (what exists now)

- Mobile unit tests include: failure mapping, retry policy, provider wiring, go_router registration, splash ViewModel state transitions, and MVVM boundary checks (Views must not import infrastructure).

## Phase 1.6 Mandatory Closures

The previously unresolved test requirements are now frozen in:
`docs/architecture-final/24-phase-1.6-condition-closure.md` section 13.

Mandatory additional architecture-gating tests include:
- security rules for every sensitive collection
- idempotency across timeout/app-kill/restart
- outbox crash-before/after-publish and dead-letter replay
- OTP cooldown/expiry/old-after-new
- location old-stream vs new-stream rejection
- unknown/new/old event schema compatibility behavior

