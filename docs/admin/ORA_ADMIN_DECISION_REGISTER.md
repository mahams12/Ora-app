# ORA Admin Platform — Decision Register

**Status:** Reconciled 2026-11-24 — architecture-lock candidate
**Classification vocabulary:** `CONFIRMED BY USER` · `PROPOSED — AWAITING USER APPROVAL` · `DEFERRED` · `NOT APPLICABLE`

**Confirmed product decisions (from user, this reconciliation + prior records):**
- Manual driver approval is required — phone verification must not auto-approve; admin review precedes activation. (`CONFIRMED BY USER`)
- One active ride per passenger, enforced transactionally in the backend — DR-008 APPROVED 2026-11-24; **backend enforcement not yet implemented** (`docs/engineering/ORA_ENGINEERING_DECISION_REGISTER.md`).
- Firebase direction for avatar/KYC handling is approved **conditional on avoiding additional storage cost**; **paid Firebase Storage / KYC image uploads are NOT approved** (`CONFIRMED BY USER`).
- `expectedApplicationVersion` on driver review mutations — required directive (`CONFIRMED BY USER` as requirement, implemented in API spec).
- Step-up auth must use Firebase token `auth_time` (not `iat`) — required directive; threshold remains a proposal.
- **D-01 Admin backend placement — Option A APPROVED (2026-11-24):** admin platform is a dedicated module inside the existing Cloud Run Express backend under `/v1/admin`. No separate admin service.
- **D-02 Vendor admin scope timing — Option A APPROVED (2026-11-24):** specify vendor management architecture/APIs/permissions/data-model integration in Admin docs now; implementation deferred to Phase 3; no vendor build until Marketplace backend is formally approved; reuse the Marketplace vendor status machine as single source of truth — no parallel lifecycle.
- **D-03 Shared driver lifecycle module — Option A APPROVED with constraints (2026-11-24):** extract transitions into `src/drivers/driver_lifecycle.ts`; self-service onboarding and Admin review share the same transition/business-rule layer; preserve existing onboarding API behavior/response contracts unless a compatibility change is explicitly approved; Firestore transactions for mutations; `expectedApplicationVersion` on all four Admin review mutations; atomic `users.driverStatus` + `drivers.driverStatus` updates; Admin authorization/audit stays in the Admin layer — mobile callers cannot invoke Admin-only transitions; regression tests required; no `DRIVER_AUTO_APPROVE`/production behavior change under this decision.
- **D-04 KYC document image storage — Option A APPROVED (2026-11-24):** defer KYC document images for V1 — text-only verification; no paid Storage/Blaze; Option B (Firebase Storage) remains a future conditional option requiring explicit billing approval; vendor KYC follows the same deferral.
- **D-05 App Check on `/v1/admin` — Option A APPROVED (2026-11-24):** defer App Check enforcement for `/v1/admin` in V1; admin security rests on Firebase Auth + `adminOperators` + RBAC + step-up + audit; existing App Check enforcement on mobile/production surfaces unchanged; `/v1/admin` namespace scoping must be verified before implementation; no Firebase Console/reCAPTCHA/cost changes; Option C remains a possible future upgrade requiring separate approval.
- **Batch 1 — Security & Governance APPROVED (2026-11-24):**
  - **D-06** Option A — permission separation only; permission catalog approved; destructive permissions separate; `counterSignedBy` reserved; co-sign deferred; **role-to-person assignments NOT approved — separate approval required**.
  - **D-07** Option A — append-only Firestore; contract test for immutability; audit failure aborts mutation (`AUDIT_UNAVAILABLE`); GCS export deferred until D-21 + compliance.
  - **D-08** Option A — no bulk/multi-target endpoints in V1; all mutations single-target, permission-checked, rate-limited, audited.
  - **D-09** Option A — `auth_time` (never `iat`) step-up, 300s threshold, op list exactly as documented; `users.unban`/`users.reactivate`/`drivers.reactivate` excluded but still gated/audited/rate-limited; MFA separate; revisit on abuse evidence.

All other entries below retain pending status — assistant recommendations are NOT approvals.

---

## D-01 — Admin platform placement — ✅ APPROVED

- **Requirement:** host admin APIs without duplicating business logic.
- **Current:** single Express monolith `ora-auth-service` on Cloud Run; `/v1/internal` coexists with user APIs.
- **Decision (user, 2026-11-24):** **Option A APPROVED** — dedicated admin module inside the existing Cloud Run Express backend; all admin endpoints under `/v1/admin`; Firebase Auth + `adminOperators/{uid}` as sole admin identity; centralized RBAC on every endpoint; step-up where required; append-only audit on sensitive mutations; modular isolation from user-facing APIs; **no `users.role='admin'` authorization mechanism**; no separate admin service.
- **Status:** **CONFIRMED BY USER — APPROVED**

## D-02 — Vendor admin scope timing — ✅ APPROVED (Option A)

- **Requirement:** plan vendor management without building on sand.
- **Current:** marketplace backend NOT STARTED; vendor model in `docs/implementation/marketplace/ORA_MARKETPLACE_AUDIT_AND_PLAN.md`.
- **Decision (user, 2026-11-24):** **Option A APPROVED** — specify vendor management architecture, API requirements, permissions, and data-model integration in Admin documentation **now**; keep implementation **deferred to Phase 3**; do not build vendor functionality until the Marketplace backend is formally approved and its vendor data model/lifecycle are established; when implementation begins, **reuse the Marketplace vendor status machine and business rules as the single source of truth — no parallel vendor lifecycle in Admin**; all vendor endpoints/permissions marked planned/deferred, not V1-ready.
- **Phase 3 entry criteria:** (1) Marketplace backend approved; (2) `vendors/*` collections + status machine implemented; (3) vendor auth/role model finalized (vendor roles NOT in `users.role`); (4) document-storage strategy resolved (paid Storage not currently approved); (5) vendor permissions granted to operators.
- **Status:** **CONFIRMED BY USER — APPROVED** (specification now; implementation DEFERRED)

