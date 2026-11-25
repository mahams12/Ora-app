# ORA Admin Platform — Security & Audit Review

**Status:** DRAFT for review — reconciled 2026-11-24
**Scope:** threat model + controls for the proposed `/v1/admin/*` surface. Builds on `docs/security/threat-model.md`, `docs/architecture-final/09-security-threat-model.md`, ADR-014.

---

## 1. Asset inventory

| Asset | Sensitivity | Current exposure |
|---|---|---|
| User PII (phone, name, avatar) | High | User-readable own doc; admin needs cross-user read |
| Driver KYC data (CNIC/license **numbers** as text) | Very high | Stored plaintext in `drivers/{uid}.documents`; **no document images in V1** (paid storage not approved) |
| Ride history/location traces | High | RTDB tripLocations live-only, deleted on terminal; ride docs have addresses/coords |
| Financial data (fares, payout snapshots) | High | `agreedFareMinor`, `driverPayoutMinor`, `platformFeeMinor` on rides; feePolicies |
| Admin credentials/operator grants | Critical | New — `adminOperators` |
| Audit trail integrity | Critical | New — `adminAuditLogs` |
| Platform config (pricing, cities, dispatch) | High | Abuse = economic/operational damage |

**V1 KYC reality:** driver verification reviews *text fields* (CNIC number, license number/expiry, vehicle details). There are no document images to leak — this significantly reduces the document-exposure threat surface vs the original plan. When/if image KYC is revisited (D-04 Option B — conditional on explicit billing approval), it requires private storage + signed URLs + audited previews per the approved constraints.

---

## 2. Threat model

| # | Threat | Vector | Impact | Controls |
|---|---|---|---|---|
| T1 | Unauthorized admin access | Stolen Firebase token, weak provisioning | Full compromise | Operator doc required + status check per request; bootstrap-only creation; `verifyIdToken(…, true)` revocation check already on; step-up `auth_time` for high-risk; App Check **deferred for `/v1/admin` — D-05 Option A approved** (documented gap; mobile/production enforcement untouched) |
| T2 | Role/permission escalation | Crafted requests, self-grant, token claim forgery | Privilege escalation | Permissions server-side only, never from token; `adminOperators` doc authoritative; cannot edit self; cannot grant perms you lack; `CANNOT_TARGET_ADMIN`; `users.role` never used for admin |
| T3 | Session hijacking | XSS in admin web app, token theft | Account takeover | Short-lived ID tokens (1h); step-up `auth_time` bounds useful window to ~5min for destructive ops; strict CSP planned for admin app; bearer-token auth (no cookies → CSRF-resistant) |
| T4 | Sensitive PII/KYC exposure | Over-broad endpoints, missing masking, unmasked list views | Privacy breach | Masked-by-default responses; `*_read_pii` permissions; per-read audit; CNIC masked (`****-****-1234`); no document images exist in V1 |
| T5 | Direct database access | Admin SDK misuse, console access, leaked SA | Bypass all controls | All admin ops via `/v1/admin` only; no raw query endpoints; SA stays in Secret Manager/env; rules deny-all for clients |
| T6 | Insecure admin APIs | Missing authz on new routes, IDOR (`:uid` params) | Horizontal abuse | `requirePermission` per route (contract-tested); target validation; actor identity always `req.admin.uid`, never client-supplied |
| T7 | Unauthorized suspension/approval | Insider threat, compromised operator | Service disruption | Mandatory reasons; permission separation; audit; rate limits; active-ride protection (verified: progression doesn't recheck driverStatus → suspension can't strand trips); step-up on destructive ops |
| T8 | Audit-log tampering | Update/delete on `adminAuditLogs`, log injection | Cover tracks | Append-only: zero update/delete paths (contract test); server-only writes; rules deny; structured fields + truncation vs injection; WORM export optional later (D-07) |
| T9 | Mass-action abuse | Bulk endpoints, scripted approvals | Platform-wide damage | **No bulk endpoints V1**; per-action rate limits; idempotency; velocity anomaly alerts (Phase 2) |
| T10 | PII leakage via logs/errors | Verbose logging, error messages | Compliance breach | `logSafe` pattern; generic error messages; mask CNIC/phone in logs; audit stores diffs not raw PII |
| T11 | Replay/duplicate admin actions | Retry, double-click | Inconsistent state | Mandatory `Idempotency-Key`; durable records; transaction state+version preconditions → 409 |
| T12 | Stale-review overwrite | Two admins review same application concurrently | Lost decisions | `expectedApplicationVersion` required on all review mutations; 409 `STALE_APPLICATION_VERSION`; transaction-validated |
| T13 | CSRF on admin web app | Browser attacks | Forced actions | Bearer-token auth (not cookies) → CSRF-resistant by design; strict CORS allowlist for admin origin |
| T14 | Compromised mobile app calling admin API | Client tampering | Attempted abuse | Mobile never holds admin capability; admin requires `adminOperators` doc server-side; App Check deferred per D-05 but operator-doc requirement already blocks casual abuse |
| T15 | Step-up bypass | Old token reuse for destructive action | Delayed-detection abuse | `auth_time` (authentication time, NOT `iat`) freshness check — token refresh doesn't extend it; threshold proposed 300s (D-09) |

