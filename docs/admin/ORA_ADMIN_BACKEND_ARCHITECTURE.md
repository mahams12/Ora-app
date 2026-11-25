# ORA Admin Platform — Backend Architecture

**Status:** DRAFT for review — reconciled 2026-11-24 — **D-01 APPROVED (same-service `/v1/admin`)**
**Depends on:** `ORA_ADMIN_WORKFLOW_DISCOVERY.md`

---

## 1. Placement decision — ✅ APPROVED (D-01, 2026-11-24)

**Approved: the Admin Platform is a dedicated module inside the existing `ora-auth-service` Cloud Run service. All admin endpoints live under `/v1/admin`. No separate admin backend service will be created.**

Approved constraints (user directive):

- Keep the existing Cloud Run service; no separate admin service.
- All admin endpoints under `/v1/admin`.
- Firebase Authentication + `adminOperators/{uid}` as the **sole** admin identity authority.
- Centralized RBAC permission checks on **every** admin endpoint.
- Step-up authentication where required by the security design.
- Append-only audit logging for all sensitive admin mutations.
- Admin routes/controllers/services/validation/authorization logically modular and isolated from user-facing APIs.
- **No `users.role = 'admin'` authorization mechanism.**

Rationale (recorded):

- Admin operations must reuse the same domain services (`RideService`, availability service, outbox publisher) to avoid duplicating business rules. In-process reuse is the only way to guarantee "approving a driver uses the same eligibility rules as the app" without a second service re-implementing them.
- The service is already a modular monolith; adding `src/admin/` matches the established pattern (`src/rides/`, `src/drivers/`, `src/pricing/`).
- Zero new infrastructure cost. Cloud Run scales to zero; admin traffic is tiny.
- The `/v1/internal` worker-token pattern proves the codebase already accepts multiple authn modes on one service.

**Isolation requirements (approved):** admin code lives in `src/admin/` and is mounted only under `/v1/admin`; it must not modify or depend on internals of user-facing routers beyond shared domain services; admin-specific middleware (`requireAdmin`, `requirePermission`, `requireStepUp`, admin rate limiter) applies to the whole namespace; user-facing routes remain unchanged.

```
┌─────────────────────────────────────────────────────────┐
│  ora-auth-service (Cloud Run, existing)                  │
│                                                          │
│  /v1/auth /v1/rides /v1/drivers /v1/location /v1/pricing │
│  /v1/device-tokens /v1/delivery-config                   │
│  /v1/internal/*        (worker token — sweeps)           │
│  /v1/admin/*           (Firebase ID token + admin RBAC)  ← NEW │
│                                                          │
│  src/admin/                                              │
│    middleware/admin_auth.ts     caller → req.admin        │
│    middleware/require_permission.ts  granular checks      │
│    middleware/require_step_up.ts    auth_time freshness    │
│    services/                    one per module            │
│    audit/admin_audit_service.ts append-only audit writer  │
│    aggregation/dashboard_metrics.ts cached aggregates     │
└─────────────────────────────────────────────────────────┘
```

---

## 2. Admin authentication & identity

### 2.1 Identity model (reconciled — requirement)

- **Admin authority lives ONLY in `adminOperators/{uid}`** (new collection). It is completely independent of `users/{uid}.role`.
- **`users.role` is never written for admin purposes.** It remains the application role (`passenger`/`driver`). An admin who also drives keeps `role='driver'`; granting admin access does not change, overwrite, or conflict with their app role. The `'admin'` literal in `UserRole` (`src/types.ts:2`) remains vestigial and unused — admin checks never read it.
- **No self-assignment, ever.** There is no endpoint, client write, or registration path that creates `adminOperators` docs. The only write paths are (a) a bootstrap ops script (Admin SDK, same pattern as `seed_e2e_driver_profile.ts`, guarded by `assertScriptFirebaseTarget`) for the first `super_admin`, and (b) `POST/PATCH /v1/admin/operators` for subsequent grants — itself gated by `operators.write` (effectively super_admin only), non-self-editable, and audited.
- **Operator doc is authoritative and revocable.** `adminOperators/{uid}.status ∈ active|suspended|disabled`; disabling takes effect on the next request (operator doc re-read per request; optional ≤60s in-process cache — revocation lag bounded and documented).

