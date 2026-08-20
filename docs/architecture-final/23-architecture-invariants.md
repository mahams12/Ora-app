# Architecture Invariants (MUST NEVER BE VIOLATED)

This document is the final “do not break” contract for Ora’s end-to-end architecture.

Any architecture change that violates an invariant is a **BLOCKER** for Phase 2+ implementation.

## Flutter / MVVM / Layering Invariants

1. **Views are presentation-only.** `presentation/views` must not import infrastructure packages (Dio/Firebase/RTDB/Firestore/Maps SDK/data sources).
2. **ViewModels are orchestration-only.** ViewModels must not contain business rules or infrastructure implementations.
3. **Use cases contain workflows.** Use cases must not depend on `BuildContext`, navigation side effects, or Flutter UI APIs.
4. **Repositories hide data sources.** Domain repository interfaces live under `domain/`, implementations live under `data/`.
5. **go_router is navigation only.** Views may initiate navigation; they may not “reconstruct” business workflows without ViewModel/use-case intents.

## Product Model Invariants (P2P Offered-Fare)

6. **Dispatch is not assignment.** Driver Accept/Counter creates a **pending offer**; it never assigns the ride.
7. **Passenger selection is the assignment command.** Assignment occurs only when passenger selects an offer.
8. **Server is authoritative for ride assignment.** The winner is determined only by server-side conditional logic (Firestore transaction semantics).
9. **Exactly one assignment commits.** There must exist no reachable path where multiple drivers become assigned for the same ride.
10. **agreedFare is immutable after assignment.** It is copied from the selected offer at assignment time; clients cannot write it.
11. **Offer selectable state is server-managed.** Only offers in canonical selectable status may be selected.
12. **Direct Mode / “first accept wins” is forbidden.** Any product/UX illusion of “accept == assign” must not map to backend state.

## Consistency / Realtime / Ordering Invariants

13. **Firestone/Firestore is ride truth for authoritative state.** RTDB and Redis may be projections or coordination helpers only.
14. **RTDB is best-effort projection.** Clients must recover correctness from Firestore on reconnect.
15. **Redis is never the authoritative assignment/payment source.** Redis may be used for GEO/locks/dispatch caches only.
16. **Outbox is required for downstream side effects.** Any “Firestore commit + async side effect” must be driven by durable outbox events.
17. **Outbox publish is at-least-once.** Consumers must be idempotent and dedupe by `eventId`.
18. **Old realtime events must not overwrite new state.** Clients must discard stale updates using ride `aggregateVersion` + signal `eventSequence` (and location `locationSeq`).
19. **Signal events carry versions.** Projection consumers must reject events that go backwards in their ordering domains.

## Idempotency / Retry Invariants

20. **Idempotency keys are required for business-critical and financial mutations.**
21. **Non-idempotent mutations cannot be auto-retried blindly.** Client retry logic must respect the idempotency policy.
22. **Duplicate requests must replay the same logical outcome.** Durable idempotency record + request hash must be used.
23. **Provider callback dedupe is mandatory.** Duplicate webhooks must ACK without re-applying ledger effects.

## Payments / Ledger Invariants

24. **Ride lifecycle and payment lifecycle are separate state machines.**
25. **Ledger is financial truth.** Wallet balance is derived/projection only.
26. **Ledger entries are append-only.** Clients cannot mutate ledger, payment intent/attempt states, or reconciliation records.
27. **Payment confirmation is server-authoritative.** Client “success” claims are never trusted.
28. **Cash collection remains auditable.** Even though cash does not go through a PSP, it must still have immutable payment aggregates + ledger postings/obligations where applicable.

## Security Invariants

29. **All API calls must pass App Check + JWT validation.**
30. **Default deny for sensitive stores.** Firestore rules must be explicit/least-privilege.
31. **RTDB ride data is participant-scoped.** No arbitrary authenticated read access to ride signals/locations.
32. **No trust in client location as fraud-proof.** Server validates accuracy, staleness, speed plausibility, sequence monotonicity, and geofences.
33. **No secrets or tokens in logs and push payloads.** Never log or transmit access tokens/refresh tokens/payment secrets.

## Privacy / Data Retention Invariants

34. **Passenger location is not retained as durable operational truth post-trip.**
35. **Driver location is auto-deleted after trip terminal state (ephemeral retention only).**
36. **Auditable trails exist for correctness-critical changes** (rideEvents/audit logs and payment aggregates).

## Operational / Failure Invariants

37. **Redis/RTDB/PubSub failures must not break correctness.** Correctness must survive by durable state + replay/outbox + read-repair.
38. **Dead letters exist.** Outbox publishers and projection consumers must move failing events to dead-letter storage after thresholds and alert ops.
39. **Old location streams cannot overwrite active streams.** Late packets from replaced `locationStreamId`s must always be rejected.
40. **Critical idempotency keys must survive app kill/restart.** Clients must durably persist and reuse them until authoritative recovery or terminal replay.
41. **Unsupported event schema versions must fail safe.** Consumers must not blindly apply unknown-version events to projections.
42. **Admin and moderation actions are audited and constrained.** No admin flow may silently bypass ride/payment/security invariants without explicit audited correction tooling.

