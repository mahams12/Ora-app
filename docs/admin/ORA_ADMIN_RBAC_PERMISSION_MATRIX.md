# ORA Admin Platform — RBAC & Permission Matrix

**Status:** DRAFT for review — reconciled 2026-11-24
**Principle:** least-privilege; backend-enforced granular permissions; roles are grant-time bundles over explicit permission lists. **No role assignment is approved — all roles/permissions are proposals awaiting user approval.**

---

## 1. Design rationale

Ora today has no admin roles (`users.role` = `passenger|driver|admin`, admin unused). Admin authority lives in `adminOperators/{uid}` — independent of app role (see Architecture §2.1).

**Six proposed roles** (count is authoritative everywhere — super_admin, ops_admin, verification_admin, support_admin, finance_admin, analyst):

| Role | Purpose | Risk level |
|---|---|---|
| `super_admin` | Full access incl. operator management | Highest — bootstrap-only creation, step-up on sensitive ops |
| `ops_admin` | Day-to-day ops: users, drivers, rides, disputes, config-read | High |
| `verification_admin` | Driver (later vendor) application review only | Medium |
| `support_admin` | Read-mostly + notes + dispute viewing | Medium |
| `finance_admin` | Financial/config read + fee policy (mostly future) | High (future) |
| `analyst` | Read-only dashboards & reports | Low |

Permissions are stored explicitly on `adminOperators/{uid}.permissions` (effective set = stored list). Role provides the default bundle at grant time; per-person deviations allowed without inventing roles.

---

## 2. Permission catalog (granular — no wildcards)

Format `<domain>.<action>`, enforced by `requirePermission()` server-side. `*` is not a usable permission string in V1 (super_admin gets the full explicit list resolved at grant time).

### Access & identity

| Permission | Description |
|---|---|
| `admin.access` | Baseline: may hold an active operator record / call `/v1/admin/me` |
| `operators.read` | List/view admin operators |
| `operators.write` | Create/update/disable operator grants |
| `audit.read` | Read `adminAuditLogs` |

### Users

| Permission | Description |
|---|---|
| `users.read` | Search/view profiles (masked PII), ride history, activity, notes |
| `users.read_pii` | Unmask phone/email/identity fields (audited reads) |
| `users.write` | Add internal notes (`adminUserNotes`) |
| `users.suspend` | Suspend/reactivate accounts |
| `users.ban` | Ban/unban accounts |
| `users.deactivate` | Soft-deactivate accounts |

### Drivers

| Permission | Description |
|---|---|
| `drivers.read` | View driver profiles, directory, history, ratings, availability, notes |
| `drivers.review.read` | View application queue + full applications |
| `drivers.review.pii` | View sensitive doc/identity fields (audited) |
| `drivers.approve` | Approve applications |
| `drivers.reject` | Reject applications (reason mandatory) |
| `drivers.review` | Request-info / reopen applications |
| `drivers.suspend` | Suspend/reactivate/force-offline drivers |
| `drivers.write` | Edit operational fields (city, vehicle category, prefs) |

### Rides

| Permission | Description |
|---|---|
| `rides.read` | Search/view rides cross-user (masked) |
| `rides.read_pii` | Unmask party identity on rides (audited) |
| `rides.cancel` | Force-cancel rides (reason mandatory, step-up) |

### Vendors — Phase 3 DEFERRED (spec approved via D-02; permissions granted to operators only when Phase 3 begins; no wildcards)

| Permission | Description |
|---|---|
| `vendors.read` | View vendor profiles/listings |
| `vendors.review.read` | View vendor applications + documents |
| `vendors.review.pii` | View sensitive vendor/business documents (audited) |
| `vendors.approve` | Approve vendor applications |
| `vendors.reject` | Reject vendor applications |
| `vendors.review` | Vendor request-info / reopen |
| `vendors.suspend` | Suspend/reactivate vendors |
| `vendors.write` | Edit vendor operational fields |

### Disputes, reports, moderation

| Permission | Description |
|---|---|
| `disputes.read` | View dispute queue/details |
| `disputes.write` | Resolve/dismiss disputes (step-up) |
| `reports.read` | View user reports queue (Phase 3+) |
| `reports.write` | Action on reports (Phase 3+) |
| `moderation.write` | Content/account moderation actions (Phase 3+) |

### Configuration

| Permission | Description |
|---|---|
| `config.read` | View categories, pricing rules, fee policies, cities, delivery config |
| `config.write` | Modify categories, pricing rules, cities, delivery config (step-up on PUTs) |
| `finance.read` | View financial aggregates, fee policies, payout data (when payments exist) |
| `finance.write` | Modify fee/commission policies (future; step-up) |

### Notifications

| Permission | Description |
|---|---|
| `notifications.read` | View announcements/delivery stats |
| `notifications.write` | Create broadcasts, send single-user notifications |

### Dashboard

| Permission | Description |
|---|---|
| `dashboard.read` | Non-financial summary/timeseries/operations metrics |
| `dashboard.read_financial` | Financial metrics subset |

---

## 3. Role → permission mapping (proposed defaults)