### 2.2 Request authentication chain

```
requireAuth (existing createAuthMiddleware — Firebase ID token,
             revocation check ON, optional App Check)
  → requireAdmin (loads users/{uid} + adminOperators/{uid};
                  attaches req.admin = {uid, role, permissions, authTime})
  → requirePermission('<perm>')   (per-route)
  → requireStepUp('<perm>')        (optional, high-risk routes only)
  → handler
```

`requireAdmin` checks, in order:

1. `users/{uid}` exists, `isActive !== false`, `banned !== true` (a banned account cannot administer).
2. `adminOperators/{uid}` exists and `status === 'active'`.
3. Effective permissions = stored `permissions[]` on the operator doc (role is a grant-time bundle, not re-resolved per request — permission edits take effect immediately since the doc is re-read).

Any failure → 403 `ADMIN_ACCESS_DENIED` (existence) or `PERMISSION_DENIED` (insufficient grant). Both generic — no oracle about which operators exist.

### 2.3 Admin sign-in & session

- Admins authenticate with **Firebase Auth** (same project). Phone-OTP or email/password — whichever is enabled for the admin web app; this is a client-config decision, not a backend one.
- **No server-side sessions.** Firebase ID tokens (1h TTL) + SDK refresh. Step-up uses token `auth_time` (§7).
- **App Check — ✅ APPROVED (D-05 Option A):** enforcement is **deferred for `/v1/admin` in V1**. `verifyAppCheck` = `getAppCheck().verifyToken()` (`src/index.ts:173-177`) works for any attested client, but no web provider is configured (reCAPTCHA Enterprise setup required) and **no console/cost changes are made under this decision**. V1 admin security rests on: Firebase token verification + `adminOperators` doc + RBAC + step-up + audit. **Approved constraint:** existing App Check enforcement on mobile/production surfaces must NOT be weakened; before implementation, verify whether the App Check middleware is globally applied and explicitly scope `/v1/admin` so the admin web client is not unintentionally blocked. Option C (monitor-then-enforce) is a possible future upgrade; any hard enforcement needs separate approval.
- CORS: admin web origin must be added to the service's CORS allowlist when the web app exists (none configured today — flag for implementation).

### 2.4 Revocation & lockout

- `adminOperators/{uid}.status = 'suspended'|'disabled'` or deleting the doc → access revoked on next request.
- `users/{uid}.banned`/`isActive=false` → also blocks (defense in depth).
- Break-glass: ops script can disable an operator directly (Admin SDK); script path is documented and itself logged to `adminAuditLogs` by convention.
- Emergency "disable all admin access" = set a `platformConfig` kill-switch or revoke SA — operational runbook item, not code.

---

## 3. Authorization model (RBAC)

Granular **permission strings** enforced by `requirePermission()` on every `/v1/admin` route. Roles are grant-time bundles producing the stored `permissions[]` list. Full catalog + matrix: `ORA_ADMIN_RBAC_PERMISSION_MATRIX.md`.

Enforcement rules:

- **Backend is the only enforcement point.** Frontend hides buttons for UX; every route independently checks.
- Permissions checked against a code-defined catalog (`src/admin/permissions.ts`) — unknown strings fail closed.
- **Six roles** (proposed, none approved yet): `super_admin`, `ops_admin`, `verification_admin`, `support_admin`, `finance_admin`, `analyst`. Role→permission defaults live in code; per-operator `permissions[]` may deviate (least-privilege exceptions).
- **No self-escalation:** cannot modify own `adminOperators` doc; cannot grant permissions you don't hold; cannot target admin accounts via user/driver/ride endpoints (`CANNOT_TARGET_ADMIN`); self-targeting on driver actions also denied (an operator reviewing their own driver application is blocked — `SELF_ACTION_DENIED`).
- **Who grants:** only `operators.write` (super_admin bundle) + bootstrap script. No delegation chains in V1.
- **Separation of duties:** permission separation is the V1 mechanism (approve vs suspend vs ban vs finance are distinct grants). Optional co-sign workflows are a later decision (D-06).

