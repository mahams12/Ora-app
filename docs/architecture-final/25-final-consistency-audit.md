# Final Consistency Audit (Phase 1.6)

Date: 2026-08-19

## 1) Files Scanned

- `docs/architecture-final/**` (including all `*.md` files)
- `docs/architecture-final/ADRs/**`

## 2) Stale Statements Found (before corrections)

1. `docs/architecture-final/08-concurrency-and-race-audit.md`
   - Case 19 still claimed the outbox projector “delivery-state transition atomicity” was a `(Gap)`.

2. `docs/architecture-final/09-security-threat-model.md`
   - An authorization gap note included a “ensure Firestore/RTDB rules are not incomplete before implementation” phrasing, which implied security rules were still not fully frozen.

3. `docs/architecture-final/18-cross-feature-clash-matrix.md`
   - Safety × Ride clash still described “safety can cancel” as a `(Gap)` rather than pointing at the Phase 1.6 frozen safety → ride intervention contract.

4. `docs/architecture-final/ADRs/ADR-014-Security-Model.md`
   - ADR status still included “with pending rule finalization”, which was stale after Phase 1.6 contract freeze.

## 3) Statements Corrected

1. Updated `docs/architecture-final/08-concurrency-and-race-audit.md`
   - Removed the outbox delivery-state atomicity `(Gap)` and replaced it with the at-least-once + transactional claim/ACK/DELIVERED semantics frozen in:
     - `docs/architecture-final/24-phase-1.6-condition-closure.md` section 3.

2. Updated `docs/architecture-final/09-security-threat-model.md`
   - Replaced the “rules are not incomplete before implementation” statement with a Phase 1.6 closure reference:
     - `docs/architecture-final/24-phase-1.6-condition-closure.md` section 1
   - Kept remaining work scoped to implementation validation (rule tests + rollout review).

3. Updated `docs/architecture-final/18-cross-feature-clash-matrix.md`
   - Replaced the safety-cancel `(Gap)` with a reference to the frozen safety → ride intervention matrix:
     - `docs/architecture-final/24-phase-1.6-condition-closure.md` section 7.

4. Updated `docs/architecture-final/ADRs/ADR-014-Security-Model.md`
   - Removed “with pending rule finalization” from ADR status.

## 4) Genuine Unresolved Items (if any)

Remaining “(Gap) / not fully specified” items are **explicitly non-implementation-gating** for Phase 1.6 frozen contracts (i.e., they do not contradict any frozen HIGH condition contract for OTP, outbox/projector semantics, security-rule matrix, idempotency durability, safety→ride intervention, locationStreamId resume, Redis degraded-mode behavior, event schema versioning, or nearby-driver authorization).

These remaining gaps are classified as:

1. `docs/architecture-final/03-state-machines.md`
   - Driver KYC required-set rules are not exhaustively enumerated. (Non-enumerated policy detail; does not contradict Phase 1.6 gating contracts.)

2. `docs/architecture-final/15-offline-recovery.md`
   - Offline queuing semantics are not defined in full detail.

3. `docs/architecture-final/13-payment-architecture.md`
   - Exact reconciliation job contract is not fully enumerated.

4. `docs/architecture-final/09-security-threat-model.md`
   - Collusion detection depends on a later Phase 14 anomaly detection pipeline; docs still label this as MEDIUM.

5. `docs/architecture-final/02-feature-inventory.md`, `docs/architecture-final/22-final-gap-analysis.md`
   - POST-MVP UX and analytics/logging sampling policies (Phase 2+) are not fully specified.

6. “unresolved” / “pending” words that appear in algorithms/state machines
   - They describe *business states* (e.g., “pending offers”, “unresolved ordering anomaly”) and are not stale “architecture gating conditions”.

## 5) OTP Consistency Check (Phase 1.6)

Result: PASS (amended 2026-08-20 via ADR-016)

Authoritative definition used (single source for current product):
- `docs/architecture-final/ADRs/ADR-016-Firebase-Native-OTP.md` (Path A)

Current product parameters:
- OTP provider = Firebase Phone Auth
- Ora client resend UX cooldown ≈ `30s`
- Post-auth abuse controls = App Check + API rate limits + bans (ADR-014)
- Custom `otpSessions` limits in section 4 of
  `24-phase-1.6-condition-closure.md` = **Path B / not implemented**

Cross-doc agreement:
- `03-state-machines.md` and section 4 carry the ADR-016 amendment note.

## 6) Outbox / Projector Consistency Check (Phase 1.6)

Result: PASS

Authoritative definition used (single source):
- `docs/architecture-final/24-phase-1.6-condition-closure.md` section 3

Verified projector/outbox invariants:
- Outbox event envelope includes `eventId`, `aggregateId`, `aggregateType`, `aggregateVersion`, `eventSequence`, `schemaVersion`
- Delivery is **at-least-once** (exactly-once is explicitly not claimed)
- per-subscriber delivery tracking in `outboxDeliveries/{eventId}_{subscriber}`
- transactional worker behavior:
  - transactionally claims delivery (`CLAIMED` + lease fields)
  - transactionally marks subscriber `ACKED`
  - if all subscribers ACKED => mark outbox event `DELIVERED`
