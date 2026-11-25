# ORA Admin Platform — API Specification

**Status:** DRAFT for review — reconciled 2026-11-24
**Placement: APPROVED (D-01)** — dedicated admin module inside the existing `ora-auth-service` Cloud Run service; no separate admin backend.
**Base path:** `/v1/admin` on `ora-auth-service` (Cloud Run), plus one driver-facing endpoint under `/v1/drivers`.
**Conventions:** all `/v1/admin` endpoints require `Authorization: Bearer <Firebase ID token>` + `requireAdmin` + `requirePermission('<perm>')`. Mutations require `Idempotency-Key`. Errors: `{error:{code,message}, requestId}`. Lists cursor-paginated (`?cursor=&limit=`, default 25, max 100). Money in integer minor units + `currency`.

Permission names reference `ORA_ADMIN_RBAC_PERMISSION_MATRIX.md`. Audit events reference `adminAuditLogs.action`.

**Step-up convention:** endpoints marked ⬆ require `requireStepUp` — the request's Firebase ID token must have `auth_time` within the approved freshness threshold (**proposed: 300s — D-09 awaiting approval**). Failure → 403 `STEP_UP_REQUIRED`.

---

## 0. Driver-facing endpoint (non-admin — serves requirement J)

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/v1/drivers/application-status` | Firebase token (any driver applicant) | Returns the caller's own application review state — see §3.4 schema. Reliable status channel independent of push. |

---

## 1. Auth & session

| Method | Path | Permission | Purpose |
|---|---|---|---|
| GET | `/v1/admin/me` | `admin.access` | Caller admin profile: uid, role, effective permissions, status, `authTime`. Admin web bootstrap. |

Response: `{data:{uid, displayName, role, permissions[], status, mfaEnrolled:false}}`
Errors: 401, 403 `ADMIN_ACCESS_DENIED`/`PERMISSION_DENIED`.
Audit: none (own-profile read).

| Method | Path | Permission | Purpose | Audit |
|---|---|---|---|---|
| GET | `/v1/admin/operators` | `operators.read` | List operators | — |
| POST | `/v1/admin/operators` ⬆ | `operators.write` | Create grant `{uid, role, permissions?, status, notes?}`. Cannot grant permissions caller lacks; cannot create self-grant beyond own perms; target must not already be operator (409). Idempotent. | `operator.create` |
| PATCH | `/v1/admin/operators/:uid` ⬆ | `operators.write` | Update role/permissions/status. **Cannot modify self.** Idempotent. | `operator.update` (records permission diff) |
| POST | `/v1/admin/operators/:uid/disable` ⬆ | `operators.write` | Revoke (status→disabled). Cannot disable self or last active super_admin (409 `LAST_SUPER_ADMIN`). | `operator.disable` |

---

## 2. User & account management

### 2.1 Search & read

| Method | Path | Permission | Purpose |
|---|---|---|---|
| GET | `/v1/admin/users` | `users.read` | Search/filter: `q` (phone/uid exact, displayName prefix), `role`, `driverStatus`, `isActive`, `banned`, `registeredAfter/Before`, cursor/limit. PII masked unless `users.read_pii`. |
| GET | `/v1/admin/users/:uid` | `users.read` | User 360: profile + linked driver summary + counts + notes list. Sensitive fields need `users.read_pii` → audit `user.view_sensitive`. |
| GET | `/v1/admin/users/:uid/rides` | `users.read` | Passenger ride history (cursor). |
| GET | `/v1/admin/users/:uid/activity` | `users.read` | Timeline: registration, mode switches, status changes, admin actions on this user (from `adminAuditLogs`), bounded 90d default. |

### 2.2 Account actions

| Method | Path | Permission | Step-up | Request | Audit |
|---|---|---|---|---|---|
| POST | `/v1/admin/users/:uid/suspend` | `users.suspend` | — | `{reason, suspendedUntil?, alsoDriver?}` | `user.suspend` |
| POST | `/v1/admin/users/:uid/reactivate` | `users.suspend` | — | `{reason?}` | `user.reactivate` |
| POST | `/v1/admin/users/:uid/ban` ⬆ | `users.ban` | ✓ | `{reason}` required ≥10 chars | `user.ban` |
| POST | `/v1/admin/users/:uid/unban` | `users.ban` | — | `{reason?}` | `user.unban` |
| POST | `/v1/admin/users/:uid/deactivate` ⬆ | `users.deactivate` | ✓ | `{reason}` required; sets `deactivatedAt/By/Reason`, `isActive=false`. **No hard delete.** | `user.deactivate` |
| POST | `/v1/admin/users/:uid/notes` | `users.write` | — | `{body}` ≤2000 chars → `adminUserNotes` | `note.add` |

**Rules (all account actions):**
- Target must exist; cannot target own uid or any `adminOperators` uid → 403 `CANNOT_TARGET_ADMIN`/`SELF_ACTION_DENIED`.
- Cannot ban/deactivate a user with an in-flight assigned ride unless `acknowledgeActiveRide:true` — dry-run returns 409 `ACTIVE_RIDE_CONFLICT` with `activeRideId`.
- Suspend/reactivate idempotent state-sets (`unchanged:true` on no-op).
- All mutations: `Idempotency-Key` required, transaction, audit.
- v1 sends no user-facing push on account actions (app's existing `ACCOUNT_DISABLED` handling covers discovery); optional notify is Phase 2 (D-17).

---

## 3. Driver management

### 3.1 Application review queue

| Method | Path | Permission | Purpose |
|---|---|---|---|
| GET | `/v1/admin/drivers/applications` | `drivers.review.read` | Queue: `drivers.driverStatus IN (pending, under_review, info_requested)` ordered by `onboardingSubmittedAt` asc + aging. Cursor paginated. |
| GET | `/v1/admin/drivers/applications/:driverId` | `drivers.review.read` (+`drivers.review.pii` for doc numbers) | Full application: user profile, drivers doc (`fullName, homeCity, vehicle{}, documents{cnicNumber, licenseNumber, licenseExpiry}`, `applicationVersion`, review fields). Audit `driver.application.view` (+`_sensitive` when PII). |
| GET | `/v1/admin/drivers/:driverId` | `drivers.read` | Driver 360: profile + status + availability + vehicle + stats + activeRideId + review/suspension metadata + notes. |
| GET | `/v1/admin/drivers` | `drivers.read` | Directory: filters `driverStatus`, `availabilityState`, `homeCity`, `category`, `q`. |

### 3.2 Review decisions — stale-review protected

All review mutations execute through the **approved shared lifecycle module** (`src/drivers/driver_lifecycle.ts`, D-03) — the same transition/business-rule layer used by self-service onboarding. Admin authorization and audit remain in the Admin layer; these Admin-only transitions are never exposed to mobile callers. All mutations run in Firestore transactions updating `users.driverStatus` and `drivers.driverStatus` atomically.

All four mutations require body field **`expectedApplicationVersion`** (integer ≥1, from the application detail response). Transaction validates `drivers.applicationVersion === expectedApplicationVersion` AND current status is an allowed source state; mismatch → **409 `STALE_APPLICATION_VERSION`** (version conflict — refetch and retry) or **409 `STATE_CONFLICT`** (wrong status). This prevents two reviewers silently overwriting each other.

| Method | Path | Permission | Step-up | Request | Effect | Audit |
|---|---|---|---|---|---|---|
| POST | `/v1/admin/drivers/applications/:driverId/approve` | `drivers.approve` | — | `{expectedApplicationVersion, note?}` | `drivers.driverStatus='approved'`, `approvedBy/At`, `users.driverStatus='approved'`, `users.role='driver'`, `driverApprovalSource='admin'` | `driver.approve` |
| POST | `/v1/admin/drivers/applications/:driverId/reject` | `drivers.reject` | — | `{expectedApplicationVersion, reason}` reason required | `drivers.driverStatus='rejected'`, `rejectionReason`, `reviewedBy/At`; `users.driverStatus='none'`; `canResubmit=true` | `driver.reject` |
| POST | `/v1/admin/drivers/applications/:driverId/request-info` | `drivers.review` | — | `{expectedApplicationVersion, note}` required | `drivers.driverStatus='info_requested'`, `infoRequestNote`, `infoRequestedAt`; `users.driverStatus='pending'` | `driver.request_info` |
| POST | `/v1/admin/drivers/applications/:driverId/reopen` | `drivers.review` | — | `{expectedApplicationVersion, note?}` | `rejected\|info_requested → pending` (re-review queue) | `driver.reopen` |

**Transition legality:** approve from `pending|under_review|info_requested`; reject from `pending|under_review|info_requested`; request-info from `pending|under_review`; reopen from `rejected|info_requested`. Self-review denied: operator cannot review own uid → 403 `SELF_ACTION_DENIED`.

**Resubmission (driver side):** driver calls `POST /v1/drivers/onboarding` again after rejection/info-request → `applicationVersion++`, `drivers.driverStatus='pending'`, `users.driverStatus='pending'`, review fields cleared. (Requires onboarding service change to allow resubmit from `rejected`/`info_requested` — implementation item.)

### 3.3 Active driver management

| Method | Path | Permission | Step-up | Purpose | Audit |
|---|---|---|---|---|---|
| POST | `/v1/admin/drivers/:driverId/suspend` ⬆ | `drivers.suspend` | ✓ | `{reason, suspendedUntil?}` — both status fields → `suspended`, force offline via availability path (geo cleanup), `suspendedBy/At`. Active ride NOT interrupted (verified: progression doesn't recheck driverStatus). | `driver.suspend` |
| POST | `/v1/admin/drivers/:driverId/reactivate` | `drivers.suspend` | — | `{reason?}` → `driverStatus='approved'` both fields; driver goes online manually. | `driver.reactivate` |
| POST | `/v1/admin/drivers/:driverId/force-offline` | `drivers.suspend` | — | Online driver → offline without status change (reuses goOffline path). | `driver.force_offline` |
| PATCH | `/v1/admin/drivers/:driverId` | `drivers.write` | — | Operational fields only: `homeCity`, `vehicle.category` (validated vs `categories`), `preferredCategories`. NOT identity/doc fields. | `driver.update` |
| GET | `/v1/admin/drivers/:driverId/rides` | `drivers.read` | — | Ride history, cursor. | — |
| GET | `/v1/admin/drivers/:driverId/ratings` | `drivers.read` | — | Ratings received. | — |

### 3.4 Driver-facing application status (requirement J)

`GET /v1/drivers/application-status` (any authenticated user; returns own data only):

```json
{ "data": {
    "applicationStatus": "none|pending|under_review|info_requested|approved|rejected|suspended",
    "capabilityStatus": "none|pending|approved|suspended",
    "infoRequestNote": "string|null",
    "rejectionReason": "string|null",
    "applicationVersion": 3,
    "submittedAt": "iso|null", "reviewedAt": "iso|null",
    "canResubmit": true,
    "nextAction": "wait|update_info|resubmit|contact_support|go_online" } }