## D-03 — Driver lifecycle refactor (shared transition module) — ✅ APPROVED (Option A, with constraints)

- **Requirement:** admin approve/reject/suspend must use identical rules as self-onboarding; manual approval is confirmed.
- **Current:** transition logic embedded in `DriverOnboardingService.submit` (auto-approve path only).
- **Decision (user, 2026-11-24):** **Option A APPROVED** — extract shared driver lifecycle transitions into `src/drivers/driver_lifecycle.ts`; self-service onboarding and Admin review share the same transition/business-rule layer.
- **Approved constraints:**
  1. Preserve existing onboarding API behavior and response contracts unless a documented compatibility change is explicitly approved.
  2. Firestore transactions for all lifecycle mutations.
  3. `expectedApplicationVersion` enforced on all four Admin review mutations (approve/reject/request-info/reopen).
  4. `users.driverStatus` and `drivers.driverStatus` updated atomically in the same transaction.
  5. Admin authorization and audit enforcement remain in the Admin layer — Admin-only transitions are not invocable by mobile callers.
  6. Regression tests required: existing onboarding, approval, rejection, request-info, reopening, resubmission, suspension, reactivation.
  7. `DRIVER_AUTO_APPROVE` and production behavior unchanged by this decision.
- **Status:** **CONFIRMED BY USER — APPROVED**

## D-04 — KYC document image storage — ✅ APPROVED (Option A: defer for V1)

> **Confirmed constraint (approved, unchanged):** paid Firebase Storage / KYC image uploads are **NOT approved**; avoid unexpected storage/infrastructure costs. V1 = text-based KYC + manual review regardless of which option below is eventually chosen.

- **Problem:** driver (and later vendor) verification today reviews only *text* KYC fields (CNIC/license numbers, vehicle details — `drivers/{uid}.documents`). There is no document-image upload anywhere in the stack (no Storage SDK, no upload endpoint). Genuine document verification (licence card, CNIC copy, vehicle registration, insurance) requires image/file storage + secure admin preview.
- **Current state:** `drivers/{uid}.documents` holds text fields only; `driverDocuments`/`vehicles` collections are schema-doc + rules-deny only; `users.avatarData` (base64 data-URL) is the only existing file-like storage and is a public profile avatar, not KYC; no Firebase Storage bucket, no `firebase-admin/storage` usage, no upload endpoints.

### Decision (user, 2026-11-24): **Option A APPROVED — defer KYC document images for V1**

Approved constraints:
1. V1 driver verification remains **text-only** (CNIC/license numbers, license expiry, vehicle details — manual review).
2. **No** KYC image upload, storage bucket, upload endpoint, or admin image-preview functionality in V1.
3. **No** paid Firebase Storage or Blaze billing activation.
4. Document images must **never** be stored as Base64 in Firestore.
5. Option B (Firebase Storage) remains a **future conditional option** — requires explicit user billing approval before any implementation.
6. Vendor KYC follows the **same deferred image-storage decision** (D-02 Phase 3 entry criterion unchanged).
7. Any future image-KYC implementation must define: access controls, audited previews, upload validation, retention/deletion policy, cost ceiling, and billing alerts — coordinated with D-10 (account deletion/anonymization).

### Options (record — A selected)

**Option A — Defer image KYC entirely (text-only verification)** ✅ SELECTED
- Admin reviews CNIC/license *numbers* + vehicle details manually; no images ever stored.
- *Technical:* zero new infra; admin review UI shows text fields only (already specified).
- *Security:* smallest data footprint — nothing to leak; but verification is weak (numbers can be typed, not proven).
- *Cost:* $0. *Maintenance:* none.
- *Fit:* fully satisfies the confirmed no-paid-storage constraint.

**Option B — Firebase Storage (Cloud Storage for Firebase), private bucket**
- Driver/vendor apps upload document images via signed-upload or backend-mediated path; admin previews via short-lived signed URLs after permission check + audit.
- *Technical:* requires Blaze (pay-as-you-go) plan — new billing relationship; `firebase-admin/storage` in `ora-auth-service`; new upload endpoint(s) (likely `/v1/drivers/documents` + admin preview under `/v1/admin`); `drivers.documents.*` gains `storagePath`/`status` fields; rules already deny client Storage/Firestore access so all access is backend-mediated.
- *Security:* private bucket, no public URLs; signed URLs TTL ~5min; `drivers.review.pii`-gated previews with read-audit; malware/type validation server-side (content-type + size caps); retention/deletion policy needed.
- *Cost:* Blaze required even at $0 usage; storage ~few GB, egress per preview — small but **nonzero and billing-account-dependent**; needs budget alert.
- *Maintenance:* bucket lifecycle rules, key management, signed-URL minting, preview UI.
- *Fit:* violates the literal "no paid storage" constraint **unless the user approves Blaze**; best long-term fit if image KYC becomes mandatory.

