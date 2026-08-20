# Final Gap Analysis (Architecture Pass)

This document consolidates:
- cross-document consistency checks
- end-to-end coherence checks against the locked product model
- adversarial gap discovery (races, replay, offline/reconnect, security, persistence)

## Key Findings Summary

The locked architecture documents are largely coherent:
- P2P offered-fare model is consistent across ride lifecycle, offer model, and assignment algorithm.
- Assignment correctness is consistently treated as Firestore transactional.
- Payment/ledger is consistently separate from ride lifecycle.
- Durable outbox + durable idempotency are consistently required for side-effect recovery.

The unresolved Phase 1.5 HIGH conditions were closed in Phase 1.6 via:
`docs/architecture-final/24-phase-1.6-condition-closure.md`.

## A. BLOCKERS

- None identified that force a full redesign of the locked product model or architecture patterns.
- However, **implementation must not start on affected features until the HIGH risks below are explicitly frozen**. These are not model-breaking blockers, but they are implementation-gating architecture conditions.

## B. HIGH RISKS

- None remain unresolved after Phase 1.6 closure.
- The former HIGH items are now frozen in `24-phase-1.6-condition-closure.md`:
  - collection-level security matrix
  - durable idempotency lifecycle and restart persistence
  - outbox per-subscriber delivery semantics
  - OTP throttle/cooldown/lock rules
  - secondary feature contracts (support, consent, block/report, trip sharing, reviews, admin/moderation)

## C. MEDIUM RISKS

- Remaining medium risks are operational/implementation tradeoffs, not contract-free gaps:
  1. Location-stream resume is now defined, but still needs strong emulator/device validation.
  2. Safety-to-ride intervention matrix is now frozen, but policy tuning may evolve.
  3. Redis degraded-mode behavior is now frozen; launch thresholds may still be tuned operationally.

## D. LOW RISKS

1. **API authorization for `GET /v1/drivers/nearby` is not explicitly client-authared in the current doc set** (LOW)
2. **“Terms/consent” absence** (LOW) — the docs set does not include a locked consent state machine.

## E. MISSING FEATURES (NOT IMPLEMENTATION)

1. Support ticket lifecycle API + read contract (POST-MVP) is only partially documented in the doc set.
2. Review/comment UX contract (“reviews” beyond rating) is not fully specified.
3. Trip-sharing web-view security contract (token TTL, route access) is not fully enumerated.

## F. CONTRADICTIONS

- None found between the locked core docs for ride/offer assignment and payment/ledger separation.

## G. DUPLICATE SOURCES OF TRUTH (allowed caches, but verify)

Allowed derived caches exist (and docs say which wins), including:
- Redis driver:online vs RTDB driverPresence vs Firestore driver availability (authoritative: Firestore for business availability; RTDB presence ephemeral).

## H. RACE CONDITIONS (covered but must be implemented/tested)

- Out-of-order realtime signals: covered via version/sequence discard + read-repair.
- Duplicate outbox delivery: covered via eventId dedupe.
- Assignment contention: covered via Firestore transaction predicates.

Resolved in Phase 1.6:
- Outbox projector per-subscriber delivery tracking + crash/restart + replay semantics are frozen in `docs/architecture-final/24-phase-1.6-condition-closure.md` section 3.

## I. SECURITY GAPS

- No unresolved HIGH security gap remains.
- Residual security work is implementation validation: rule tests, admin tooling hardening, and rollout review.

## J. PERFORMANCE GAPS

From cost model:
- Top-30 fan-out is explicitly avoided by deterministic waves.
- Logging volume and read duplication must be controlled.

Missing:
- Exact client logging sampling policies are not fully specified for Phase 2+ telemetry.

## K. API GAPS

- Nearby-driver authorization and privacy are now frozen.
- OTP and idempotency request semantics are now frozen.

## L. DATABASE GAPS

- TTL/index requirements are now frozen.
- Sensitive collection ownership is now frozen.

## M. REALTIME GAPS

- Outbox replay/dead-letter thresholds are now frozen.

## N. TESTING GAPS

- No unresolved architecture-gating test gap remains.
- Remaining work is implementation execution of the mandated test suite in Phase 2+.

## O. DOCUMENTATION GAPS

- No unresolved documentation gap remains for implementation-gating contracts.

## Architecture Decision

- **BLOCKERS:** 0
- **HIGH:** 0

## ARCHITECTURE STATUS

**APPROVED**

Meaning:
- The locked core model remains unchanged and coherent.
- All implementation-gating Phase 1.5 conditions were explicitly frozen in Phase 1.6.