---

## 3. Auditability design

Every mutating admin endpoint writes `adminAuditLogs` (schema in Data Model §1.2):

- **Actor:** `adminUid`, `adminRole` (snapshot at action time).
- **Action:** `<domain>.<verb>` stable enum, code-validated.
- **Target:** `targetType` + `targetId`.
- **Diff:** `previousState`/`newState` — **field-level changes only**, masked values (e.g. `driverStatus: pending→approved`, `phoneNumber: [masked]`), never full documents.
- **Context:** `reason` (required for destructive), `requestId`, `ipHash` (SHA-256 truncated — never raw IP), `userAgent` truncated.
- **Timing:** server `createdAt`.

**Which actions must be logged:** every `/v1/admin` mutation (users, drivers, rides, disputes, config, operators, notes, announcements); every sensitive read (`*_read_pii` unmasking, application detail views with PII, audit-log access itself is permission-gated but reads of audit logs are not re-audited to avoid recursion — access is already restricted).

**Integrity properties:**
- Append-only — no update/delete paths; enforced by code review + contract test.
- Atomicity — audit write inside same transaction as mutation where possible; audit failure aborts mutation (`AUDIT_UNAVAILABLE`) — never unaudited changes.
- Queryable both ways: "everything admin X did" (`adminUid`) and "everything done to entity Y" (`targetType+targetId`).

**Retention (PROPOSED — D-21, awaiting approval):** 7 years hot in Firestore → archive/export (GCS export or BigQuery sink — mechanism deferred to D-07). Firestore alone can't provide cryptographic tamper-evidence; protection = IAM + rules + no client path. WORM export available later if compliance requires.

---

## 4. Data protection specifics

| Data | Handling |
|---|---|
| CNIC / license numbers | Text fields in `drivers.documents`; masked in API responses by default (`****-****-1234`); full view requires `drivers.review.pii` + audit. **Field-level encryption is a future hardening option** (pre-existing plaintext storage flagged) |
| Phone numbers | Masked in lists; full via `users.read_pii` |
| Document images | **N/A in V1** — no image KYC (paid storage not approved). When revisited: private bucket + 5-min signed URLs + permission check + audit |
| Avatar | Existing public-profile `avatarData` base64 — unrelated to KYC; not admin-sensitive |
| Ride coordinates | Admin ride detail shows pickup/destination (ops need); `analyst` role gets aggregates only, not per-ride coords (least privilege) |
| Audit log PII | IDs + masked field diffs only |
| Logs | `logSafe`: uids, action names, requestIds — never tokens, CNIC, full phones |

---

## 5. Abuse & rate-limit design (proposals — tune at implementation)