**Option C — Alternative object storage (e.g., Cloudflare R2 / S3-compatible)**
- Same flow as B but on non-GCP object storage with zero egress fees and free tier (~10GB).
- *Technical:* new vendor + credentials + IAM outside GCP; backend adapter for signed URLs/uploads; data residency/compliance review; more moving parts than B.
- *Security:* comparable if configured correctly (private, signed URLs), but adds a second cloud trust boundary.
- *Cost:* free tier likely covers V1 volumes; egress-free helps at scale.
- *Maintenance:* highest — separate provider, SDK, monitoring, billing.
- *Fit:* avoids Blaze but introduces new infrastructure/vendor — heavier than B for the same outcome.

**Option D — Base64/inline in Firestore** — *rejected:* 1MiB doc limit too small for multi-doc KYC sets, per-read cost on every admin view, rules exposure risk, no lifecycle management.

### Dependencies

- **D-01 (approved):** any upload/preview endpoints would live in the same Cloud Run service (`/v1/drivers/*` for upload, `/v1/admin/*` for review) — compatible with all options.
- **D-02 (approved):** vendor KYC documents share this decision — Phase 3 entry criterion "document-storage strategy resolved" points here.
- **D-03 (approved):** `driver_lifecycle.ts` stores review state; document *references* (paths/status) would be additive fields on `drivers/{uid}.documents` — compatible, no lifecycle change needed.

### Risks & trade-offs

- Choosing B/C without billing approval repeats the constraint violation the user already ruled out.
- Staying text-only (A) indefinitely means admin approval rests on unverified self-reported numbers — fraud risk the product may find unacceptable at scale.
- Whichever option wins, admin preview must be permission-gated + audited; public exposure of KYC images would be a serious privacy breach.

### Outcome

**Option A selected (approved).** Option B (Firebase Storage) remains the recommended *future conditional* path if image verification becomes mandatory — conditional on explicit billing approval. Option C only if egress costs later dominate. Option D rejected.

### Constraints that would apply to any future image-KYC implementation (recorded at approval)

1. Private storage only — no public URLs ever; access via backend-minted short-lived signed URLs.
2. Uploads backend-mediated or signed-upload with strict content-type/size validation; malware scanning consideration.
3. Admin preview requires `drivers.review.pii`-equivalent permission + `*.read_sensitive` audit entry per view.
4. Retention/deletion policy defined before launch — coordinated with D-10 (right-to-erasure vs audit/financial retention).
5. Cost ceiling + billing alert before enabling.
6. Vendor documents reuse the same mechanism (D-02 Phase 3 criterion).

- **Status:** **CONFIRMED BY USER — APPROVED (Option A)**

## D-05 — App Check on `/v1/admin` — ✅ APPROVED (Option A: defer enforcement for V1)

- **Problem:** prevent non-app/scripted clients from calling admin APIs with stolen or forged credentials; raise the cost of token abuse.
- **Current state:** backend `verifyAppCheck` = `getAppCheck().verifyToken()` (`src/index.ts:173-177`) and works for **any** attested client; production sets `REQUIRE_APP_CHECK=true` for the existing mobile surface. **No App Check provider is configured for an admin web app** — web attestation requires reCAPTCHA Enterprise provider setup in Firebase console + `RECAPTCHA_ENTERPRISE_SITE_KEY` in the app + domain registration.

### Decision (user, 2026-11-24): **Option A APPROVED — defer App Check enforcement for `/v1/admin` in V1**

Approved constraints:
1. App Check enforcement is **deferred** for `/v1/admin` in V1.
2. Admin API security must still enforce: Firebase Authentication, `adminOperators/{uid}` identity verification, granular RBAC permissions, required step-up authentication, and append-only audit logging.
3. **Do not weaken, disable, or change** existing App Check enforcement on mobile or other production API surfaces.
4. Before admin API implementation, **verify whether existing App Check middleware is globally applied**; ensure `/v1/admin` namespace behavior is explicitly scoped and documented so the admin web client is not unintentionally blocked.
5. **No** Firebase Console changes, reCAPTCHA Enterprise configuration, domain registration, or App Check-related costs under this decision.
6. Option C (monitor-then-enforce) remains a possible **future upgrade** after the admin web provider is configured and tested; any future hard enforcement requires a **separate explicit approval**.

### Options (record — A selected)

**Option A — Defer App Check enforcement on `/v1/admin` (launch without it)** ✅ SELECTED
- Admin endpoints rely on: Firebase ID token verification (revocation-checked), `adminOperators/{uid}` doc + status, granular RBAC, `auth_time` step-up, rate limits, audit.
- *Technical:* zero new setup; must ensure App Check middleware does not accidentally block `/v1/admin` (scope or exempt the namespace — implementation detail).
- *Security:* still strong — admin endpoints are inert without a valid operator grant; App Check only raises the bar against scripted abuse of a *stolen operator token* for read endpoints; step-up already bounds destructive ops. Residual risk: bulk PII scraping with a stolen token within permission scope.
- *Cost:* $0. *Maintenance:* none now; re-enable later is config-level.
- *Fit:* consistent with confirmed D-01 (same service) and the cost-conscious posture; honest — not claimed ready.

**Option B — Configure web App Check (reCAPTCHA Enterprise) and enforce before launch**
- Set up reCAPTCHA Enterprise site key + domain allowlist in Firebase console; admin web app initializes Firebase App Check web SDK; `/v1/admin` requires valid App Check token.
- *Technical:* console + billing-adjacent setup (reCAPTCHA Enterprise has its own pricing/quota — verify); web SDK integration; enforcement wiring; testing matrix (web attested, curl/non-browser rejected).
- *Security:* strongest — blocks non-browser/scripted clients entirely at the edge of the API.
- *Cost:* reCAPTCHA Enterprise pricing applies beyond free quota (verify current tiers); small but nonzero.
- *Maintenance:* key rotation, domain management, provider monitoring.
- *Fit:* delays admin web launch until console setup + verification complete; adds a paid-ish external dependency the project has so far avoided.