---

## 4. Service layer design

```
src/admin/
  middleware/
    admin_auth.ts               // resolve caller → req.admin (users + adminOperators)
    require_permission.ts       // permission gate factory
    require_step_up.ts          // auth_time freshness check
    rate_limit_admin.ts         // stricter limiter for /v1/admin
  permissions.ts                // permission catalog + role→permission map
  services/
    admin_users_service.ts      // user search/detail/account actions
    admin_drivers_service.ts    // applications, review, suspension
    admin_rides_service.ts      // ride lookup, force-cancel, history
    admin_categories_service.ts // category CRUD
    admin_disputes_service.ts   // dispute resolution
    admin_config_service.ts     // pricingRules, feePolicies, deliveryConfig, cities
    admin_notifications_service.ts // broadcast/announcement (Phase 2)
    admin_dashboard_service.ts  // metrics APIs
    admin_notes_service.ts      // adminUserNotes
  audit/
    admin_audit_service.ts      // append-only writer + query helper
  aggregation/
    dashboard_aggregator.ts     // scheduled/on-demand metric computation
```

Plus one **non-admin** addition: a driver-facing application-status endpoint (§4.4).

### 4.1 Reuse, don't duplicate

| Admin operation | Reuses | Notes |
|---|---|---|
| Approve driver application | Shared `driver_lifecycle` module (extracted from `DriverOnboardingService`) | See §4.2 — the key refactor |
| Suspend driver | `DriverAvailabilityService.goOffline` path + Firestore tx writing status fields | Same path as mode-switch offline (`routes/auth.ts:298-312`) — geo cleanup included |
| Reactivate driver | Reverse transition; driver goes online themselves | Never auto-set `online` |
| Suspend passenger | `users.isActive=false`/`banned=true` write + audit | Enforcement already global |
| Force-cancel ride | New `RideService.adminForceCancel` wrapping cancel internals + `actorRole:'admin'` in `rideEvents` | Must emit outbox events so FCM projectors notify both parties; must respect courier custody rules |
| Resolve dispute | New method updating `disputes.status` + outbox event | Courier disputes only today |
| Category changes | New `categories` collection + validation against `pricingRules` keys | Must not silently break `{city}_{category}` lookups |
| Pricing/fee config | `pricing_rules_repository.ts`, `fee_policy.ts` write shapes | Currently seed-only; expose validated upsert |

### 4.2 Shared driver lifecycle module — ✅ APPROVED (D-03, 2026-11-24)

`DriverOnboardingService.submit` mixes self-service validation + transition. **Approved:** introduce `src/drivers/driver_lifecycle.ts` with explicit transitions used by BOTH self-onboarding and admin review — same transition/business-rule layer, no duplicated logic.

**Approved constraints:**
- Preserve existing onboarding API behavior and response contracts unless a documented compatibility change is explicitly approved.
- All lifecycle mutations run in Firestore transactions.
- All four Admin review mutations enforce `expectedApplicationVersion`.
- `users.driverStatus` and `drivers.driverStatus` updated atomically in the same transaction.
- Admin authorization and audit stay in the Admin layer — Admin-only transitions are never exposed to mobile callers.
- Regression tests required: onboarding, approve, reject, request-info, reopen, resubmit, suspend, reactivate.
- `DRIVER_AUTO_APPROVE` and production behavior unchanged by this decision.

```
submitApplication(uid, application)          // self-service (existing path)
adminApprove(driverId, adminUid, expectedVersion, note?)
adminReject(driverId, adminUid, expectedVersion, reason)   // mandatory reason
adminRequestInfo(driverId, adminUid, expectedVersion, note)
adminReopen(driverId, adminUid, expectedVersion)           // rejected/info_requested → pending
adminSuspend(driverId, adminUid, reason, until?)
adminReactivate(driverId, adminUid)
```

