# Deployment & Migration Safety

Authoritative sources:
- `docs/ORA_MASTER_PLAN.md` (rollback principles)
- `docs/operations/disaster-recovery.md`
- `docs/operations/observability.md`

## Deployment Model

- Flutter: store phased rollout + remote config feature flags
- Backend: Cloud Run traffic-splitting and safe promotion
- Firestore: rules versioning + `firebase deploy --only firestore:rules`

## Safe Migration Principles

1. **Database migrations must be backwards compatible** with older clients until the rollout window completes.
2. **Event schema changes must be additive** or gated by `schemaVersion`.
3. **Security rules deploys are treated as high-risk**:
   - default deny remains
   - deploy with rollback plan
4. **Feature flags** must include kill-switches to disable new feature flows without breaking ride correctness.
5. **Outbox schema changes must preserve eventId stability**; consumers must dedupe by eventId.

## Rollback

- Cloud Run: instant traffic split rollback
- Firestore rules: git revert + redeploy rules
- Flutter: stop rollout at 0% + remote config kill switch

## Phase 1.6 Freeze

Security-rule rollout remains a high-risk deployment surface, but the rule matrix itself is now frozen in:
`docs/architecture-final/24-phase-1.6-condition-closure.md` section 1.

Any migration that changes:
- Firestore rule allowlists
- outbox schema
- idempotency schema
- event schemaVersion semantics

must preserve backward compatibility and include rollback steps.

