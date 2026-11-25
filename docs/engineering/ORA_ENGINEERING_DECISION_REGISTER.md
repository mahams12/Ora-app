# Ora Engineering Decision Register

Status legend: `PENDING — USER REVIEW` = needs owner decision before any
implementation. `DECIDED` = approved direction already recorded.

Evidence basis: code inspection 2026-11-24, branch
`devin/1794389046-orange-profile-merge` (working tree contains the
uncommitted `cost-optimization-local` work). All cost figures are
**[CALC]** estimates from verified unit prices — not billing data.

---

## DR-001 — Driver invite discovery path

- **Problem:** While a driver sits on the driver home screen, the only
  invite-discovery trigger is the FCM `RIDE_DISPATCH_INVITE` nudge
  (`mobile/lib/core/notifications/dispatch_fcm_service.dart:224-236`).
  `GET /v1/rides/invited` is only fetched when the Open Rides screen or
  invites section mounts (`driver_invites_section.dart:133-141`,
  `driver_open_rides_view.dart:67`) — there is **no periodic invite
  poll** for an online foregrounded driver. With a 20 s server invite
  TTL (`N4_INVITE_TTL_MS`), a delayed/dropped FCM (OEM doze — common on
  Samsung/Xiaomi devices in the target market) means the driver never
  sees the invite; dispatch simply moves to the next wave.
- **Options:**
  1. Bounded invite poll while online+foregrounded (e.g. 10–15 s,
     invite-boosted to 3–5 s when any invite is actionable). Cost:
     ~240–360 reads/driver-day extra at 15 s cadence — small vs
     presence cost. Pro: deterministic discovery, FCM stays a hint.
     Con: modest steady-state request volume.
  2. FCM-only (current). Pro: zero poll cost. Con: missed invites on
     unreliable push; longer passenger match times.
  3. RTDB invite channel. Con: Spark 100-connection cap, second SDK
     surface — rejected in cost audit (§8.3/8.4).
- **Cost implications:** Option 1 ≈ +$0.10–0.40/mo per 1k DAU
  [CALC] — negligible.
- **Recommended:** Option 1 with adaptive cadence tied to
  `driverInviteActivityProvider` (already exists for presence boost).
- **Approval status:** `PENDING — USER REVIEW`
- **Final decision:** —
- **Date/evidence:** 2026-11-24 audit; gap GAP-001.

## DR-002 — Driver onboarding approval model

- **Problem:** `DRIVER_AUTO_APPROVE` defaults to **true**
  (`src/config/driver_auto_approve.ts`, `.env.example:24`). Any
  phone-verified user can self-approve as a driver by submitting a
  syntactically valid CNIC/license/plate
  (`driver_onboarding_service.ts`) — no document upload, no admin
  review, no KYC verification. PII (CNIC, license number, plate) is
  stored plaintext in `drivers/{uid}`.
- **Options:**
  1. Keep auto-approve for launch, add manual review queue later.
     Pro: zero friction now. Con: fake-driver fraud exposure from day
     one; no recourse.
  2. Require admin approval before `driverStatus='approved'` (flip
     `DRIVER_AUTO_APPROVE=false` + build review console). Pro: real
     trust gate. Con: ops overhead, slower driver onboarding.
  3. Auto-approve + post-hoc verification flags (license expiry
     checks, plate format per city, anomaly detection). Middle ground.
- **Cost implications:** Option 2 adds an admin surface (Firestore
  reads only) — ~$0 at launch volumes.
- **Recommended:** Decide before production launch. If cash rides go
  live without review, fraud losses will exceed any engineering cost.
- **Approval status:** **APPROVED — USER DECISION (2026-11-24):
  MANUAL APPROVAL.** See decision detail below.
- **Final decision:** **Manual driver approval.** Phone verification
  must NOT auto-approve. Drivers remain `pending` until an authorized
  Admin reviews and explicitly approves or rejects.
- **Date/evidence:** decided 2026-11-24; gap GAP-002.

### DR-002 decision detail — MANUAL APPROVAL

**Policy (production intent — runtime config unchanged until
implemented):**

- `users.driverStatus` remains the *capability* flag consumed by
  eligibility gates (`approved`-only). It must never become `approved`
  without an admin decision record.
