# ORA Admin Platform — Master Plan

**Status:** Reconciled architecture-lock candidate — 2026-11-24 — **D-01 APPROVED** — planning only, implementation NOT started
**Scope:** centralized administrative platform for the Ora backend. Entry point; detail lives in supporting docs.

---

## Supporting documents

| Document | Contents |
|---|---|
| [ORA_ADMIN_WORKFLOW_DISCOVERY.md](ORA_ADMIN_WORKFLOW_DISCOVERY.md) | Evidence-based inventory (Implemented/Partial/Planned/Missing) with file citations — reconciled against source |
| [ORA_ADMIN_BACKEND_ARCHITECTURE.md](ORA_ADMIN_BACKEND_ARCHITECTURE.md) | Placement, admin identity (`adminOperators`-only), authN/Z, service layer, audit, step-up (`auth_time`), suspension semantics (verified) |
| [ORA_ADMIN_DATA_MODEL.md](ORA_ADMIN_DATA_MODEL.md) | New/modified collections, two-field driver status ownership, indexes, migrations |
| [ORA_ADMIN_API_SPECIFICATION.md](ORA_ADMIN_API_SPECIFICATION.md) | Endpoint catalog: permissions, `expectedApplicationVersion`, step-up markers, errors, idempotency, audit |
| [ORA_ADMIN_RBAC_PERMISSION_MATRIX.md](ORA_ADMIN_RBAC_PERMISSION_MATRIX.md) | Six proposed roles, granular permissions (no wildcards), enforcement rules |
| [ORA_ADMIN_SECURITY_AUDIT.md](ORA_ADMIN_SECURITY_AUDIT.md) | Threat model, controls, auditability, data protection, honest App Check status |
| [ORA_ADMIN_DASHBOARD_METRICS.md](ORA_ADMIN_DASHBOARD_METRICS.md) | Metric catalog, live-vs-aggregate separation, online-driver freshness semantics, cost honesty |
| [ORA_ADMIN_FRONTEND_SCREEN_INVENTORY.md](ORA_ADMIN_FRONTEND_SCREEN_INVENTORY.md) | Functional screens → backend capabilities (no UI design) |
| [ORA_ADMIN_DECISION_REGISTER.md](ORA_ADMIN_DECISION_REGISTER.md) | All decisions classified: CONFIRMED / PROPOSED / DEFERRED / N/A |

---

## 1. Executive summary

Ora's backend (`ora-auth-service`, Express modular monolith on Cloud Run + Firestore/RTDB + FCM outbox) has a mature server-authoritative domain — rides, offers, dispatch waves, geo, pricing, courier v2 — but **zero administrative surface**. No admin identity is assigned anywhere, no admin endpoint exists, and every privileged mutation today requires Firebase Console or ops scripts.

The enforcement half already exists: `users.isActive`, `users.banned`, `users.driverStatus`, and `drivers.availabilityState` gate every *new-work* path (verified in `nearby_service.ts`, `ride_service.ts` offer/invite/select, `location_update_service.ts`, `driver_availability_service.ts`). **Verified:** ride progression (`progressAssignedRide`) does not re-check `driverStatus`, so suspension blocks new work without stranding in-flight trips.

**Confirmed product requirements driving this plan:** manual driver approval before activation; one active ride per passenger (DR-008 — approved, backend enforcement pending); no paid Firebase Storage — KYC is text-based in V1.

**Approved architecture (D-01, 2026-11-24):** `/v1/admin` router inside the existing Cloud Run service; admin identity solely in `adminOperators/{uid}` (independent of `users.role` — no `users.role='admin'` authorization); granular server-side permissions across six proposed roles; append-only `adminAuditLogs`; cursor-paginated APIs; `auth_time` step-up for destructive ops; cached dashboard aggregates; separate admin web app later (D-15 pending).

---

## 2. What Ora already supports (admin builds on)

- Full ride state machine (14 states), transactional transitions, idempotency, outbox events
- N4 dispatch waves + offer marketplace + passenger select-offer assignment
- Driver onboarding form (CNIC/license/vehicle text validation) with auto-approve
- Driver availability lifecycle with geo projection cleanup
- Eligibility gates enforcing `driverStatus==='approved'`, `isActive`, `banned` on all new-work paths
- **Verified:** in-flight ride progression is exempt from `driverStatus` re-checks (suspension-safe)
- Ratings (stars), courier v2, fare engine + pricing snapshots + fee-policy payout snapshots
- FCM notification pipeline (durable outbox → projectors → sweeps)
- Fail-closed Firestore rules reserving `adminAuditLogs`, `moderationCases`, `reports`, `supportTickets`, `disputes`, payment collections
- `/v1/internal` worker-token pattern + Cloud Scheduler — template for admin aggregation

