# ORA Admin Platform — Data Model

**Status:** DRAFT for review — reconciled 2026-11-24
**Principles:** no duplicate sources of truth; extend existing collections where they already carry the fields; every new collection is server-only (rules fail closed — add explicit denies for clarity at implementation).

**Status-field ownership (reconciled — requirement B):** two driver status fields with distinct authority:

| Field | Authority | Consumers |
|---|---|---|
| `users/{uid}.driverStatus` ∈ `none\|pending\|approved\|suspended` | **Capability/eligibility flag** — the ONLY field dispatch gates read | `nearby_service`, `ride_service` (offer/invite/select), `location_update_service`, `driver_availability_service`, `eligibility.ts` |
| `drivers/{uid}.driverStatus` ∈ `pending\|under_review\|info_requested\|approved\|rejected\|suspended` | **Review lifecycle** — the ONLY field admin review queues read | admin review queue, driver-facing status endpoint |

The lifecycle module keeps them consistent transactionally: e.g. `approved`↔`approved`, `rejected`/`info_requested`/`under_review`→`users.driverStatus='none'` (or `'pending'` while actively pending — see transition table §2.2), `suspended`↔`suspended`.

---

## 1. New collections

### 1.1 `adminOperators/{uid}` — admin identity, roles, permissions

| Field | Type | Notes |
|---|---|---|
| uid | string | = Firebase Auth uid = doc id |
| displayName | string | For audit display |
| role | string | `super_admin` \| `ops_admin` \| `verification_admin` \| `support_admin` \| `finance_admin` \| `analyst` (6 proposed roles — none approved yet) |
| permissions | string[] | Explicit grant list = effective permission set (role provides defaults at grant time) |
| status | string | `active` \| `suspended` \| `disabled` |
| mfaEnrolled | boolean | Reserved — Firebase MFA not implemented; future use only |
| createdAt / updatedAt | timestamp | Server-managed |
| createdBy | string | uid or `bootstrap-script` |
| notes | string? | Internal only |

- **Indexes:** none (doc-id lookups only).
- **Security:** Admin SDK only; add explicit rules deny for clarity (catch-all already denies).
- **Bootstrap:** ops script creates the doc + Firebase Auth user. **Does NOT touch `users/{uid}.role`** — admin identity is independent of app role. First `super_admin` via script only; subsequent grants via `POST /v1/admin/operators`.
- **Retention:** lifetime of employment + audit retention.

### 1.2 `adminAuditLogs/{autoId}` — append-only admin action log

| Field | Type | Notes |
|---|---|---|
| auditId | string | auto-id |
| adminUid | string | |
| adminRole | string | Role at time of action |
| action | string | `<domain>.<verb>` e.g. `driver.approve` |
| targetType | string | `user` \| `driver` \| `ride` \| `vendor` \| `category` \| `config` \| `operator` \| `note` \| `announcement` |
| targetId | string | |
| previousState | map? | bounded: changed fields only, masked values — never full docs |
| newState | map? | |
| reason | string? | mandatory for destructive/sensitive actions |
| requestId | string | correlation id |
| ipHash | string? | SHA-256 truncated; never raw IP |
| userAgent | string? | truncated 200 chars |
| createdAt | timestamp | server timestamp; immutable |

- **Indexes:** `adminUid + createdAt DESC`; `targetType + targetId + createdAt DESC`; `action + createdAt DESC`; `createdAt DESC`.
- **Security:** write-only from backend; **zero update/delete paths**. Rules already deny clients.
- **Retention (PROPOSED — D-21, awaiting approval):** 7 years hot in Firestore, then archive/export (mechanism deferred). Alternative: indefinite.
- **Read access:** `audit.read` permission only.

### 1.3 Idempotency — reuse `idempotencyRecords`

**No new collection.** Key format `admin:{adminUid}:{clientKey}`; existing 7-day TTL cleanup applies.

### 1.4 `adminUserNotes/{autoId}` — internal admin notes on users/drivers

| Field | Type | Notes |
|---|---|---|
| noteId | string | auto-id |
| targetType | string | `user` \| `driver` |
| targetId | string | uid |
| authorUid | string | admin who wrote it |
| authorRole | string | snapshot |
| body | string | max 2000 chars, plain text |
| createdAt | timestamp | immutable |

- **Indexes:** `targetType + targetId + createdAt DESC`.
- **Access:** read via user/driver 360 endpoints (`users.read`/`drivers.read`); write via `users.write`/`drivers.write` permission. Notes are **internal** — never exposed to the user-facing app.
- **Audit:** note creation logged as `note.add` in `adminAuditLogs` (body NOT copied into audit — PII minimization; audit stores noteId + target only).
- **Retention:** follows account retention; deleted only via account anonymization job (future).
- **Update/delete:** notes are append-only like audit (correction = new note); no edit path in V1.