- `drivers.driverStatus` carries the full review lifecycle
  (per admin-platform D-11): `pending` → `under_review` /
  `info_requested` → `approved` | `rejected`; `suspended` is a
  separate admin action; resubmission returns to `pending` with
  `applicationVersion++` (D-16).
- Mapping rule (D-11): `rejected`/`info_requested` →
  `users.driverStatus` stays non-approved (`none` on reject,
  `pending` while under review); `approved` → `users.driverStatus` =
  `approved` + `role='driver'` repair + `approvedBy/At` +
  `driverApprovalSource='admin'`.
- All transitions transactional, idempotent, audit-logged via
  `adminAuditLogs` (admin data model).

**Required backend enforcement (never frontend-only):**

- `DriverOnboardingService.submit` writes `driverStatus='pending'`
  unconditionally in production (the `autoApprove` path becomes
  staging/dev-only or is removed).
- New admin endpoints (per `ORA_ADMIN_PLATFORM_MASTER_PLAN.md` P1)
  perform approve/reject/request-info/resubmit through a shared
  `driver_lifecycle` module (admin D-03) — single source of truth for
  transitions used by both self-onboarding and admin review.
- Eligibility gates already enforce `driverStatus==='approved'` —
  pending/rejected drivers are automatically excluded from
  go-online/location/matching with zero gate changes.