```

Mobile driver registration/status screens render from this — **push is supplementary, never the only channel**.

---

## 4. Ride operations

| Method | Path | Permission | Step-up | Purpose | Audit |
|---|---|---|---|---|---|
| GET | `/v1/admin/rides` | `rides.read` | — | Cross-user search: `state`, `serviceType`, `category`, `city`, `passengerId`, `driverId`, date range, fare range. Cursor. PII masked unless `rides.read_pii`. |
| GET | `/v1/admin/rides/:rideId` | `rides.read` | — | Detail: ride doc + `rideEvents` timeline + offers + dispatch waves + settlement/dispute. PII gated → `ride.view_sensitive`. |
| GET | `/v1/admin/rides/active` | `rides.read` | — | Non-terminal rides with age/city/category — ops monitor. |
| POST | `/v1/admin/rides/:rideId/force-cancel` ⬆ | `rides.cancel` | ✓ | `{reason}` required. Terminal states rejected (409); courier custody respected (parcel in transit → 409 `CUSTODY_LOCKED`). Emits normal cancel outbox events; `cancelledBy='admin'` + `adminIntervention` set. | `ride.force_cancel` |

**NOT provided (V1):** manual driver assignment, dispatch override, fare edits, state time-travel (D-13).

---

## 5. Categories & service config

| Method | Path | Permission | Step-up | Purpose | Audit |
|---|---|---|---|---|---|
| GET | `/v1/admin/categories` | `config.read` | — | List (`?kind=&active=`). | — |
| POST | `/v1/admin/categories` | `config.write` | — | Create `{categoryId, displayName, kind, description?, sortOrder?, iconRef?}`; slug-validated unique. | `category.create` |
| PATCH | `/v1/admin/categories/:id` | `config.write` | — | Update display/desc/sort/active/icon. `categoryId`/`kind` immutable; deactivation non-destructive. | `category.update` |
| GET | `/v1/admin/pricing-rules` | `config.read` | — | List `pricingRules`. | — |
| PUT | `/v1/admin/pricing-rules/:city/:category` | `config.write` | — | Validated upsert; bumps `version`, sets `updatedBy`; affects new estimates only. | `config.pricing_rule.upsert` |
| GET/PUT | `/v1/admin/fee-policies` | `config.read` / `config.write` | PUT ⬆ | Manage `feePolicies`; amounts visible with `finance.read`. New snapshots only. | `config.fee_policy.upsert` |
| GET/PUT | `/v1/admin/cities` | `config.read` / `config.write` | PUT ⬆ | City activate/deactivate/displayName via `CityCatalogService` patterns. Bulk import stays script-gated. | `config.city.upsert` |
| GET/PUT | `/v1/admin/delivery-config` | `config.read` / `config.write` | PUT ⬆ | Courier limits, dispute window, feature toggles. | `config.delivery.upsert` |

All config writes versioned/non-destructive; audit stores before/after diff (masked).

---

## 6. Admin notes

| Method | Path | Permission | Purpose | Audit |
|---|---|---|---|---|
| GET | `/v1/admin/users/:uid/notes` | `users.read` | List notes for user (also embedded in user 360). | — |
| POST | `/v1/admin/users/:uid/notes` | `users.write` | Add note → `adminUserNotes` (append-only). | `note.add` |
| GET | `/v1/admin/drivers/:driverId/notes` | `drivers.read` | List notes for driver. | — |
| POST | `/v1/admin/drivers/:driverId/notes` | `drivers.write` | Add note. | `note.add` |

Notes never exposed to user-facing app; bodies not copied into audit log.

---

## 7. Disputes, reports & moderation

| Method | Path | Permission | Step-up | Purpose | Audit |
|---|---|---|---|---|---|
| GET | `/v1/admin/disputes` | `disputes.read` | — | Open queue, filters category/rideId. | — |
| GET | `/v1/admin/disputes/:id` | `disputes.read` | — | Detail + ride context + parties (PII gated). | `dispute.view` |
| POST | `/v1/admin/disputes/:id/resolve` ⬆ | `disputes.write` | ✓ | `{resolution:'resolved'\|'dismissed', note, actionTaken?}` from `OPEN` only → status + `resolvedBy/At` + outbox notify. | `dispute.resolve` |
| GET | `/v1/admin/reports` | `reports.read` | — | Reports queue — **Phase 3+, requires reports feature to exist**. | — |
| POST | `/v1/admin/reports/:id/action` | `reports.write` | — | Mark reviewed/action/dismiss — Phase 3+. | `report.action` |

### Vendor management — ⏸ DEFERRED (Phase 3; spec approved via D-02, NOT V1-ready)

**Status:** planned/deferred. No vendor backend exists; endpoints below are the agreed shape and **must be implemented against the Marketplace vendor model as single source of truth** (`vendors/{uid}_{kind}`, `kind ∈ rental|service|logistics`, `status ∈ pending|under_review|info_requested|approved|rejected|suspended` per `docs/implementation/marketplace/ORA_MARKETPLACE_AUDIT_AND_PLAN.md` §2.2). Admin must NOT invent a parallel vendor lifecycle. All review mutations carry `expectedApplicationVersion` (or the marketplace equivalent version field) once that model lands.

| Method | Path | Permission | Purpose |
|---|---|---|---|
| GET | `/v1/admin/vendors/applications` | `vendors.review.read` | Vendor review queue (marketplace status machine) |
| GET | `/v1/admin/vendors/applications/:vendorId` | `vendors.review.read` (+`vendors.review.pii`) | Full application: business profile, owner/contact, documents |
| POST | `/v1/admin/vendors/applications/:vendorId/approve` | `vendors.approve` | Approve — marketplace transition rules |
| POST | `/v1/admin/vendors/applications/:vendorId/reject` | `vendors.reject` | Reject — mandatory reason |
| POST | `/v1/admin/vendors/applications/:vendorId/request-info` | `vendors.review` | Request additional information |
| POST | `/v1/admin/vendors/applications/:vendorId/reopen` | `vendors.review` | Reopen rejected/info-requested |
| GET | `/v1/admin/vendors` | `vendors.read` | Vendor directory (kind/status/city filters) |
| GET | `/v1/admin/vendors/:vendorId` | `vendors.read` | Vendor 360: profile, listings, status, stats |
| POST | `/v1/admin/vendors/:vendorId/suspend` | `vendors.suspend` | Suspend (step-up ⬆ when implemented) |
| POST | `/v1/admin/vendors/:vendorId/reactivate` | `vendors.suspend` | Reactivate |
| PATCH | `/v1/admin/vendors/:vendorId` | `vendors.write` | Operational fields only (not identity/docs) |
| GET | `/v1/admin/vendors/:vendorId/notes` + POST | `vendors.read` / `vendors.write` | Internal notes via `adminUserNotes` (targetType `vendor`) |

**Entry criteria (all required before build):** Marketplace backend formally approved; `vendors/*` collections + lifecycle implemented; vendor role model finalized (vendor roles NOT in `users.role`); document-storage strategy resolved per **D-04 Option A (approved — text-only V1; images deferred, Option B conditional on billing approval)**; vendor KYC follows the same deferral; operator vendor permissions (`vendors.read`, `vendors.review.read`, `vendors.review.pii`, `vendors.approve`, `vendors.reject`, `vendors.review`, `vendors.suspend`, `vendors.write`) granted.

---

## 8. Notifications (Phase 2)

| Method | Path | Permission | Step-up | Purpose | Audit |
|---|---|---|---|---|---|
| POST | `/v1/admin/announcements` | `notifications.write` | — | `{title, body, audience{roles,cities,driverStatus}, channels:['push'], scheduledAt?}` → `adminAnnouncements` + outbox `admin.announcement`. Max 3/day/operator. | `announcement.create` |
| GET | `/v1/admin/announcements` | `notifications.read` | — | List + delivery stats. | — |
| POST | `/v1/admin/announcements/:id/cancel` | `notifications.write` | — | Cancel scheduled/unsent. | `announcement.cancel` |
| POST | `/v1/admin/users/:uid/notify` | `notifications.write` | — | Single-user push `{title, body}`; 5/hour cap; identifiers-only payload pattern. | `notification.send` |

---

## 9. Dashboard & metrics

| Method | Path | Permission | Purpose |
|---|---|---|---|
| GET | `/v1/admin/dashboard/summary` | `dashboard.read` | KPIs: totals, queue depths, today activity — cached aggregates + bounded live `count()` queries. Includes `computedAt` staleness. |
| GET | `/v1/admin/dashboard/timeseries` | `dashboard.read` | `?metric=&from=&to=` daily/monthly rollups; ≤400 days. |
| GET | `/v1/admin/dashboard/operations` | `dashboard.read` | Active rides by state/city, **fresh** online-driver count (see metrics doc §online semantics), outbox backlog, sweep health. |
| GET | `/v1/admin/reports/:report` | `dashboard.read` (+`finance.read` for financial) | Bounded on-demand reports (`driver-performance`, `city-activity`, `cancellation-analysis`); mandatory date range + row cap. |

No write endpoints. All reads bounded/cached per metrics doc.

---

## 10. Audit log access

| Method | Path | Permission | Purpose |
|---|---|---|---|
| GET | `/v1/admin/audit-logs` | `audit.read` | Query by `adminUid`, `action`, `targetType`, `targetId`, `from`, `to`; cursor paginated. Read-only by design — no mutation endpoints exist. |

---

## 11. Admin-specific error codes

| Code | HTTP | Meaning |
|---|---|---|
| `ADMIN_ACCESS_DENIED` | 403 | authenticated but not an active operator |
| `PERMISSION_DENIED` | 403 | operator lacks required permission |
| `STEP_UP_REQUIRED` | 403 | token `auth_time` older than threshold — re-authenticate |
| `CANNOT_TARGET_ADMIN` | 403 | action targets an admin operator account |
| `SELF_ACTION_DENIED` | 403 | operator targeting own uid (e.g. reviewing own driver app) |
| `LAST_SUPER_ADMIN` | 409 | operation would remove final active super_admin |
| `STATE_CONFLICT` | 409 | entity not in required state |
| `STALE_APPLICATION_VERSION` | 409 | `expectedApplicationVersion` mismatch — refetch & retry |
| `IDEMPOTENCY_KEY_REQUIRED` | 400 | missing on mutation |
| `IDEMPOTENCY_CONFLICT` | 409 | key reused with different payload |
| `REASON_REQUIRED` | 400 | mandatory reason empty |
| `ACTIVE_RIDE_CONFLICT` | 409 | target has in-flight ride; needs `acknowledgeActiveRide` |
| `CUSTODY_LOCKED` | 409 | courier parcel in transit — force-cancel forbidden |
| `AUDIT_UNAVAILABLE` | 503 | audit write failed → mutation aborted (fail closed) |

---

## 12. Idempotency & transaction contract (all mutations)

1. `Idempotency-Key` required → `idempotencyRecords` key `admin:{uid}:{key}` + request hash + response snapshot (7-day TTL).
2. Same key + same payload → replay stored response (`Idempotent-Replay: true` header).
3. Same key + different payload → 409 `IDEMPOTENCY_CONFLICT`.
4. State transitions in `runTransaction` with expected-state (+ `applicationVersion` for reviews) checks.
5. Audit write inside/adjacent transaction with same `requestId`; audit failure → abort (`AUDIT_UNAVAILABLE`).