**Option C — Configure provider now, enforce selectively/monitor-mode initially**
- Set up reCAPTCHA Enterprise + web SDK; log/monitor App Check validity on `/v1/admin` without hard-failing; flip to enforce after observation period.
- *Technical:* same setup cost as B plus a soft-enforcement mode in middleware (new code path).
- *Security:* middle ground — visibility before enforcement; still requires the console setup upfront.
- *Cost:* same as B. *Maintenance:* two-phase rollout complexity.
- *Fit:* reasonable if user wants App Check eventually but not as a launch blocker.

### Dependencies on approved decisions

- **D-01 (approved):** admin lives in the same Cloud Run service — App Check enforcement mechanics (`REQUIRE_APP_CHECK`, route scoping) apply service-wide; exemption/scoping for `/v1/admin` is an implementation detail consistent with D-01.
- **D-02 (approved):** vendor admin endpoints (Phase 3) inherit whatever App Check posture is chosen — no conflict.
- **D-03 (approved):** driver lifecycle module is backend-internal; App Check decision does not affect it.
- **D-04 (approved):** no interaction (no file uploads/Storage involved).

### Risks & trade-offs

- Option A leaves a documented gap: a stolen operator token usable from scripts for permitted reads until token expiry/step-up boundaries — mitigated by RBAC granularity, rate limits, and audit detection.
- Option B/C couple admin launch to Firebase console changes outside the codebase and to reCAPTCHA Enterprise terms/pricing — verify quota/cost before committing.
- If App Check middleware is global today, Option A **requires** explicit namespace scoping so admin web is not accidentally blocked — flag as implementation requirement, not optional.
- Reversibility: A→B later is easy (config + web SDK); B→A is also easy but weakens posture.

### Recommendation

**Option A for V1 launch** — admin security rests on operator doc + RBAC + step-up + audit, which are all backend-enforced and sufficient for an internal tool; App Check enforcement is deferred until the web provider is configured and verified. **Option C** is the recommended upgrade path once the admin web app exists and console setup is approved — observe before enforcing. Option B only if the user wants hard enforcement from day one and accepts the setup dependency.

### Outcome

**Option A selected (approved).** Admin web launch is not blocked by App Check setup; security rests on the backend-enforced chain (Firebase token → operator doc → RBAC → step-up → audit). Option C is the recommended upgrade path once the admin web provider exists; Option B only with separate explicit approval.

### Constraints that apply (approved)

- If enforcement is later added: `/v1/admin` namespace scoping must be verified first (implementation prerequisite, recorded in Security doc checklist); mobile/production App Check enforcement remains untouched.
- Any future hard enforcement (Option B or C→enforce) requires separate explicit user approval.

- **Status:** **CONFIRMED BY USER — APPROVED (Option A)**

## D-06 — Segregation of duties — ✅ APPROVED (Option A: permission separation only)

- **Problem/current state:** a single operator could approve + suspend + ban + change config with no second pair of eyes. No co-sign machinery exists.
- **Decision (user, 2026-11-24):** **Option A APPROVED** — granular permission-separation design and permission catalog approved; destructive permissions remain separate; `counterSignedBy` reserved for future use; co-sign deferred; **role-to-person assignments are NOT approved by this decision** and require separate approval.
- **Options:** (a) permission separation only — destructive powers are distinct grants (`drivers.approve` vs `drivers.suspend` vs `users.ban` vs `config.write`); (b) + mandatory co-sign/second-operator approval for suspensions/deactivations; (c) + delayed execution queue.
- **Recommendation:** **(a) for V1.** RBAC matrix already splits these powers; audit makes abuse detectable; team is small so co-sign adds friction without proportional risk reduction. Audit schema reserves `counterSignedBy` for later.
- **Implications:** technical — none beyond existing permission checks; security — relies on grant discipline + audit review; ops — simpler workflows; cost — $0.
- **Dependencies:** RBAC matrix approval (same batch); D-09 step-up covers the highest-risk ops.
- **Approval constraints (approved):** permission separation enforced per-route; revisit co-sign if audit shows abuse patterns or team grows.
- **Status:** **CONFIRMED BY USER — APPROVED (Option A)**

## D-07 — Audit log tamper-evidence beyond append-only — ✅ APPROVED (Option A: append-only Firestore)

- **Problem/current state:** `adminAuditLogs` is append-only in code + rules-denied to clients, but Firestore itself offers no cryptographic tamper-evidence; a compromised Admin SDK credential could rewrite history.
- **Decision (user, 2026-11-24):** **Option A APPROVED** — no audit update/delete paths; contract test enforcing immutability required; audit failure must abort the associated mutation with `AUDIT_UNAVAILABLE`; GCS export remains deferred until D-21 retention is decided and compliance requires it.
- **Options:** (a) append-only Firestore only (V1); (b) + scheduled export to GCS with retention lock; (c) + BigQuery/WORM storage.
- **Recommendation:** **(a) for V1; (b) when compliance/audit requirements demand it.** IAM + rules + zero mutation paths + fail-closed audit writes already provide strong practical integrity for an internal tool.
- **Implications:** technical — (b)/(c) add export job + bucket lifecycle; security — export adds a second tamper-evident copy; ops — export is scheduled, low effort; cost — GCS storage trivial at audit-log volumes.
- **Dependencies:** D-21 (retention period defines export window); scheduler pattern already exists.
- **Approval constraints (approved):** zero update/delete paths enforced by contract test; audit failure aborts mutation (`AUDIT_UNAVAILABLE`); export design must preserve field-level diffs and never include unmasked PII; export deferred pending D-21 + compliance need.
- **Status:** **CONFIRMED BY USER — APPROVED (Option A)**