- Reject requires mandatory reason; resubmission allowed from
  `rejected` (version-checked against the reviewer's snapshot).
- Suspend forces driver offline via `DriverAvailabilityService`
  (geo cleanup) — active ride continues to completion.

**RBAC linkage** (`ORA_ADMIN_RBAC_PERMISSION_MATRIX.md`):
`drivers.review.read` (queue), `drivers.review.pii` (CNIC/doc fields,
audit-logged reads), `drivers.approve`, `drivers.reject`,
`drivers.review` (request-info/reopen), `drivers.suspend` —
`verification_admin` can approve/reject/review but deliberately
cannot suspend/ban.

**Audit linkage:** every decision → `adminAuditLogs` entry
(action `<domain>.<verb>`, targetType `driver`, operator id, reason,
applicationVersion).

**Outstanding questions:**
- Review SLA target (pending queue size vs ops staffing)?
- Does `pending` driver see an honest "under review" state in app?
- Step-up auth (admin D-09) required for approve/reject or only for
  suspend/ban? (recommend: approve/reject = normal perm, suspend =
  step-up)
- Auto-approve flag: keep for staging/dev (`DRIVER_AUTO_APPROVE`)
  or remove entirely? Recommend: env-gated, `false` in production.

**Dependencies:** admin platform P0+P1 (operators, RBAC middleware,
audit log, review queue APIs), shared lifecycle module (D-03),
driver-status model decision (D-11). Runtime change
(`DRIVER_AUTO_APPROVE=false`) ships only AFTER approve/reject paths
are live — flipping earlier would strand applicants.

## DR-003 — Avatar/KYC document storage

- **Problem:** `avatarData` (base64 data-URL, ≤400 000 chars) is stored
  inside `users/{uid}` (`services/profile.ts:24-47`) — a document read
  by `loadActor` on nearly every authenticated request and by
  `getAll` batches during N3 matching. Two issues: (a) GAP-003 — the
  32 kb JSON body limit currently makes uploads >~24 KB fail; (b) if
  fixed naively, a ≤400 KB blob sits in the hottest-read document.
  KYC documents (DR-002 manual review) need private storage that
  admins can preview but that is never publicly accessible.
- **User constraint (2026-11-24):** prefers Firebase-based storage but
  **zero additional cost** — no paid storage, no billing upgrade, no
  paid service activation without explicit approval.
- **Approval status:** **CONDITIONALLY APPROVED — $0 usage is
  plausible but NOT guaranteed.** Free quotas are allowances on a
  pay-as-you-go plan with no hard spend cap; zero-cost holds only
  while all quotas are respected AND billing reports confirm it.
  Final option selection (Storage vs Firestore-docs fallback)
  pending owner confirmation + guardrails.
- **Date/evidence:** feasibility verified 2026-11-24 against
  firebase.google.com/pricing; gaps GAP-003, GAP-008.

### DR-003 feasibility findings — Firebase Storage at $0

> **Verification note (2026-11-24, second pass):** figures below were
> re-verified against firebase.google.com/pricing and Google Cloud
> free-tier docs. Free allowances are **quotas, not guarantees** —
> Blaze has no hard spend cap; exceeding any quota bills
> automatically. "Zero additional cost" is therefore a *target that
> requires monitoring*, not an inherent property of the service.

**Plan prerequisite:** Cloud Storage for Firebase **requires the
Blaze (pay-as-you-go) plan** — Spark projects cannot create or access
any bucket (API returns 402/403; since Feb 2026 even legacy
`appspot.com` access requires Blaze). `ora-app-d8112` is **already on
Blaze** (billingEnabled since 2026-10-21, per prior cloud inventory)
→ **no plan upgrade needed**; but "already on Blaze" also means
**there is no hard cap** — any usage beyond no-cost quotas bills the
linked payment method.

**No-cost quotas (default `*.firebasestorage.app` bucket AND any
additional buckets, Blaze):**
- Stored: **5 GB-months**
- Downloaded: **100 GB/month**
- Upload operations: **5,000/month**
- Download operations: **50,000/month**
- **Region restriction:** no-cost quotas apply ONLY in `us-central1`,
  `us-west1`, `us-east1` — bucket MUST be created in `us-central1`
  (matches Cloud Run/Firestore region). A bucket anywhere else pays
  from the first byte.
- Quotas are **project-level** (not per-app/per-bucket) and no-cost
  usage on Blaze is **calculated daily**, refreshed at midnight.
- **Egress geography caveat:** the 100 GB/mo free download applies to
  qualifying destinations — Google documents it as North-America
  egress excluding Australia/China. Ora's users are primarily in
  Pakistan (asia-south). Whether PK-destined downloads qualify for
  the free 100 GB **must be verified in billing reports** — if not,
  avatar/KYC downloads could bill egress from the first GB
  (~$0.12/GB class). KYC is admin-only and low-volume; avatar loads
  are the exposure. This is the single largest uncertainty in the
  $0 claim → **monitoring is mandatory before enabling**.

**Beyond-quota pricing (what "not free" looks like):**
- Storage: Google Cloud Storage Standard rates (~$0.02–0.026/GB-mo
  in us-central1)
- Download/egress: ~$0.12/GB (first-tier NA egress; asia egress may
  price higher — verify)
- Ops: upload ~$0.05/10K, download ~$0.004/10K class
- Legacy `*.appspot.com` buckets have DIFFERENT quotas (5 GB stored,
  1 GB/**day** download, 20K uploads/**day**, 50K downloads/day) —
  do not confuse the two bucket types.

**Usage estimate [CALC] — with explicit caveats:**
- Avatar: 512 px JPEG q≈80 ≈ 40–80 KB. 1k DAU × ~30% avatar adoption
  ≈ 300 files ≈ ~20 MB stored — 0.4% of 5 GB quota. Storage side is
  safe by ~250×.
- KYC docs: ~3 files/application × ~300 KB ≈ 1 MB/application.
  500 applications/mo ≈ 0.5 GB — inside quota.
- Upload ops: few hundred/mo ≪ 5k/mo **at launch**; at ~10k+ DAU with
  heavy avatar churn this quota is the first to bind → monitor.
- Download ops: 50k/mo is generous for avatars (self-view only today)
  + admin KYC previews.
- Egress: the 100 GB/mo figure is the binding constraint IF Pakistan
  destinations don't qualify — worst case avatar traffic
  (~300 avatars × ~60 KB × a few loads/day ≈ tens of MB/day ≈
  ~1 GB/mo) is still trivially small in absolute terms; even 10×
  that ≈ ~$1–2/mo. **Conclusion: even if egress is billed, absolute
  cost stays single-digit $/mo at launch scale — but that is a
  billing event, not "free", so alerts are required.**

**Verdict: CONDITIONALLY FEASIBLE — likely ~$0 but NOT guaranteed.**
Conditions that must ALL hold for the $0 claim:
1. Bucket created in `us-central1` (hard requirement).
2. Project stays on Blaze with billing alerts on Storage SKUs.
3. Usage stays inside all four quotas (storage, GB-downloaded,
   uploads, download-ops) — verified monthly via billing reports.
4. Egress-to-PK qualification verified from actual billing data
   after first real usage (cannot be proven from docs alone).
5. No secondary/additional buckets outside quota regions.

**Required guardrails before enabling (all console/config, need
approval):**
- Billing budget alert scoped to Cloud Storage SKUs (existing $1
  budgets may not isolate Storage — verify coverage).
- Log-based/metrics alert on Storage bytes-downloaded + upload-ops
  approaching quota (e.g. 50%/80%/100%).
- Documented kill-switch: if any quota is approached, pause uploads
  client-side (feature flag) rather than paying.

**Access separation (required):**
- **Avatar:** semi-public within app (own profile + eventually
  counterpart display) → Firebase Storage object with download-token
  or rules-gated read; `users/{uid}` stores only `avatarPath`/
  `avatarUpdatedAt` metadata — never binary.
- **KYC documents:** strictly private — `driverDocuments` paths under
  a private prefix; Storage rules deny all client access; admin
  previews via short-lived **signed URLs** minted by Admin SDK after
  `drivers.review.pii` permission + audit-logged read. Never public,
  never in Firestore as base64.

**Alternatives if owner requires guaranteed $0 (no billing exposure):**
- (F1) **Firestore private docs:** avatar in dedicated
  `userAvatars/{uid}` doc (read only on profile screen); KYC docs as
  base64 in `driverDocuments/{id}` docs (collection already
  rules-denied; Admin-SDK-only; ≤1 MB/doc limit). Cost: Firestore
  reads/writes only — Firestore free allotments are daily and far
  larger relative to this volume; ~33% base64 inflation; no egress
  geography ambiguity (Firestore egress pricing differs and is also
  quota'd). **This is the only option with zero billing-account
  exposure for the storage layer itself.**
- (F2) Status quo + GAP-003 fix only (route-scoped body limit) —
  cheapest but keeps 400 KB in hot doc (GAP-008 remains).

**Recommendation:** present both to owner — (S) Firebase Storage
(us-central1) with mandatory quota monitoring = best long-term
pattern, small residual billing risk; (F1) Firestore private docs =
strictly zero-new-billing-surface fallback. **DR-003 stays
CONDITIONALLY APPROVED until owner picks AND guardrails are in
place.** Do not enable Storage or create the bucket without explicit
owner approval (bucket creation is an infrastructure change).

## DR-004 — Production rollout of cost-optimization work

- **Problem:** The validated cost-optimization branch work (adaptive
  presence, merged cursor, adaptive freshness, coalesced sweeps,
  pricing cache, N3 latency hardening) is **uncommitted in the working
  tree**; prod still runs the pre-optimization image with Redis+VPC
  connector (~$60–95/mo standing), paused schedulers, and no
  `FIREBASE_DATABASE_URL` (trip tracking silently dead).
- **Options:** (already fully planned in
  `docs/audits/ORA_COST_OPTIMIZATION_PLAN.md` §PROD-ROLLOUT)
  1. Deploy clean `7449cc7` worktree first → resume 6 schedulers →
     rollback window → delete Redis/connector/secret → later deploy
     cost-opt image with flags + coalesced scheduler.
  2. Single deploy of the cost-opt image with flags ON, skipping the
     intermediate step. Faster but couples Redis-removal and
     flag-enablement in one blast radius.
- **Recommended:** Option 1 (two-stage, already preflighted).
- **Approval status:** `PENDING — USER REVIEW` (each step needs
  explicit approval per standing rules)
- **Final decision:** —
- **Date/evidence:** 2026-11-24 audit; gap GAP-004.

## DR-005 — Rate limiting for production

- **Problem:** `createRateLimiter` is in-memory per instance
  (`middleware/rate_limit.ts:4` — self-documented "LOCAL ONLY — NOT
  PRODUCTION READY"). With `maxScale=10`, a uid+IP effectively gets
  10× the configured limit; cold starts reset buckets.
- **Options:**
  1. Accept per-instance limits at launch (60 req/min/uid is already
     generous; abuse needs many instances to matter). Revisit at
     scale.
  2. Cloud Armor edge rate limit (L7) — no code change, per-IP rules.
  3. Firestore/RTDB-backed distributed limiter — adds read/write cost
     per request; not worth it.
- **Recommended:** Option 1 now + Option 2 (Cloud Armor) at production
  hardening — cheapest correct answer.
- **Approval status:** `PENDING — USER REVIEW`
- **Final decision:** —
- **Date/evidence:** 2026-11-24 audit; gap GAP-005.

## DR-006 — Trip-mode location authz caching

- **Problem:** Every trip-mode `/v1/location/update` packet (4 s
  cadence) performs `assertTripPublishAuthorization` → a `rides/{id}`
  doc read (`location_update_service.ts:343-375`). ≈900 extra reads per
  driver-hour of trip time.
- **Options:**
  1. Short-TTL (10–15 s) authz cache keyed by rideId. Risk: up to TTL
     of trip-location writes after ride termination — passenger RTDB
     listener is already gated by ride state
     (`trip_location_listen_gate.dart`), so impact ≈ nil.
  2. Keep per-packet read (current). Correct, costs ~25% of trip-mode
     read volume.
  3. Validate inside the stream-store transaction — still a read, no
     savings.
- **Recommended:** Option 1, TTL ≤15 s, invalidate on ride-state
  transitions via existing outbox/state path or simply accept the
  bounded staleness.
- **Approval status:** `PENDING — USER REVIEW`
- **Final decision:** —
- **Date/evidence:** 2026-11-24 audit; gap GAP-011.

## DR-007 — outboxEvents retention

- **Problem:** `outboxEvents` docs reach `DELIVERED`/`DEAD_LETTER` and
  are never deleted — unbounded collection growth
  (`delivery/*_fcm_projector.ts`). Sweeps filter by `publishState` so
  there is no read amplification today, but storage grows forever.
- **Options:**
  1. Add `expiresAt` to outbox docs at write time + include
     `outboxEvents` in `ExpiresAtCleanupService`. ~20 lines, uses
     existing machinery.
  2. Periodic delete sweep by publishState+createdAt. Similar cost,
     more code.
- **Recommended:** Option 1.
- **Approval status:** `PENDING — USER REVIEW`
- **Final decision:** —
- **Date/evidence:** 2026-11-24 audit; gap GAP-009.

## DR-008 — One active ride per passenger

- **Problem:** `createRide` has no guard against a passenger holding
  multiple concurrent active rides (audit finding R-1).
- **Approval status:** **APPROVED — USER DECISION (2026-11-24).**
- **Final decision:** A passenger may have only ONE active ride at a
  time, enforced at the **backend transaction level** — never
  frontend-only.

### DR-008 decision detail

**Definition of "active" (non-terminal) states** — the same set the
mode-switch guard already uses (`services/users.ts:21-30`
`PASSENGER_BLOCK_STATES`):

```
SEARCHING, OFFERS_AVAILABLE, DRIVER_ASSIGNED, DRIVER_EN_ROUTE,
DRIVER_ARRIVED, RIDE_STARTED, DELIVERY_FAILED, RETURNING
```

Terminal (do NOT block rebooking): `RIDE_COMPLETED`, `RETURNED`,
`RIDE_CLOSED`, `CANCELLED`, `EXPIRED`, `NO_SHOW`.
(`RIDE_STATES` union: `rides/types.ts:1-16`.)

**Enforcement design (PENDING IMPLEMENTATION + VERIFICATION — the
approach below is the recommended candidate, not yet proven in code):**

### Why a query-inside-transaction alone is NOT sufficient

A `rides WHERE passengerId==uid AND state IN (active)` query inside
`createRide`'s transaction has a **phantom-read hole**: when the
result set is empty, there are no documents for Firestore's
optimistic concurrency to conflict on. Two simultaneous
`createRide` transactions can both read "no active ride", both write
their own new ride doc (different doc IDs → no write conflict), and
both commit → two active rides. **This must not ship as the sole
guard.** A query-based check is acceptable only as a *secondary*
validation, never as the race closer.

### Recommended approach: per-passenger active-ride pointer document

Use a deterministic document as the serialization point — the
standard Firestore pattern for "one-of" constraints:

- New collection, e.g. `passengerActiveRides/{passengerId}` (one doc
  per passenger, created lazily). Fields: `activeRideId`,
  `rideState`, `updatedAt`.
- **Acquire (inside `createRide` tx):**
  1. Idempotency replay check first (returns original ride — replay
     must NOT 409).
  2. `tx.get(pointerRef)` — a single-document read of a doc that
     ALWAYS exists after first use (pre-create it in `registerUser`
     or lazily inside the tx via `tx.set` when absent).
  3. If `activeRideId` set → load that ride's state; if non-terminal
     → throw `ACTIVE_RIDE_EXISTS` (409) + `activeRideId`. If the
     pointed-to ride is terminal (pointer is stale) → overwrite.
  4. `tx.set(rideRef, …)` + `tx.set(pointerRef, {activeRideId:
     newRideId, rideState:'SEARCHING', updatedAt})` — both in the
     SAME transaction.
- **Why this closes the race:** both concurrent transactions read
  and write the SAME `passengerActiveRides/{uid}` doc. Firestore
  transactions conflict on that document → the loser retries → on
  retry it sees the winner's `activeRideId` → 409. Deterministic,
  single-doc, no query phantom.
- **Release:** every transition to a terminal state must clear the
  pointer **inside the same transaction that flips `state`**:
  `cancelRide` (passenger+driver cancel paths), `completeRide`,
  `expireRide` (incl. sweep path), `markNoShow`, courier
  `completeReturn`/`cancelReturn`, `transitionRide` terminal edges.
  Implementation must enumerate ALL terminal writers — a missed
  writer leaves the passenger permanently 409'd (fail-safe direction:
  blocks rebooking, never allows duplicates — but still a bug).
  A defensive fallback: on acquire, if pointer's ride is terminal,
  treat as stale and overwrite (self-healing).
- **Stale-pointer edge cases:** ride doc deleted/expired without
  pointer update → acquire path re-reads pointed ride state and
  self-heals; pointer pointing at nonexistent ride → same.
- **Cost:** +1 doc read + 1 doc write per createRide, +1 write per
  terminal transition — negligible.
- **Rules/security:** `passengerActiveRides` is server-only → add to
  `firestore.rules` deny-by-default (catch-all already covers it;
  verify no explicit allow needed — none).
- **Alternative considered:** keep query-check + rely on tx retry —
  REJECTED (phantom read, proven above). Alternative: deterministic
  ride doc ID per passenger-slot — rejected (breaks rideId
  randomness/lookup model).

**Index requirement:** with the pointer design, NO new composite
index is needed for enforcement (single-doc get). The optional
secondary query-check (`passengerId+state`) would need
`rides(passengerId, state)` — verify in `firestore.indexes.json` at
implementation; a `passengerId,state,createdAt` variant already
exists but may not cover equality-IN without createdAt.

**Tests required (must all pass before enabling):**
1. Two concurrent `createRide` calls, same passenger, distinct
   idempotency keys → exactly one 201, one 409 `ACTIVE_RIDE_EXISTS`.
2. Repeat ×N (e.g. 20-way) to exercise tx-retry path.
3. Rebook after each terminal state: CANCELLED, EXPIRED, COMPLETED,
   NO_SHOW, RETURNED, RIDE_CLOSED → all allowed.
4. Idempotency-Key replay of the original create → returns original
   ride, NOT 409.
5. Stale pointer (ride terminal but pointer uncleared — simulate
   missed writer) → acquire self-heals, create succeeds.
6. Courier/buy-deliver/multi-stop serviceTypes → same guard.
7. Driver-cancel vs passenger-cancel vs sweep-expiry → pointer
   cleared in each path (enumeration test over terminal writers).

**Open verification items:**
- Confirm every terminal-state writer is enumerated before merge
  (grep `state:` terminal assignments in `ride_service.ts`).
- Decide whether pointer doc is created at register or lazily
  (lazy inside tx is fine; register-time is cleaner).
- 409 body shape + client handling (`activeRideId` deep-link).

**Status:** approach = `PENDING IMPLEMENTATION & VERIFICATION` —
decision APPROVED, correctness not yet demonstrated. Do not enable
without the concurrency tests above passing.