### 1.5 `categories/{categoryId}` — admin-managed category catalog

| Field | Type | Notes |
|---|---|---|
| categoryId | string | slug; doc id; **immutable once referenced** |
| displayName | string | e.g. "Bike", "AC Sedan" |
| description | string? | |
| kind | string | `vehicle` \| `service` \| `logistics` \| `rental` (extensible) |
| sortOrder | number | |
| active | boolean | `false` = hidden from new selection; **existing references remain valid** |
| iconRef | string? | asset key, not URL |
| pricingKey | string | used in `pricingRules/{city}_{category}` lookups |
| createdAt / updatedAt / updatedBy | — | |

- **Seed/migration:** initial docs mirror the 6 existing slugs (`zip,trio,easy,breeze,premium,executive`) — IDs unchanged → `pricingRules` keys and `rides.category`/`vehicle.category` stay valid.
- **Safety:** `categoryId`/`kind` immutable; deletion forbidden once referenced; deactivation non-destructive.
- **Indexes:** `active + kind`.

### 1.6 `adminMetrics/{periodKey}` — cached dashboard aggregates

| Field | Type | Notes |
|---|---|---|
| periodKey | string | doc id `d:YYYY-MM-DD` \| `m:YYYY-MM` |
| period | string | `day` \| `month` |
| metrics | map | counts + sums per metrics doc |
| computedAt | timestamp | staleness indicator |
| computedBy | string | `aggregator-job` |

- Written only by `/v1/internal/admin/aggregate` worker endpoint (existing scheduler pattern). Read by dashboard API.

### 1.7 `adminAnnouncements/{autoId}` — broadcast messages (Phase 2)

| Field | Type | Notes |
|---|---|---|
| announcementId | string | |
| title / body | string | |
| audience | map | `{roles:[], cities:[], driverStatus:[]}` |
| channels | string[] | `push` v1; `in_app`/`sms` future |
| status | string | `draft` \| `scheduled` \| `sending` \| `sent` \| `failed` |
| scheduledAt / sentAt | timestamp? | |
| createdBy / createdAt | — | |
| deliveryStats | map? | `{targeted, delivered, failed}` |

- Delivery via new outbox event `admin.announcement` + projector extension. Phase 2.

### 1.8 `platformConfig/{key}` — runtime configuration (Phase 2)

| Field | Type | Notes |
|---|---|---|
| key | string | doc id e.g. `featureFlags` |
| value | map | typed per key; server-validated |
| version | number | monotonic |
| updatedBy / updatedAt | — | every change audited |

- V1 may expose only `featureFlags`; never store secrets here.

---

## 2. Modified existing collections

### 2.1 `users/{uid}` — additive fields; role untouched by admin grants

| Field | Status | Notes |
|---|---|---|
| `role` | exists | **NOT used for admin.** Stays `passenger`/`driver`; `'admin'` literal unused. Admin access = `adminOperators` only |
| `driverStatus` | exists | capability flag `none\|pending\|approved\|suspended`; written transactionally by lifecycle module |
| `banned`, `bannedReason`, `isActive` | schema-doc fields | now actually written by admin service |
| `deactivatedAt`, `deactivatedBy`, `deactivationReason` | NEW | account-level disable metadata |
| `suspendedUntil` (user-level) | NEW? | optional; driver suspension uses `drivers.*` fields |

### 2.2 `drivers/{uid}` — review lifecycle becomes real

| Field | Status | Notes |
|---|---|---|
| `driverStatus` | NEW field (schema-doc only today) | review lifecycle: `pending\|under_review\|info_requested\|approved\|rejected\|suspended` — **authoritative for admin queues** |
| `applicationVersion` | NEW | integer, starts 1, increments on each submission/resubmission; **required in all review mutations as `expectedApplicationVersion`** |
| `approvedBy`, `approvedAt`, `rejectionReason`, `reviewedBy`, `reviewedAt` | schema-doc fields | now written |
| `infoRequestNote`, `infoRequestedAt` | NEW | what the driver must fix (driver-facing) |
| `reviewNotes` | NEW? | internal reviewer notes (admin-only) — optional; `adminUserNotes` may suffice. Keep field out unless needed |
| `suspensionReason`, `suspendedUntil`, `suspendedBy`, `suspendedAt` | schema-doc fields | now written |
| `onboardingSubmittedAt` | exists | already written |
| `documents` | exists (text fields) | CNIC/license **numbers** only in V1; image refs deferred (no paid storage) |