## D-08 — Bulk actions — ✅ APPROVED (Option A: no bulk actions in V1)

- **Problem/current state:** review queues could make single-target actions tedious; bulk ops risk mass mistakes/abuse.
- **Decision (user, 2026-11-24):** **Option A APPROVED** — no bulk or multi-target admin endpoints; every mutation remains single-target, individually permission-checked, rate-limited and audited; client-side loops provide no bypass since all mutations use the same audited API.
- **Options:** (a) no bulk endpoints in V1 — single-target only; (b) bulk endpoint with per-item audit + partial-failure semantics; (c) client-side repeated calls (effectively unbounded scripting).
- **Recommendation:** **(a).** Explicitly reject (c) — client loops bypass the per-action rate-limit intent. Revisit (b) only if queue volume proves painful.
- **Implications:** technical — simplest; security — caps blast radius per action; ops — more clicks; cost — $0.
- **Dependencies:** none; rate limits already specified.
- **Approval constraints (approved):** no bulk/multi-target endpoints in V1; any future bulk design needs per-item audit + idempotency + reason.
- **Status:** **CONFIRMED BY USER — APPROVED (Option A)**

## D-09 — Step-up authentication — ✅ APPROVED (Option A: `auth_time` + 300s)

- **Problem/current state:** destructive admin actions should require recent re-authentication. Mechanism is confirmed: Firebase token `auth_time` freshness (NOT `iat`).
- **Decision (user, 2026-11-24):** **Option A APPROVED** —
  1. Use Firebase `auth_time`, never token `iat`, for step-up freshness.
  2. Threshold = **300 seconds**.
  3. Step-up operation list = exactly as documented (API spec ⬆ markers): `users.ban`, `users.deactivate`, `drivers.suspend`, `rides.force-cancel`, `operators.write`, `config.write` PUTs, `finance.write`, `disputes.write`.
  4. `users.unban`, `users.reactivate`, `drivers.reactivate` remain **excluded** from mandatory step-up in V1 — but must still be permission-gated, audited and rate-limited.
  5. MFA remains a separate future decision — not implemented, not assumed.
  6. Revisit restoration step-up requirements if audit evidence indicates abuse.
- **Implications:** technical — `requireStepUp` middleware checks `auth_time` age, 403 `STEP_UP_REQUIRED`; admin web re-auths and retries; security — bounds stolen-token usefulness for destructive ops; ops — occasional re-auth prompts; cost — $0.
- **Dependencies:** D-24 (admin sign-in method determines re-auth UX — OTP resend vs password re-entry); D-15 admin web.
- **Approval constraints (approved):** mechanism fixed as `auth_time`; threshold 300s; op list exactly as documented — `users.unban`/`users.reactivate`/`drivers.reactivate` excluded from mandatory step-up in V1 but remain permission-gated, audited, rate-limited; revisit restoration step-up on audit evidence of abuse; MFA separate future decision.
- **Status:** **CONFIRMED BY USER — APPROVED (Option A)**

## D-10 — Account deletion policy — PROPOSED — AWAITING USER APPROVAL

- **Problem/current state:** requirement says "permanently deactivate where policy allows"; no deletion exists; ride/payment/financial records reference user docs.
- **Options:** (a) soft-deactivate only (`isActive=false`/`deactivatedAt`) — V1; (b) + PII anonymization job after retention period; (c) hard delete — rejected.
- **Recommendation:** **(a) for V1; (b) as a later job once D-21 retention is set and legal/privacy review confirms.** Deactivation preserves referential integrity for rides, ratings, disputes, audit.
- **Implications:** technical — deactivation already specified; anonymization needs a defined field list + job; security — anonymization reduces PII at rest long-term; ops — support runbook for "deleted" requests = deactivate + note; cost — trivial.
- **Dependencies:** D-21 (retention), D-07 (audit export may retain IDs), D-04 constraints (KYC text fields also need anonymization coverage).
- **Approval constraints:** no hard-delete endpoint ever in this design; anonymization requires explicit field list + retention period + legal sign-off before implementation.

## D-11 — Driver status model (two-field ownership) — PROPOSED — AWAITING USER APPROVAL

- **Problem/current state:** need consistent semantics for application review vs dispatch eligibility; `users.driverStatus` (4 values) is read by all eligibility gates; `drivers.driverStatus` (6 values) is unwritten today.
- **Options:** (a) two-field split per Data Model §2.2 transition table — capability flag vs review lifecycle, updated atomically; (b) single extended field — rejected (would touch every eligibility gate).
- **Recommendation:** **(a).** Zero risk to existing gates; admin queues get rich review states; lifecycle module (D-03, approved) keeps them consistent.
- **Implications:** technical — `drivers.driverStatus` + `applicationVersion` + review fields added; gates unchanged; security — review states never grant eligibility (only `approved` does); ops — queues filter on `drivers.driverStatus`; cost — none.
- **Dependencies:** D-03 (approved lifecycle module), D-16 (resubmission), D-23 (driver-facing status).
- **Approval constraints:** Data Model §2.2 transition table is normative; any status-semantic change requires updating gates' expectations explicitly.