- crash semantics are consistent:
  - crash before publish => lease expires and another worker reclaims
  - crash after publish before ack => duplicate publish possible but subscriber must dedupe by `eventId`
- retry ceilings + dead-letter + replay rules frozen

Stale projector-atomicity `(Gap)` removed:
- `docs/architecture-final/08-concurrency-and-race-audit.md` Case 19 now matches section 3 freeze.

## 7) Security Consistency Check (Phase 1.6)

Result: PASS

Frozen security-rule reference used:
- `docs/architecture-final/24-phase-1.6-condition-closure.md` section 1

Verified consistency:
- `docs/architecture-final/05-database-model.md` references the “full collection-level security matrix” freeze
- `docs/architecture-final/09-security-threat-model.md` threat item no longer implies rules are incomplete; remaining scope is implementation validation (rule tests + rollout review)
- `docs/architecture-final/ADRs/ADR-014-Security-Model.md` no longer contains stale “pending rule finalization” status wording

Remaining MEDIUM “Gap” entries in the threat model:
- relate to later pipeline capability (collusion detection dependence), not to the Phase 1.6 security-rule freeze.

## 8) Idempotency Consistency Check (Phase 1.6)

Result: PASS

Authoritative definition used:
- `docs/architecture-final/24-phase-1.6-condition-closure.md` section 2

Verified that all referenced documents treat durable idempotency durability as frozen:
- local key persistence through app kill / device restart
- concurrent duplicate request behavior is deterministic via durable records
- retry semantics replay stable logical outcomes
- key lifecycle + cleanup/retention are specified in the closure doc

No doc claims “idempotency durability” is still unresolved post Phase 1.6.

## 9) Secondary-Feature Consistency (Phase 1.6)

Result: PASS

Frozen contract location:
- `docs/architecture-final/24-phase-1.6-condition-closure.md` section 5

Verified:
- secondary feature contracts (support, terms/consent, block/report, trip sharing, reviews, admin/moderation) are referenced as frozen in:
  - `docs/architecture-final/22-final-gap-analysis.md` HIGH-risk closure summary
- no remaining “unresolved HIGH” wording for these feature contracts
- remaining “not fully specified” items are POST-MVP/non-gating UX or later-phase policies

## 10) Location Consistency (Phase 1.6)

Result: PASS

Frozen contract references:
- `docs/architecture-final/10-location-architecture.md` (explicit “now frozen” statement)
- `docs/architecture-final/24-phase-1.6-condition-closure.md` section covering `locationStreamId` lifecycle + stale old-stream packet rejection

Verified:
- `locationStreamId` lifecycle + restart negotiation
- monotonic sequence rules
- old `locationStreamId` packets cannot overwrite newer active streams

## 11) Safety Consistency (Phase 1.6)

Result: PASS

Frozen contract:
- `docs/architecture-final/24-phase-1.6-condition-closure.md` section 7 (Safety → Ride State Matrix)

Verified:
- safety events can only trigger ride interventions according to the frozen matrix
- “safety can cancel” semantics now point at the frozen contract (stale `(Gap)` removed from `18-cross-feature-clash-matrix.md`)

## 12) Redis Consistency (Phase 1.6)

Result: PASS

Frozen contract references:
- `docs/architecture-final/05-database-model.md`
- `docs/architecture-final/22-final-gap-analysis.md` notes redis degraded-mode behavior is frozen

Verified:
- correctness authority remains Firestore
- redis degraded-mode impacts dispatch availability/performance only

## 13) Schema-Version Consistency (Phase 1.6)

Result: PASS

Frozen contract:
- `docs/architecture-final/24-phase-1.6-condition-closure.md` section 9 (Event schema versioning freeze)

Verified:
- envelope includes `schemaVersion`, `aggregateVersion`, and `eventSequence`
- compatibility rules are defined (old producer/new consumer + new producer/old consumer)
- unknown version handling is fail-safe

## 14) Architecture Invariant Consistency (Phase 1.6)

Result: PASS

Re-checked:
- `docs/architecture-final/23-architecture-invariants.md`

Verified no contradictions introduced by the Phase 1.6 closure and the text-only stale-warning fixes:
- redis is not authoritative for assignment/payment
- Firestore remains assignment authority
- dispatch is not assignment
- outbox side effects are at-least-once and consumers are dedupe/idempotent
- old events cannot overwrite newer state (version/sequence discard rules)

## 15) Final Grep/Search Result (manual inspection)

Repo-wide match scan after corrections retained only non-gating/non-contradictory “Gap / unresolved / not fully specified” language (no stale unresolved HIGH claims remain).

Remaining matches are limited to:
- intentional business-state terminology (“pending offers”, “unresolved ordering anomaly”, “unresolved incident lifecycle”)
- POST-MVP UX/policy gaps (reviews/search/history/log sampling Phase 2+)
- non-contract-enumeration gaps that do not contradict Phase 1.6 frozen HIGH contracts (offline queuing semantics, reconciliation job detail enumeration, later-phase collusion pipeline dependency, KYC required-set enumerations)

## 16) Final Architecture Status

- BLOCKERS = 0
- HIGH = 0

ARCHITECTURE STATUS: APPROVED