| Permission | super_admin | ops_admin | verification_admin | support_admin | finance_admin | analyst |
|---|:-:|:-:|:-:|:-:|:-:|:-:|
| admin.access | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| operators.read | ✓ | | | | | |
| operators.write | ✓ | | | | | |
| audit.read | ✓ | ✓ | | ✓ | | |
| users.read | ✓ | ✓ | | ✓ | | ✓ |
| users.read_pii | ✓ | ✓ | | per-person* | | |
| users.write | ✓ | ✓ | | ✓ | | |
| users.suspend | ✓ | ✓ | | | | |
| users.ban | ✓ | | | | | |
| users.deactivate | ✓ | ✓ | | | | |
| drivers.read | ✓ | ✓ | ✓ | ✓ | | ✓ |
| drivers.review.read | ✓ | ✓ | ✓ | | | |
| drivers.review.pii | ✓ | | ✓ | | | |
| drivers.approve | ✓ | | ✓ | | | |
| drivers.reject | ✓ | | ✓ | | | |
| drivers.review | ✓ | | ✓ | | | |
| drivers.suspend | ✓ | ✓ | | | | |
| drivers.write | ✓ | ✓ | | | | |
| rides.read | ✓ | ✓ | | ✓ | | ✓ |
| rides.read_pii | ✓ | ✓ | | | | |
| rides.cancel | ✓ | ✓ | | | | |
| disputes.read | ✓ | ✓ | | ✓ | | |
| disputes.write | ✓ | ✓ | | | | |
| vendors.read | ✓ | ✓ | ✓ | ✓ | | |
| vendors.review.read | ✓ | ✓ | ✓ | | | |
| vendors.review.pii | ✓ | | ✓ | | | |
| vendors.approve | ✓ | | ✓ | | | |
| vendors.reject | ✓ | | ✓ | | | |
| vendors.review | ✓ | | ✓ | | | |
| vendors.suspend | ✓ | ✓ | | | | |
| vendors.write | ✓ | ✓ | | | | |
| reports.read | ✓ | ✓ | | ✓ | | |
| reports.write | ✓ | ✓ | | | | |
| moderation.write | ✓ | ✓ | | | | |
| config.read | ✓ | | | | ✓ | ✓ |
| config.write | ✓ | | | | | |
| finance.read | ✓ | | | | ✓ | |
| finance.write | ✓ | | | | | |
| notifications.read | ✓ | ✓ | | | | |
| notifications.write | ✓ | ✓ | | | | |
| dashboard.read | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| dashboard.read_financial | ✓ | | | | ✓ | |

\* `users.read_pii` for support_admin is a **per-person grant**, not a role default — support sees masked PII unless explicitly granted unmask for ticket context.

**Design notes:**
- `verification_admin` approves/rejects but cannot suspend/ban — reviewers don't punish.
- `support_admin` reads + notes + dispute viewing; no destructive account actions.
- `ops_admin` is the workhorse (users/drivers/rides/disputes/config-read).
- `super_admin` adds operator management, ban, config.write, finance.write.
- `finance_admin` mostly future-facing (payments unimplemented); today reads config/fee policies.
- `analyst` pure read.

---

## 4. Enforcement rules (all backend-side)

1. **`requirePermission()` on every `/v1/admin` route** — no route relies on frontend visibility. Contract test enumerates routes and asserts middleware presence.
2. **Fail closed:** missing operator doc, suspended/disabled status, banned user, unknown permission string → 403.
3. **No self-escalation:** cannot edit own `adminOperators` doc; cannot grant permissions you lack; cannot create an operator with permissions exceeding your own (except bootstrap script which bypasses by design — audited).
4. **Cannot target admins** via user/driver/ride/note endpoints → `CANNOT_TARGET_ADMIN`; self-targeting → `SELF_ACTION_DENIED` (e.g. operator reviewing own driver application).
5. **Grant/revoke authority:** `operators.write` only (super_admin bundle) + bootstrap script for first super_admin. **No self-service, no delegation chains in V1.**
6. **Step-up:** destructive/high-risk permissions additionally require fresh `auth_time` (see API spec ⬆ markers + Architecture §7).
7. **Sensitive permissions are audited on use:** `users.read_pii`, `drivers.review.pii`, `rides.read_pii`, document previews → read-audit entries, not just mutations.
8. **Every mutation:** permission + validation + idempotency + reason (where required) + transaction + audit record. Audit failure aborts the mutation.
9. **Rate limits per class:** reads 60/min, mutations 20/min, review decisions 10/min, PII-unmask 30/hour, notify 5/hour per operator (proposals).

---

## 5. Permission change management

- Grant/revoke via `POST/PATCH/disable /v1/admin/operators` — itself step-up + audited (`operator.update` stores permission diff).
- Effective immediately (operator doc re-read per request; optional ≤60s cache — bounded revocation lag, documented).
- Break-glass: ops script disables operator directly; logged to `adminAuditLogs` by convention.
- Quarterly access review recommended (process).
- **Approval gate:** this entire matrix is PROPOSED — no role is assigned to any real person until the user approves the matrix and names initial operators.