## D-12 — Admin notes storage — PROPOSED — AWAITING USER APPROVAL

- **Problem/current state:** admins need internal notes on users/drivers without polluting domain docs.
- **Options:** (a) `adminUserNotes/{autoId}` as fully specified in Data Model §1.4; (b) embed notes in domain docs — rejected (PII bleed, unbounded docs); (c) defer notes entirely.
- **Recommendation:** **(a)** — design already complete and consistent across Data Model, API spec §6, screens F7/F12.
- **Implications:** technical — one collection + service + 4 endpoints; security — internal-only (never exposed to user app); ops — append-only, corrections via new note; cost — negligible.
- **Dependencies:** none beyond P0 foundation.
- **Approval constraints:** notes append-only; `note.add` audited without copying body into audit; read via `users.read`/`drivers.read`, write via `users.write`/`drivers.write`.

## D-13 — Admin ride interventions beyond cancel — PROPOSED — AWAITING USER APPROVAL

- **Problem/current state:** ops may need to stop a problematic ride; no admin ride mutation exists.
- **Options:** (a) force-cancel only (V1); (b) + force-transition between states; (c) + manual driver assignment/dispatch override.
- **Recommendation:** **(a).** Force-transition and manual assign bypass the offer/assignment invariants and courier custody rules; force-cancel covers the real need with normal cancel semantics + notifications.
- **Implications:** technical — `RideService.adminForceCancel` reusing cancel internals + `cancelledBy='admin'` + `adminIntervention`; security — step-up + reason + audit; ops — escape hatch for stuck/abusive rides; cost — none.
- **Dependencies:** courier `v2HasCustody` boundary must be verified at implementation (`CUSTODY_LOCKED`); D-09 step-up; one-active-ride guard (DR-008, pending implementation) doesn't affect cancel safety.
- **Approval constraints:** force-cancel only; must emit normal outbox events; forbidden once parcel in custody; never used to mutate fare/state arbitrarily.

## D-14 — Admin access to driver location — PROPOSED — AWAITING USER APPROVAL

- **Problem/current state:** requirement mentions "last known location subject to privacy and authorization"; no location history is persisted (geo markers transient, RTDB tripLocations deleted on terminal).
- **Options:** (a) no location access in V1; (b) live-marker ops view in Phase 2 (current position only, permission-gated); (c) location history retention — needs privacy policy/legal first.
- **Recommendation:** **(a) for V1; (b) possible later; (c) deferred pending privacy policy.** Nothing to show today anyway — the data doesn't persist.
- **Implications:** technical — none V1; security — location is sensitive; any future view needs dedicated permission + audit; ops — dispatch already works without admin location access; cost — none.
- **Dependencies:** privacy policy decision (external); geo marker freshness semantics (already defined in metrics doc).
- **Approval constraints:** no location-history collection in V1; any future access is a separate decision with privacy review.

## D-15 — Admin frontend: separate app — PROPOSED — AWAITING USER APPROVAL