| Surface | Limit per operator |
|---|---|
| `/v1/admin` reads | 60 req/min |
| `/v1/admin` mutations | 20 req/min |
| Review decisions | 10 req/min |
| PII-unmasking | 30/hour (soft cap; alert on exceed) |
| Single-user notify | 5/hour |
| Announcements | 3/day |

Velocity anomaly detection (Phase 2): alert when one operator exceeds N destructive actions/hour or acts on >X% of a queue — derivable from `adminAuditLogs`.

---

## 6. Segregation of duties (V1 = permission separation)

| Risk | Mitigation |
|---|---|
| Single admin approves + suspends drivers | Distinct permissions (`drivers.approve` vs `drivers.suspend` vs `drivers.reject`); optional co-sign later (D-06) |
| Admin reviews own driver application | `SELF_ACTION_DENIED` — operators cannot act on own uid |
| Admin-on-admin actions | Only via `operators.read`/`operators.write` (super_admin); user/driver/ride endpoints deny admin targets |
| Config change + financial exploit | `config.write` vs `finance.write` separate; fee changes versioned + audited |
| Operator lockout | Break-glass script path documented; audited |

---

## 7. App Check & admin web — ✅ DECIDED (D-05 Option A approved)

- Backend `verifyAppCheck` = `getAppCheck().verifyToken()` works for any attested client (`src/index.ts:173-177`).
- **Decision (approved):** App Check enforcement on `/v1/admin` is **deferred for V1**. Admin web App Check is NOT configured (would require reCAPTCHA Enterprise provider + site key + domain registration — **no console/cost changes under this decision**).
- V1 security rests on: Firebase token verification (revocation-checked) + `adminOperators` doc + granular RBAC + `auth_time` step-up + audit. This is sufficient because admin endpoints are inert without a valid operator grant — App Check would only raise the bar against scripted abuse of a *stolen operator token*, which step-up already mitigates for destructive ops.
- **Approved constraints:** existing App Check enforcement on mobile/production surfaces is unchanged; before implementation, verify whether the App Check middleware is globally applied and explicitly scope `/v1/admin` so admin web is not unintentionally blocked; Option C (monitor-then-enforce) is a possible future upgrade; any hard enforcement requires separate explicit approval.

---

## 8. Compliance & privacy notes

- Pakistan context (PKR, CNIC, phone-OTP): CNIC is sensitive; masked-by-default + audited unmask + no image storage in V1 is the minimum bar. Field-level encryption of CNIC/license numbers is a recommended future hardening (flagged, not V1).
- Right-to-erasure vs records: permanent deletion deferred (D-10); deactivation preserves ride/financial integrity. Retention policy needed before vendor/payments launch.
- Audit retention proposal: 7 years (D-21) — awaiting approval.
- Admin access is purpose-bound via permissions + audit → misuse is detectable after the fact.

---

## 9. Security checklist for implementation phase

- [ ] `requireAdmin` + `requirePermission` on every `/v1/admin` route (contract test enumerates routes)
- [ ] `requireStepUp` on all ⬆-marked routes using `auth_time` (not `iat`)
- [ ] Actor identity always `req.admin.uid` — no client-supplied actor fields anywhere
- [ ] Self-target and admin-target denied on all entity endpoints (tests)
- [ ] All mutations: idempotency + reason validation + audit + transaction
- [ ] `expectedApplicationVersion` enforced on all four review mutations (tests incl. concurrent-review conflict)
- [ ] `adminAuditLogs` zero update/delete paths (grep contract test)
- [ ] PII masking verified per endpoint (snapshot tests on response shapes)
- [ ] Rate limiters mounted separately on `/v1/admin`
- [ ] CORS allowlist = admin origin only
- [ ] App Check decision recorded (D-05 Option A approved — deferred; `/v1/admin` namespace scoping verified at implementation)
- [ ] `firestore.rules` explicit denies added for all new collections
- [ ] Suspension test suite: suspended driver blocked from offer/invite/select/nearby/location/go-online BUT can progress in-flight ride to completion; geo marker removed
- [ ] Driver-facing `application-status` endpoint returns correct states for all review outcomes