Each runs in `runTransaction`, validates `applicationVersion` (stale-review protection), writes both `users.driverStatus` (capability flag) and `drivers.driverStatus` (review lifecycle) consistently, writes `adminAuditLogs`, and emits outbox notification events where implemented. **This is the single most important reuse decision** — approval must never diverge between self-service and admin paths.

### 4.3 Driver-facing application status (new non-admin endpoint)

Reliable driver status must not depend on FCM. Add `GET /v1/drivers/application-status` (authenticated driver caller) returning:

```json
{ "data": {
    "applicationStatus": "none|pending|under_review|info_requested|approved|rejected|suspended",
    "capabilityStatus": "none|pending|approved|suspended",   // users.driverStatus mirror
    "infoRequestNote": "..." | null,                          // what to fix
    "rejectionReason": "..." | null,
    "applicationVersion": 3,
    "submittedAt": "...", "reviewedAt": "..." | null,
    "canResubmit": true|false,
    "nextAction": "wait|update_info|resubmit|contact_support" } }
```

Data source: `drivers/{uid}` review fields + `users/{uid}.driverStatus`. Mobile driver registration/status screens consume this — push notifications are a nice-to-have on top, never the only channel.

### 4.4 Suspension semantics — verified behavior

**Suspension MUST:**

1. Set `users.driverStatus='suspended'` (capability flag — gates read this) **and** `drivers.driverStatus='suspended'` (review/lifecycle record) in one transaction.
2. Force `availabilityState='offline'` via the `DriverAvailabilityService.goOffline` path → removes geo projection, clears presence.
3. Write `suspensionReason`, `suspendedUntil?`, `suspendedBy`, `suspendedAt`.
4. Emit outbox `driver.suspended` notification event (Phase 2 push; state change is immediate regardless).
5. Record audit `driver.suspend` with reason.

**Active-ride behavior — VERIFIED in code:**

- `progressAssignedRide` (`ride_service.ts:3104`) authorizes solely on `ride.assignedDriverId === caller.uid` + state machine — it does **not** re-check `driverStatus`. A suspended driver with an in-flight ride completes `en-route→arrived→start→complete` normally. ✅ Desired: suspension never strands a live trip.
- New work is blocked instantly: `createOffer` (`:1827`), invite accept (`:1734`), `selectOffer` re-check (`:2454-2465`), nearby eligibility (`nearby_service.ts:783`), location updates (`location_update_service.ts:317`), go-online (`driver_availability_service.ts:95`).
- **Admin force-cancel** of an active ride remains available as the escape hatch (`rides.cancel` permission), respecting courier custody rules (no force-cancel once parcel in transit — aligns with `v2HasCustody`).
- **Implementation checklist:** add tests proving (a) suspended driver cannot createOffer/be invited/selectOffer, (b) suspended driver CAN progress an already-assigned ride to completion, (c) force-offline removes geo marker, (d) reactivation restores eligibility without auto-going-online.

**Passenger suspension:** `isActive=false` (reversible suspend) vs `banned=true` (stronger). Both enforced globally at auth routes. Same active-ride policy: block new bookings (`createRide` → `assertPassenger` → `loadActor`; banned/inactive actors fail), don't corrupt in-flight rides.

**Reactivation:** restores prior approved state; driver goes online manually. Never restores `banned` implicitly.

**State semantics — never interchangeable:**
- `rejected` = application denied (pre-activation; lives on `drivers.driverStatus`)
- `suspended` = activated driver blocked (both status fields)
- `isActive=false` = account-level disable (any role)
- `banned=true` = abuse ban (strongest)
- Hard deletion = **not supported** (D-10: soft-deactivate + future anonymization)

**One-active-ride-per-passenger (DR-008):** approved product invariant, backend enforcement **not yet implemented**. Admin ride tooling must not depend on it; force-cancel stays valid either way. When DR-008 ships, admin ride lists may show it as a data-quality signal.

---

