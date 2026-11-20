# ORA Documentation Index

**Last updated:** 2026-11-18 · **How to read this:** start with "Authoritative — current state". Everything under "Historical" is preserved for migration traceability and phase history — it describes what was *planned or built at that date*, not necessarily what is true now.

## Authoritative — current state

| Doc | What it covers |
|---|---|
| [`ORA_CURRENT_STATE.md`](ORA_CURRENT_STATE.md) | Chronological status log — what is implemented, verified, deferred. Entry #42+ = latest. |
| [`audits/ORA_ARCHITECTURE_COST_AUDIT.md`](audits/ORA_ARCHITECTURE_COST_AUDIT.md) | Current architecture, cost model, executed fixes, backend module inventory, cloud E2E spec |
| [`audits/ORA_GCP_RESOURCE_DELETION_PROOF.md`](audits/ORA_GCP_RESOURCE_DELETION_PROOF.md) | Live GCP inventory both projects, Redis/VPC deletion evidence (BLOCKED BY BILLING_DISABLED), E2E readiness |
| [`ORA_BACKEND_HANDOFF.md`](ORA_BACKEND_HANDOFF.md) | Developer handoff: modules, collections, endpoints, env config, commands |
| [`ENGINEERING_RULES.md`](ENGINEERING_RULES.md) | Non-negotiable engineering rules |
| [`ORA_MASTER_PLAN.md`](ORA_MASTER_PLAN.md) | Product/build master plan |

## Infrastructure facts that must not be rewritten

- **Redis is removed from the active codebase** — `src/geo/` (Firestore `geoDrivers`), no Redis package/connection/`REDIS_URL`.
- **Redis is absent from `oraapp-a9be5`** (new project, billing ACTIVE — verified via Cloud Asset Inventory 2026-11-18).
- **Old Redis/VPC resources still exist in `ora-app-d8112`** (billing CLOSED): `ora-production-n3-redis` (suspended), `ora-staging-vpc` connector, `*-redis-url` secrets, peering plumbing.
- **Permanent old-project deletion is BLOCKED BY `BILLING_DISABLED`** — GCP rejects mutations on billing-closed projects; not deleted, not completed. Nothing bills while billing stays closed.

## Reference — still accurate

| Area | Doc(s) |
|---|---|
| API contracts | [`api/api-contract.md`](api/api-contract.md), [`api/ride-api.md`](api/ride-api.md), [`api/error-codes.md`](api/error-codes.md), [`architecture/API_CONTRACT_INDEX.md`](architecture/API_CONTRACT_INDEX.md) |
| Data model | [`database/firestore-schema.md`](database/firestore-schema.md), [`database/realtime-schema.md`](database/realtime-schema.md), [`database/indexes.md`](database/indexes.md) |
| Security | [`ORA_SECURITY_MODEL.md`](ORA_SECURITY_MODEL.md), [`security/security-model.md`](security/security-model.md), [`security/threat-model.md`](security/threat-model.md), [`security/authorization-matrix.md`](security/authorization-matrix.md), [`security/abuse-prevention.md`](security/abuse-prevention.md) |
| State machines | [`ORA_STATE_MACHINE.md`](ORA_STATE_MACHINE.md), [`architecture-final/03-state-machines.md`](architecture-final/03-state-machines.md) |
| Location pipeline | [`architecture/N_LOCATION_FLOW.md`](architecture/N_LOCATION_FLOW.md), [`architecture-final/10-location-architecture.md`](architecture-final/10-location-architecture.md) |
| Operations | [`operations/production-remote-backend.md`](operations/production-remote-backend.md), [`operations/production-mobile-release.md`](operations/production-mobile-release.md), [`operations/disaster-recovery.md`](operations/disaster-recovery.md), [`operations/observability.md`](operations/observability.md) |
| Testing | [`ANYWHERE_TESTING.md`](ANYWHERE_TESTING.md), [`testing/test-strategy.md`](testing/test-strategy.md), [`testing/race-condition-tests.md`](testing/race-condition-tests.md), [`diagnostics/`](diagnostics/) |
| Performance | [`ORA_LATENCY_SLO.md`](ORA_LATENCY_SLO.md), [`performance/performance-budget.md`](performance/performance-budget.md) |
| Setup | [`implementation/firebase-native-setup.md`](implementation/firebase-native-setup.md), [`implementation/dev-otp-test-numbers.md`](implementation/dev-otp-test-numbers.md) |

## Historical — preserved, do not treat as current

| Doc/dir | Why kept |
|---|---|
| `architecture-final/` (25 docs) | Canonical design-phase architecture set — mostly still accurate in intent; runtime details may drift from code |
| `architecture-review/` | Audit-phase review docs (invariants, cost model, idempotency matrix) |
| `architecture/` | Earlier topical architecture docs — superseded where they conflict with `architecture-final/` or current code |
| `implementation/` (76 phase docs) | Phase-by-phase build record — historical proof of work |
| [`database/redis-schema.md`](database/redis-schema.md) | **SUPERSEDED** — Redis design history only, clearly bannered |
| `audits/ORA_COMPLETE_ARCHITECTURE_AUDIT.md`, `ORA_MASTER_ROADMAP_AUDIT.md`, `ORA_COST_OPTIMIZATION_PLAN.md` | Earlier audit passes — superseded by `ORA_ARCHITECTURE_COST_AUDIT.md` |
| `design/`, `product/`, `algorithms/` | Design rationale & product specs — reference only |

Root `../MIGRATION_NOTES.md` — Firebase/GCP migration record (`ora-app-d8112` → `oraapp-a9be5`).