- **Problem/current state:** admin UI must not touch mobile release cadence or expose admin capability in the consumer app.
- **Options:** (a) separate `admin-web/` app + Firebase Auth web SDK calling `/v1/admin` only; (b) admin mode embedded in Flutter app — rejected (admin surface in consumer binary is a risk); (c) third-party admin framework — rejected (custom domain fits better, extra dependency).
- **Recommendation:** **(a).** Clean isolation, independent deploys, Firebase Auth reuse.
- **Implications:** technical — new web app consuming documented APIs only; security — smaller attack surface than embedding; ops — separate hosting (static/hosting — decide at build); cost — minimal static hosting; branding deferred to Ora identity.
- **Dependencies:** D-24 (auth method), D-05 (App Check deferred — web client won't be blocked), D-01 (same backend).
- **Approval constraints:** admin web calls `/v1/admin` only — never Firestore directly; no admin capability shipped in mobile app.

## D-16 — Driver self-service resubmission — PROPOSED — AWAITING USER APPROVAL

- **Problem/current state:** rejected/info-requested drivers need a path to fix and resubmit; today re-submit while `pending` overwrites and `suspended` → 403; `rejected`/`info_requested` states don't exist yet.
- **Options:** (a) allow `POST /v1/drivers/onboarding` resubmission from `rejected|info_requested` → `applicationVersion++` → `drivers.driverStatus='pending'`; (b) admin-only resubmission via reopen — rejected as sole path (poor UX, admin bottleneck).
- **Recommendation:** **(a)** — standard pattern; `applicationVersion` guards stale reviews; `canResubmit` flag in status endpoint tells the app when to show the form.
- **Implications:** technical — onboarding service accepts two more source states + clears review fields; security — resubmission is self-service, still goes through review; ops — fewer admin touches; cost — none.
- **Dependencies:** D-11 (status model), D-23 (status endpoint), D-03 (lifecycle module executes transition).
- **Approval constraints:** resubmission only from `rejected|info_requested` — never from `approved|suspended`; increments `applicationVersion`; audit `driver.resubmit`.

## D-17 — User notifications on admin actions — PROPOSED — AWAITING USER APPROVAL

- **Problem/current state:** suspension/ban/approval should reach the user; FCM outbox pipeline exists but no `admin.*`/`driver.application.*` event types exist.
- **Options:** (a) state-only — user discovers via app errors/status screens; (b) + new outbox event types (`driver.application.approved|rejected|info_requested`, `admin.account.restricted`) via existing projectors; (c) SMS — no infra, rejected for now.
- **Recommendation:** **(b)** — cheap reuse of durable pipeline; driver status endpoint (D-23) remains the authoritative channel so push is enhancement, never sole notification. Ship as P1/P2 item, not a blocker.
- **Implications:** technical — new event types + projector allowlist entries + token targeting; security — identifiers-only payloads (no PII/reasons in push); ops — users informed promptly; cost — FCM free tier, negligible.
- **Dependencies:** D-23 (status endpoint is the reliable channel regardless); outbox projector patterns already exist.
- **Approval constraints:** push payloads identifiers-only; reason text never in push; status endpoint must work without push.

## D-18 — Pricing rules & fee policy write path — PROPOSED — AWAITING USER APPROVAL

- **Problem/current state:** `pricingRules`/`feePolicies` are seed-only via scripts; admin needs validated write path without breaking historical `pricingSnapshots`.
- **Options:** (a) admin PUT endpoints — validated upsert, `version` bump, `updatedBy`, audit diff; (b) keep script-only — rejected (no audit trail, ops burden).
- **Recommendation:** **(a)** — snapshots already freeze per-ride so changes only affect new estimates; `config.write` + step-up on PUTs.
- **Implications:** technical — write methods on existing repositories + admin routes; security — config abuse = economic damage → step-up + audit + rate limit; ops — self-service config; cost — none.
- **Dependencies:** D-19 (categories must exist for category-keyed rules); `config.write` permission.
- **Approval constraints:** validated upsert only — no raw doc writes; every change audited with before/after diff; never retroactively alter snapshots.

## D-19 — Categories: new collection vs hardcoded — PROPOSED — AWAITING USER APPROVAL

- **Problem/current state:** `DRIVER_VEHICLE_CATEGORIES` is a hardcoded const (6 slugs); `rides.category`/`vehicle.category`/`pricingRules` keys all depend on those slugs.
- **Options:** (a) `categories` collection seeded with the 6 existing slugs + const fallback during transition; (b) config-doc toggles only — can't add categories cleanly; (c) full DB-driven migration — overkill now.
- **Recommendation:** **(a)** — admin-manageable catalog without breaking existing references; `categoryId`/`kind` immutable; deactivation non-destructive.
- **Implications:** technical — new collection + read fallback + admin CRUD; security — `config.write` gated; ops — categories manageable without deploys; cost — negligible.
- **Dependencies:** D-18 (pricing rules keyed by category); ride-create validation must read collection with fallback.
- **Approval constraints:** seed docs mirror existing slugs exactly; never delete referenced categories; deactivation hides from new selection only.

## D-20 — Payment/financial admin scope — PROPOSED — AWAITING USER APPROVAL

- **Problem/current state:** payments/ledger/payouts are unimplemented; only fare/payout snapshot fields exist on rides.
- **Options:** (a) read-only financial metrics now (`finance.read` on aggregates/snapshots); write-ops deferred until payments ship; (b) defer all finance admin.
- **Recommendation:** **(a)** — dashboard financial visibility is computable today from ride snapshots; write-ops (`finance.write`) stay dormant until payment collections exist.
- **Implications:** technical — read endpoints on existing fields; security — financial data permission-gated + masked aggregates; ops — visibility without premature write surface; cost — none.
- **Dependencies:** payments roadmap (external); D-22 aggregation for financial metrics.
- **Approval constraints:** no financial write endpoints until payment backend exists and is separately approved; `finance.read`/`finance.write` permissions defined but write path inert.

## D-21 — Audit log retention period — PROPOSED — AWAITING USER APPROVAL

- **Problem/current state:** retention undefined; need a concrete period for compliance, disputes, financial reconciliation, abuse investigation.
- **Options:** (a) **7 years** hot in Firestore then archive/export; (b) indefinite retention; (c) 2 years.
- **Recommendation:** **(a) 7 years** — covers dispute windows, financial reconciliation cycles, and abuse investigations; matches common fintech/audit practice; storage cost at audit-log volumes is small (ESTIMATE — verify at implementation).
- **Implications:** technical — Firestore TTL or scheduled archive job (mechanism deferred to D-07 export design); security — bounded PII retention aligns with D-10 anonymization; ops — predictable lifecycle; cost — ESTIMATE small; verify.
- **Dependencies:** D-07 (archive/export mechanism); D-10 (anonymization interacts with retention).
- **Approval constraints:** retention applies to `adminAuditLogs` (and by extension `adminUserNotes` follows account retention); archive must preserve queryability or documented export format.

## D-22 — Dashboard aggregation budget & freshness — PROPOSED — AWAITING USER APPROVAL

- **Problem/current state:** dashboard must be useful without full-collection scans or surprising bills.
- **Proposal (as documented):** live bounded `count()` for queue depths (billed per ~1k index entries — ESTIMATE ≤ ~50 reads/dashboard load); 15-min scheduler aggregates into `adminMetrics`; online-driver count = 15-min-fresh aggregate using N3-equivalent freshness gates (never raw `geoDrivers` count); on-demand reports bounded by mandatory range+cap; every section carries `computedAt` staleness.
- **Recommendation:** approve as specified — separates live ops metrics from historical analytics and keeps costs predictable.
- **Implications:** technical — `/v1/internal/admin/aggregate` worker + `adminMetrics` collection + indexes; security — aggregates contain no PII; ops — freshness labels prevent over-trusting stale numbers; cost — ESTIMATE bounded; monitor Firestore usage metrics post-launch.
- **Dependencies:** D-01 (scheduler pattern reuse); metrics doc is the spec.
- **Approval constraints:** no whole-collection scans ever; cost figures are estimates — validate against billing data before/after launch; refresh cadence tunable without re-approval within stated bounds.

## D-23 — Driver-facing status endpoint shape — PROPOSED — AWAITING USER APPROVAL

- **Problem/current state:** drivers need reliable application status (state, info-requested notice, rejection reason, next action) without depending on FCM push.
- **Proposal (as documented):** `GET /v1/drivers/application-status` returning `applicationStatus`, `capabilityStatus`, `infoRequestNote`, `rejectionReason`, `applicationVersion`, `submittedAt`, `reviewedAt`, `canResubmit`, `nextAction` — sourced from `drivers.driverStatus` + review fields + `users.driverStatus`.
- **Recommendation:** approve as specified — own-data only, authenticated driver caller, powers mobile registration/status screens.
- **Implications:** technical — one read endpoint joining two docs; security — caller-scoped (no cross-user); ops — reliable status channel; cost — trivial.
- **Dependencies:** D-11 (status model), D-16 (resubmission/canResubmit), mobile app consumption (separate workstream).
- **Approval constraints:** returns caller's own data only; fields exactly per API spec §3.4; push notifications never the sole channel.

## D-24 — Admin web auth method — PROPOSED — AWAITING USER APPROVAL

- **Problem/current state:** admin sign-in mechanism for the future `admin-web/` app; backend is agnostic (any valid Firebase ID token + operator doc works).
- **Options:** (a) phone OTP — same as consumer app; (b) email/password; (c) both.
- **Recommendation:** **(b) email/password** for admin operators — separates admin credentials from consumer phone-OTP flow, easier operator provisioning/revocation, and avoids tying admin access to SIM/phone-number changes. Backend requires no change either way.
- **Implications:** technical — Firebase console enables email/password provider; web SDK sign-in; security — password policy + optional future MFA (separate decision); ops — operator onboarding via email; cost — $0.
- **Dependencies:** D-15 (admin web app), D-09 (step-up re-auth UX — password re-entry is smoother than OTP resend), Firebase console access (user action).
- **Approval constraints:** requires enabling the provider in Firebase console (user-side action, not code); backend remains provider-agnostic; decision can be revisited before admin web launch without API changes.

## D-25 — App Check for admin web — ➖ NOT APPLICABLE (superseded by D-05)

- **Requirement:** honest App Check status (reconciliation item N).
- **Resolution:** D-25 duplicated D-05's scope. D-05 is now **APPROVED (Option A — defer enforcement for `/v1/admin`)**; its approved constraints (namespace scoping verification, untouched mobile enforcement, future hard-enforcement approval) fully cover this entry. No separate decision needed.
- **Status:** **NOT APPLICABLE — superseded by D-05**

---

## Suggested approval order (for review efficiency)

1. **Driver-review chain:** D-09 (step-up threshold/op list) → D-11 (status model) → D-16 (resubmission) → D-23 (status endpoint) — these four define the manual-approval workflow end-to-end.
2. **Audit & retention:** D-21 (retention) → D-07 (tamper-evidence/export) → D-10 (deletion/anonymization) — D-10 depends on D-21; D-07 export depends on D-21 window.
3. **Operations policy:** D-12 (notes), D-13 (ride interventions), D-06 (SoD), D-08 (bulk), D-14 (location) — independent, low coupling.
4. **Config & metrics:** D-18 (pricing/fee writes) → D-19 (categories) → D-22 (aggregation budget) → D-20 (finance scope) — D-18 depends on D-19 category keys; D-20 read metrics depend on D-22.
5. **Frontend & comms:** D-15 (admin web) → D-24 (auth method) → D-17 (notifications) — D-24 needs Firebase console decision alongside D-15; D-17 is independent but pairs with D-23.

## Summary — awaiting user approval

| Status | Decisions |
|---|---|
| CONFIRMED BY USER | **D-01** (Option A — same-service `/v1/admin`); **D-02** (Option A — vendor spec now, build Phase 3, marketplace SoT); **D-03** (Option A — shared `driver_lifecycle.ts`, constraints recorded); manual driver approval; one-active-ride-per-passenger (DR-008); **D-04** (Option A — KYC images deferred for V1, text-only, no paid Storage); **D-05** (Option A — App Check deferred for `/v1/admin`, namespace scoping to verify); `expectedApplicationVersion` required; `auth_time` step-up mechanism |
| PROPOSED — AWAITING USER APPROVAL | D-06 (SoD: permission separation), D-07 (audit: append-only now/export later), D-08 (no bulk V1), D-09 (step-up: 300s + op list), D-10 (soft-deactivate now/anonymize later), D-11 (two-field driver status), D-12 (adminUserNotes), D-13 (force-cancel only), D-14 (no location V1), D-15 (separate admin-web), D-16 (driver resubmission), D-17 (push events via outbox), D-18 (config PUT endpoints), D-19 (categories collection), D-20 (finance read-only now), D-21 (7y audit retention), D-22 (tiered aggregation), D-23 (application-status endpoint), D-24 (email/password admin auth) |
| DEFERRED | KYC image upload/preview implementation (D-04 Option A approved — Option B conditional on future billing approval); **vendor admin implementation (D-02 — spec approved, build Phase 3)**; bulk actions; payments/finance write; broadcast notifications; reports/moderation features; location history; MFA |
| NOT APPLICABLE | hard deletion (rejected by design); separate admin database (Firestore shared); D-25 (superseded by D-05) |