## 3. What is missing (admin must create)

- Admin identity/authorization (`adminOperators` + permission enforcement)
- Admin audit logging (collection reserved, no writers)
- Driver review workflow (approve/reject/request-info/reopen/resubmit) with `expectedApplicationVersion` stale-review protection
- Suspension/reactivation/ban/deactivate write paths
- Cross-user read APIs (ride/user/driver search — existing lists are owner-scoped)
- Admin ride force-cancel
- Driver-facing application-status endpoint (reliable, push-independent)
- Admin notes (`adminUserNotes`)
- Category management (hardcoded const + script-seeded pricing today)
- Dashboard metrics aggregation
- Step-up auth (`auth_time` freshness)

## 4. Deferred / not in V1

| Item | Why |
|---|---|
| KYC document **images** (upload + preview) | Paid Firebase Storage NOT approved; V1 = text KYC fields + manual review |
| Vendor backend + vendor admin | Marketplace Step 3+ not approved; APIs specified, build later |
| Bulk actions | Mass-action abuse risk; single-target only |
| Payments/finance write ops, refunds, payouts | Payments unimplemented |
| Broadcast/push notifications to users | Phase 2 (outbox extension); driver status works without push |
| Reports/moderation/support tickets | Product features don't exist yet |
| Driver location access/history | Privacy; nothing persisted anyway |
| MFA | Firebase MFA not implemented — separate future decision |
| Hard account deletion | Soft-deactivate + future anonymization only |
| Real-time dashboards, fuzzy search, manual dispatch, fare edits | Out of scope / cost / invariant risk |

## 5. Reusable vs new backend services

**Reuse:** `createAuthMiddleware`, `createRateLimiter`, `sendApiError`/`logSafe`/`getRequestId`, `DriverAvailabilityService` (offline/geo cleanup), eligibility gates, `RideService` internals, outbox publisher + FCM projectors, `idempotencyRecords`, `CityCatalogService`/`pricing_rules_repository` shapes, `/v1/internal` worker pattern.

**Refactor (approved — D-03):** extract driver lifecycle transitions into shared `src/drivers/driver_lifecycle.ts` (self-onboarding + admin review, one code path; constraints in Decision Register).

**New:** `src/admin/` (middleware, permissions catalog, per-module services, audit writer, aggregator); `/v1/internal/admin/aggregate`; `GET /v1/drivers/application-status`; collections `adminOperators`, `adminAuditLogs`, `adminUserNotes`, `categories`, `adminMetrics`, `adminAnnouncements`(P2), `platformConfig`(P2).

## 6. Admin modules & priority

| Phase | Module | Depends on |
|---|---|---|
| **P0 — foundation** | `adminOperators`, admin authN/Z middleware, permission catalog, `adminAuditLogs`, `/v1/admin/me`, step-up | nothing |
| **P1 — core ops (V1)** | User mgmt (search/detail/suspend/ban/deactivate/notes), driver review queue + decisions + resubmit, driver suspend/reactivate/force-offline/directory, ride search/detail/force-cancel/active-monitor, driver-facing `application-status`, audit log viewer | P0; **`DRIVER_AUTO_APPROVE=false` only after review workflow deployed+tested** |
| **P2 — config & insights** | Categories CRUD, pricing rules, fee policies, cities, delivery config; dashboard summary/timeseries/operations; admin notes UI; announcements (optional) | P0 |
| **P3 — marketplace** ✅ spec approved (D-02) | Vendor applications/360/directory/actions | **Entry criteria:** Marketplace backend formally approved; `vendors/*` collections + status machine implemented; vendor role model finalized (not `users.role`); document-storage strategy resolved; vendor permissions granted. Reuses Marketplace vendor status machine as single source of truth — no parallel lifecycle |
| **P4 — trust & safety** | Dispute resolution, reports, moderation, broadcast | Disputes exist; reports/moderation need product features |
| **P5 — KYC documents** | Image upload + verification + previews | **D-04 Option A approved — deferred**; Option B (Firebase Storage) only with explicit future billing approval; must satisfy approved constraints (access controls, audited previews, validation, retention/deletion w/ D-10, cost ceiling, billing alerts) |
| **P6 — financial** | Fee-policy writes, payout/refund oversight, financial dashboards | Payments implementation |

## 7. Key workflows (summary)