**Transition table (both fields updated atomically by the approved shared `driver_lifecycle.ts` module — D-03):**

| Review action | `drivers.driverStatus` | `users.driverStatus` | `users.role` |
|---|---|---|---|
| submit (auto-approve ON, current prod) | — | `approved` | `driver` |
| submit (manual mode) | `pending` | `pending` | unchanged |
| admin approve | `approved` | `approved` | `driver` |
| admin reject | `rejected` | `none` | unchanged |
| admin request-info | `info_requested` | `pending` | unchanged |
| driver resubmits | `pending` (version++) | `pending` | unchanged |
| admin suspend | `suspended` | `suspended` | unchanged (`driver` kept) |
| admin reactivate | `approved` | `approved` | unchanged |

`users.driverStatus='pending'` while under review keeps the capability gate closed (gates require `'approved'`) while preserving "application in flight" semantics.

### 2.3 `rides/{rideId}` — additive fields

| Field | Notes |
|---|---|
| `adminIntervention` | map `{type:'force_cancel', by:adminUid, reason, at}` |
| `cancelledBy` | extend enum with `'admin'` (currently `passenger\|driver\|server`) |

### 2.4 `disputes/{id}` — additive fields

`resolvedBy`, `resolvedAt`, `resolutionNote` added; status transitions `OPEN→RESOLVED|DISMISSED` already in type union.

### 2.5 Config collections — no schema change

`pricingRules`, `feePolicies`, `cities`, `deliveryConfig` — admin service writes through existing repository shapes (`updatedBy`/`version` already present).

---

## 3. Explicitly NOT created (avoid duplicate SoT)

| Don't create | Because |
|---|---|
| `adminUsers` separate from `adminOperators` | one doc per operator is enough |
| `driverApplications` separate collection | application state lives on `drivers/{uid}`; a parallel collection would fork truth |
| `notifications` inbox v1 | FCM push only today |
| `adminSessions` | Firebase ID tokens + `auth_time` step-up suffice |
| `adminRoles` collection | role→permission map is code-defined (catalog), not data |
| Vendor collections now | **D-02 approved:** Admin specifies integration now but builds Phase 3; vendor collections/status machine come from the Marketplace plan (`vendors/{uid}_{kind}` etc.) as single source of truth — Admin adds only read/admin-action paths + `adminUserNotes` (targetType `vendor`) + audit events |
| Payment admin collections | payments unimplemented |
| KYC document/image storage | **paid Firebase Storage not approved — V1 text-only** |

---

## 4. Index additions required (`firestore.indexes.json`)

| Collection | Fields | Query it serves |
|---|---|---|
| `users` | `driverStatus + createdAt` | pending driver queue |
| `users` | `isActive + createdAt` | account lists by status |
| `users` | `role + createdAt` | role-filtered lists |
| `drivers` | `driverStatus + onboardingSubmittedAt` | application review queue (oldest first) |
| `adminUserNotes` | `targetType + targetId + createdAt` | notes on a profile |
| `rides` | `state + createdAt` | active ride ops view |
| `rides` | `assignedDriverId + createdAt` | driver ride history (admin) |
| `rides` | `passengerId + createdAt` | passenger ride history (admin); **also needed by DR-008 one-active-ride guard when implemented** |
| `disputes` | `status + createdAt` | open dispute queue |
| `adminAuditLogs` | per §1.2 | audit queries |
| `categories` | `active + kind` | catalog |

All list endpoints stay cursor-paginated; no unbounded scans.

---

## 5. Migration requirements

| Step | Action | Risk |
|---|---|---|
| M1 | Deploy `categories` seed (6 docs mirroring existing slugs) | none — additive |
| M2 | Code reads categories from collection with **fallback to hardcoded const** during transition | keeps existing flows working |
| M3 | Backfill `adminOperators` for initial admins via bootstrap script (no `users.role` writes) | manual, audited |
| M4 | Enable `DRIVER_AUTO_APPROVE=false` **only after** admin review endpoints are deployed AND tested on staging — confirmed product requirement | otherwise pending queue is unreviewable |
| M5 | Add explicit rules denies: `adminOperators`, `adminMetrics`, `adminAnnouncements`, `platformConfig`, `categories`, `adminUserNotes` (catch-all already denies; clarity) | none |
| M6 | Backfill `drivers.driverStatus` for existing approved drivers (`'approved'`) — one-time script; verify count vs `users.driverStatus='approved'` | low — additive field |
| M7 | (Deferred — D-04 Option A approved) document image fields/Storage paths when KYC upload is revisited; Option B requires explicit billing approval + approved constraints | requires cost-approved storage |