## 5. Audit logging

New collection **`adminAuditLogs/{autoId}`** (already reserved deny-all in `firestore.rules:151`):

```ts
{
  auditId: string,
  adminUid: string,
  adminRole: string,             // snapshot at action time
  action: string,                // '<domain>.<verb>' e.g. 'driver.approve'
  targetType: string,            // 'user'|'driver'|'ride'|'vendor'|'category'|'config'|'operator'|'note'
  targetId: string,
  previousState: map|null,       // bounded: changed fields only, masked values
  newState: map|null,
  reason: string|null,           // mandatory for destructive/sensitive actions
  requestId: string,             // correlation id
  ipHash: string|null,           // SHA-256 truncated; never raw IP
  userAgent: string|null,        // truncated 200 chars
  createdAt: timestamp           // server timestamp — immutable
}
```

Rules:

- **Append-only.** No update/delete code paths anywhere; contract test asserts this.
- Written **in the same Firestore transaction** as the mutation where feasible; otherwise immediately after with same `requestId`. Audit failure → mutation aborts (`AUDIT_UNAVAILABLE` 503) — **fail closed, never unaudited changes**.
- **PII minimization:** record field-level diffs (`driverStatus: pending→approved`), not full documents; mask CNIC/phone values in `previousState`/`newState`; never log tokens, passwords, document contents, raw IPs, or full request bodies.
- **Who reads:** `audit.read` permission (super_admin + ops_admin + support_admin per matrix). No write/update endpoints exist — query-only.
- **Retention (PROPOSED — awaiting approval, D-21):** retain hot in Firestore for **7 years**, then archive/export (GCS export or BigQuery sink — deferred decision). Rationale: dispute windows, financial reconciliation, and abuse investigations realistically need multi-year history; 7y matches common fintech/audit practice. Alternative: indefinite (current doc default) — user decides.
- **Tamper-resistance:** server-only writes + rules deny + no mutation paths. Cryptographic/WORM export is a later option (D-07).

---

## 6. Cross-cutting API concerns

| Concern | Design |
|---|---|
| Pagination | Cursor-based (`?cursor=&limit=`), matching `rides/list_query.ts`; default 25, max 100; `orderBy`+`startAfter`; never offset on large collections |
| Filtering | Whitelisted params → indexed fields only; compound queries need `firestore.indexes.json` entries (listed in Data Model doc) |
| Search | v1: phoneNumber/uid/email exact + displayName prefix (bounded). Firestore has no substring search — do not promise fuzzy search; document limitation |
| Rate limiting | Dedicated admin limiter mounted on `/v1/admin` separately: reads 60/min/operator, mutations 20/min, review decisions 10/min, PII-unmask 30/hour, notify 5/hour, announcements 3/day (proposals — tune at implementation) |
| Idempotency | `Idempotency-Key` **required** on all mutations; durable `idempotencyRecords` (existing, 7-day TTL) keyed `admin:{adminUid}:{key}`; replay returns stored response; conflicting reuse → 409 |
| Concurrency | `runTransaction` + expected-state preconditions; review actions additionally require `expectedApplicationVersion`; 409 `STATE_CONFLICT`/`STALE_APPLICATION_VERSION` on lost races |
| Validation | Strict body allowlists (existing `rejectUnknownProfileFields` pattern); unknown fields → 400 |
| Errors | `sendApiError` `{error:{code,message}, requestId}` envelope + admin-specific codes (API spec §10) |
| Bulk actions | **None in V1** (D-08) — single-target only |
| Sensitive reads | `*_read_pii` permissions + `*.read_sensitive`-style audit entries; document previews deferred (no storage) |
| File access | N/A in V1 — no document images. Avatar is existing public-profile data, not KYC |

---

## 7. Step-up authentication (reconciled — D-09)

**Mechanism: Firebase ID token `auth_time` claim** (seconds since epoch, present in decoded token from `verifyIdToken`). NOT `iat` — `iat` is token issuance; `auth_time` is when the user last *authenticated* (fresh OTP/password), which is what re-authentication freshness means. `iat` can be refreshed without re-auth; `auth_time` cannot.