- **Driver application:** submit → `drivers.driverStatus=pending` (+`applicationVersion=1`) → queue → `under_review` (optional claim) → `approve` (both status fields → approved, `users.role='driver'`, `driverApprovalSource='admin'`) | `reject` (mandatory reason → `rejected`, `users.driverStatus='none'`, resubmit allowed) | `request-info` (`info_requested` + note → driver sees via `application-status`). All mutations require `expectedApplicationVersion`; 409 `STALE_APPLICATION_VERSION` on conflict.
- **Driver suspension:** both status fields → `suspended` + force offline via availability path (geo cleanup) → new work blocked instantly → **in-flight ride completes normally** (verified) → force-cancel available as escape hatch → audited + optional push later.
- **Account actions:** suspend (`isActive=false`) / reactivate / ban (`banned=true`+reason, step-up) / deactivate (soft, step-up). Never interchangeable; self/admin targets denied; active-ride acknowledgment required.
- **Ride force-cancel:** non-terminal only, courier custody respected (`CUSTODY_LOCKED`), emits normal cancel outbox events, `cancelledBy='admin'` + `adminIntervention` recorded.

## 8. Security posture

Backend-enforced RBAC (six proposed roles, granular permissions, no wildcards), `adminOperators`-only identity independent of `users.role`, no self-escalation/admin-targeting, `auth_time` step-up (proposed 300s) on destructive ops, masked PII with audited unmask, append-only field-level-diff audit on every mutation, mandatory idempotency + `expectedApplicationVersion`, no bulk actions, fail-closed everywhere. Full threat model: security doc.

## 9. Cost & performance

- **Infrastructure:** ~$0 incremental — same Cloud Run service, same Firestore, existing scheduler pattern. **No new paid services in V1** (Storage/KYC deferred per confirmed constraint).
- **Query discipline:** cursor pagination, indexed filters, bounded `count()` for queues (ESTIMATE ≤ ~50 index reads/dashboard load — not free, monitored), 15-min window-bounded aggregation into `adminMetrics`, no collection scans, no listeners.
- **Watch-items:** `adminAuditLogs`/`adminUserNotes` growth; `count()` cost as `users`/`rides` grow (revisit with maintained counters if needed).

## 10. Rollout sequence (safe order)

1. **Approve remaining decision register items** (D-01, D-02, D-03 approved; still pending: D-05–D-25 as listed).
2. Implement P0: `adminOperators` + bootstrap script + middleware + audit + permissions.
3. Implement P1 read APIs → review decisions → suspension → force-cancel → driver-facing status endpoint.
4. **Staging test:** full review workflow, suspension mid-ride test, stale-review conflict test, step-up flow.
5. **Only then** set `DRIVER_AUTO_APPROVE=false` in production (confirmed requirement — never flip before review path is live and proven).
6. P2 config + dashboard; P3+ per approvals.

## 11. Decisions awaiting approval

25 entries in the register. Confirmed already: **D-01** (same-service `/v1/admin`); **D-02** (vendor spec now, build Phase 3, marketplace SoT); **D-03** (shared `driver_lifecycle.ts` — approved with constraints); manual driver approval; one-active-ride (DR-008); **D-04** (Option A — KYC images deferred for V1, text-only, no paid Storage/Blaze); **D-05** (Option A — App Check deferred for `/v1/admin`; namespace scoping to verify before implementation; mobile enforcement untouched); `expectedApplicationVersion`; `auth_time` mechanism. **Awaiting:** D-06 SoD, D-07 audit export, D-08 bulk, D-09 threshold+op list, D-10 deletion, D-11 status model, D-12 notes, D-13 ride interventions, D-14 location, D-15 admin app, D-16 resubmission, D-17 notifications, D-18 config writes, D-19 categories, D-20 finance scope, D-21 retention, D-22 aggregation budget, D-23 status endpoint, D-24 admin auth method.

## 12. Unverifiable / open items (honest list)

- Whether `driverStatus` check absence in progression is *intentional* long-term — verified as current behavior; admin plan relies on it but product should confirm suspension-mid-ride policy explicitly.
- Courier custody boundary for admin force-cancel (`v2HasCustody` internals) — must be verified at implementation.
- Actual Firestore read costs — all cost figures are ESTIMATEs pending billing data.
- Whether staging/prod Firebase Auth supports the chosen admin sign-in method (phone OTP vs email) — console check needed (D-24).
- `users.driverStatus='pending'` semantic during review — proposed mapping in Data Model §2.2 needs product sign-off (D-11).

## 13. What was NOT done

- No application code, tests, config, env files, dependencies, rules, indexes, migrations, infrastructure, or deployments touched.
- Only the 10 existing `docs/admin/*.md` files modified (plus this reconciliation).
- No commits, merges, pushes, or git state changes.
- No frontend screens/components/design produced.

---

## ARCHITECTURE LOCK READINESS

**READY FOR USER APPROVAL**

The 10 documents are now internally consistent and reconciled against verified source code. All reconciliation items A–O are resolved in the docs. Remaining blockers are **user decisions** (25 proposed items in the decision register), not documentation inconsistencies. Two implementation-time verifications are flagged (§12) but do not block approval of the architecture.
