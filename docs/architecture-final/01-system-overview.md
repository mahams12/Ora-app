# System Overview (End-to-End Coherence)

## What Ora Is

Ora is a **P2P offered-fare** ride platform:
passenger proposes price → drivers accept/counter with offers → passenger selects one offer → **server atomically assigns exactly one driver** → ride proceeds → payment/ledger settlement → ratings/reviews.

Dispatch is not assignment; driver accept/counter creates **pending offers**.

## Core Architectural Pillars

1. **Server-authoritative state**:
   - Firestore is the durable source of truth for ride assignment/state and the barrier for correctness.
   - RTDB is an ephemeral projection layer for live location/presence/signals.
   - Redis is ephemeral (GEO/locks/dispatch caches), never authoritative.
2. **Durable outbox**:
   - Firestore commits side-effect intent into an outbox record in the same transaction.
   - Outbox projector publishes to Pub/Sub and triggers RTDB cleanup + FCM fallback.
3. **Durable idempotency**:
   - Business-critical mutations (ride create, offer create, select/assignment, payments/cash collection, etc.) must be safe to retry via durable idempotency records.
4. **Versioned replay & read-repair**:
   - Clients must discard stale realtime updates using ride `aggregateVersion` + signal `eventSequence`, and discard stale GPS using `locationSeq`.
5. **Strict Flutter MVVM boundaries**:
   - Views render state and dispatch user intents only.
   - ViewModels orchestrate presentation state and call use cases.
   - Use cases implement workflows.
   - No direct infrastructure access in Views.

## High-Level Component Interaction

See `docs/architecture/system-overview.md` and `docs/architecture/realtime-architecture.md`.

Minimal flow:

1. Client → Cloud Run API: create ride request / create offer / select offer / cancel / status transitions.
2. Cloud Run → Firestore (Admin SDK): conditional transactions + durable outbox.
3. Cloud Run/Outbox projector → RTDB (server projection) and Pub/Sub events.
4. Clients listen:
   - Firestore: authoritative ride state.
   - RTDB: live markers, assignment signals, invalidation of pending request cards.
   - FCM: best-effort fallback when listeners aren’t connected.

## Phase 1 Context (Flutter Foundation Only)

The current Flutter Phase 1 codebase establishes:
- MVVM folder structure & layer rules in code and tests
- Riverpod DI wiring (providers graph)
- Freezed immutable state patterns
- go_router route table scaffolding
- networking abstraction with request/correlation IDs and typed errors

No ride dispatch/assignment, no payment capture, no RTDB/Firestore connectivity is implemented yet in Flutter (by design and by test constraints).