**Proposed threshold (awaiting approval): 300 seconds (5 minutes).** A step-up-protected route rejects tokens whose `auth_time` is older than 5 min with 403 `STEP_UP_REQUIRED`; the admin web app re-authenticates (fresh OTP or password) and retries. 300s balances security vs UX; alternatives 60s (friction) / 900s (looser) — user decides.

**Requires step-up (proposed list):**
- `users.ban`, `users.unban`?, `users.deactivate`
- `drivers.suspend`, `drivers.reactivate`?, `drivers.force-offline`?
- `rides.force-cancel` (admin ride cancel)
- `operators.write` (grant/revoke admin access)
- `config.write` (pricing/fee/city/delivery config)
- `finance.write` (future)
- `disputes.write`? (resolve — medium risk; include for consistency)

(Reactivation/unban arguably lower-risk — final list is a decision detail; recommend including all state-changing destructive-ish actions.)

**MFA:** Firebase MFA (TOTP/phone) is **NOT implemented or verified** anywhere in the codebase — treat as a separate future decision (D-09b), not assumed. `adminOperators.mfaEnrolled` field reserved for when/if adopted.

---

## 8. Dashboard aggregation strategy

See `ORA_ADMIN_DASHBOARD_METRICS.md`. Principles:

- **No full-collection scans per page load.** Live `count()` aggregation queries for queue depths (small, indexed), scheduled `adminMetrics` rollups for trends, bounded on-demand reports for drill-down.
- **Cost honesty:** Firestore `count()` is an aggregation query billed per ~1000 index entries scanned — cheap relative to document reads but **not free**; dashboard budget caps total ops per load (~50). Estimates labeled ESTIMATE, not verified billing.
- Aggregation runs via `/v1/internal/admin/aggregate` on the existing Cloud Scheduler → Cloud Run Jobs pattern; window-bounded scans only.
- No real-time listeners; dashboard polls on load.

---

## 9. Admin frontend boundary

- **Separate web app** (proposal D-15): `admin-web/` — Firebase Auth web SDK, calls `/v1/admin/*` only, never touches Firestore.
- **App Check for web:** enforcement **deferred per D-05 (approved Option A)** — no reCAPTCHA Enterprise setup, domain registration, or costs under this decision; mobile/production enforcement unchanged; `/v1/admin` scoping to be verified at implementation; future hard enforcement requires separate approval.
- CORS allowlist for admin origin (to add at implementation).
- Branding deferred — matches Ora navy/gold/teal when UI work begins.

---

## 10. What needs NEW vs REUSED — summary

| Capability | Status |
|---|---|
| Admin authN (Firebase token) | REUSE `createAuthMiddleware` |
| Admin authZ | NEW `requireAdmin`/`requirePermission` + `adminOperators` |
| Step-up auth | NEW `requireStepUp` on `auth_time` |
| Driver lifecycle transitions | REFACTOR shared module from `DriverOnboardingService` |
| Driver suspension enforcement | REUSE existing eligibility gates (verified for new work; progression exempt by design) |
| Driver-facing status endpoint | NEW `GET /v1/drivers/application-status` |
| Ride reads for admin | NEW cross-user query service |
| Ride force-cancel | NEW `RideService` method reusing cancel internals |
| Audit logging | NEW `adminAuditLogs` writer |
| Dashboard metrics | NEW aggregation job + read APIs |
| Admin notes | NEW `adminUserNotes` collection + service |
| Category management | NEW `categories` collection + admin CRUD |
| Vendor management | SPEC APPROVED (D-02), build Phase 3 — reuses Marketplace `vendors` status machine as SoT; entry criteria in Master Plan §6 |
| Document image verification | **DEFERRED — D-04 Option A approved** (text-only KYC V1; Option B conditional on future billing approval) |
| Broadcast notifications | NEW outbox event type + projector extension (Phase 2) |
| Payment admin | FUTURE — payments not implemented |
