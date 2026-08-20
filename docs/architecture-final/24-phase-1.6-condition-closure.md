# Phase 1.6 Condition Closure

This document closes the remaining Phase 1.5 architecture conditions and acts as the canonical freeze for:

1. Firestore security matrix
2. Durable idempotency lifecycle
3. Durable outbox projector semantics
4. OTP contract
5. Secondary feature contract closure
6. Location stream resume
7. Safety-to-ride transition matrix
8. Redis degraded mode
9. Event schema versioning
10. Nearby-driver authorization
11. TTL/index freeze
12. Telemetry/log sampling
13. Mandatory tests
14. Invariant re-check
15. Final cross-feature review

If any later document conflicts with this one, **this document wins until a new architecture approval explicitly supersedes it**.

---

## 1. Firestore Security Rule Freeze

### Access actor taxonomy

- `CLIENT_PASSENGER`
- `CLIENT_DRIVER_PENDING`
- `CLIENT_DRIVER_APPROVED`
- `BACKEND`
- `ADMIN`
- `SYSTEM_JOB`

### Core rule

- Firestore rules default to **deny all**.
- Any collection not explicitly client-readable/writable is **backend-only**.
- Client writes are limited to low-risk profile/preferences/saved-place/support-ticket/message/report surfaces that do not mutate authoritative ride/payment/security state.

### Collection-Level Security Matrix

| Collection | Purpose | Read | Create | Update | Delete | Notes |
|---|---|---|---|---|---|---|
| `users/{uid}` | profile/preferences | own user; admin any | backend on first auth/bootstrap | own non-sensitive fields; admin/backend broader | account deletion via backend flow only | immutable: `uid`, `role`, `driverStatus`, `createdAt`; audit sensitive changes |
| `drivers/{driverId}` | driver business state | own; admin; passenger limited public projection only via API, not raw Firestore | backend only | backend/admin only; driver may patch limited preferences through API | backend/admin only | immutable: `driverId`, `userId`; client cannot write `availabilityState`, `activeRideId`, rating, earnings |
| `vehicles/{vehicleId}` | vehicle registration/approval | owner driver, admin | driver via API (backend writes doc) | driver via API for editable fields while not approved; admin/backend approval fields only | backend/admin only | immutable after approval for identity fields unless admin flow |
| `driverDocuments/{driverId}` | KYC docs | owner driver read-only summary; admin full; backend full | backend only via signed upload workflow | backend/admin only | backend/admin only | no direct client writes; client uploads blobs via signed URL; metadata written by backend |
| `rides/{rideId}` | authoritative ride aggregate | passenger owner, assigned driver, admin | backend only | backend/admin/system job only | backend/admin only | client never writes state/assignment/financial fields |
| `rideOffers/{offerId}` | driver offers | passenger owning ride; offering driver; admin | backend only from offer API | backend only for status transitions | backend/admin only | client never writes status/selected/superseded |
| `rideEvents/{eventId}` | immutable audit | backend/admin only | backend/system only | none | none | append-only |
| `outboxEvents/{eventId}` | durable outbox | backend/admin/support tooling read-only | backend only | backend/system job only (`deliveryState`, attempts, leases) | backend/system archival only | never client-accessible |
| `idempotencyRecords/{key}` | durable replay safety | backend/admin only | backend only | backend/system only | system TTL/archive only | never client-accessible |
| `pricingRules/{id}` | admin pricing policy | authenticated read | admin/backend only | admin/backend only | admin only | public mobile config only if safe; no write by clients |
| `pricingSnapshots/{id}` | estimate snapshot | passenger owner, backend, admin | backend only | none | system TTL cleanup | immutable after write |
| `feePolicies/{id}` | fee policy | backend/admin; optionally authenticated read if safe summary needed | admin/backend only | admin/backend only | admin only | historical rides use snapshot copies |
| `paymentIntents/{id}` | payment aggregate | owner user, assigned driver limited receipt view, admin | backend only | backend/admin only | backend/admin only | client never writes |
| `paymentAttempts/{id}` | PSP/cash attempt | backend/admin only; owner may receive derived API view only | backend only | backend/system only | backend/admin only | raw attempt records not exposed to clients directly |
| `paymentProviderCallbacks/{id}` | webhook dedupe | backend/admin only | backend only | backend/system only (`processed`) | archive/system only | never client-accessible |
| `walletAccounts/{uid}` | balance projection | owner user, admin | backend only | backend/system only | backend/admin only | client never writes balance |
| `walletLedgerEntries/{id}` | immutable ledger | backend/admin only; user may get API-projected statement | backend only | none except void status by controlled admin adjustment flow | never hard delete in normal ops | append-only |
| `driverPayouts/{id}` | payout workflow | owner driver summary; admin; backend | backend only from payout API | backend/admin only | backend/admin only | no client direct write |
| `refunds/{id}` | refund workflow | owner user summary; admin; backend | backend/admin only | backend/admin only | backend/admin only | no client direct write |
| `reconciliationRecords/{id}` | ops mismatch tracking | backend/admin only | backend/system only | backend/system/admin only | archive/system only | never client-accessible |
| `ratings/{rideId}_{type}` | ratings/reviews | rater, rated user limited read via API, admin | backend only from rating API | backend/admin only while editable window open | backend/admin soft delete/moderation only | no raw cross-user browsing by Firestore rule |
| `savedPlaces` | favorite places | owner user | owner user via API/backed client write if rules allow nested doc | owner user | owner user | low-risk client write allowed |
| `safetyEvents/{id}` | safety incidents | backend/admin full; participants may receive API-projected own incident summary | backend or safety API only | backend/admin/system only | archive/system/admin only | client never writes raw record directly |
| `supportTickets/{id}` | support workflow | owner user, assigned support/admin, backend | owner user via API (backend writes) | owner may append messages while open; support/admin/backend manage states | soft delete/admin only | attachments via signed URL |
| `supportTicketMessages/{id}` | ticket thread | owner/support/admin | backend only from message API | immutable after write except moderation flags | moderation/admin only | append-only messaging surface |
| `reports/{id}` | abuse/block/report | reporter, admin/backend | owner user via API | backend/admin only | archive/admin only | false-report handling via moderation |
| `blocks/{id}` | passenger/driver/user block relations | block owner, backend, admin | owner user via API | backend only for active flags | owner/backend/admin | impacts dispatch eligibility |
| `tripShareTokens/{id}` | trip share tokens | backend/admin only; browser access uses tokenized API, not Firestore | backend only | backend/system revoke/expire only | system TTL cleanup | never client-readable as raw collection |
| `consentRecords/{id}` | terms/privacy/optional consents | owner user, backend, admin | backend only from consent API | no mutation; append new version records or withdrawal records | archive/admin only | immutable evidence |
| `adminAuditLogs/{id}` | admin action audit | admin/backend only | backend/admin only | none | none/archival only | append-only |
| `moderationCases/{id}` | admin/moderation workflow | assigned admin/support backend | backend/admin only | backend/admin only | archive/admin only | never client-accessible |
| `notificationReceipts/{id}` | notification delivery/projection | backend/admin only | backend/system only | backend/system only | system TTL cleanup | never client-accessible |

### Explicit prohibitions

Clients must never be able to:
- assign a ride
- mutate authoritative ride status
- mutate `assignedDriverId`, `agreedFareMinor`, `platformFee*`, `driverNet*`
- write payment intent/attempt states
- write ledger or wallet balances
- approve driver/vehicle/KYC state
- create raw outbox/idempotency/audit records
- alter another user’s offer/ticket/report/review

### Audit requirement

Every backend/admin mutation affecting:
- ride state
- offers
- payments
- payouts/refunds
- safety
- moderation
- support resolution
- consent withdrawals

must append an audit/event record with actor, requestId, timestamp, before/after summary, and reason where applicable.

---

## 2. Durable Idempotency Freeze

### Canonical record schema

Collection: `idempotencyRecords/{idempotencyKey}`

```json
{
  "idempotencyKey": "ride_select:ride_123:uid_abc:nonce_xyz",
  "operation": "RIDE_SELECT",
  "resourceId": "ride_123",
  "actorId": "uid_abc",
  "actorRole": "passenger",
  "requestHash": "sha256(...)",
  "status": "RECEIVED | PROCESSING | SUCCEEDED | FAILED_RETRYABLE | FAILED_FINAL | EXPIRED",
  "responseStatusCode": 200,
  "responseSnapshot": {},
  "firstReceivedAt": "timestamp",
  "lastTouchedAt": "timestamp",
  "expiresAt": "timestamp",
  "deviceId": "optional safe device binding hint",
  "clientRequestId": "req_...",
  "operationVersion": 1
}
```

### Lifecycle states

- `RECEIVED`: request persisted, hash validated, not yet claimed
- `PROCESSING`: request claimed by active handler
- `SUCCEEDED`: terminal success; exact logical response replayed
- `FAILED_RETRYABLE`: transient dependency failure; safe client retry with same key
- `FAILED_FINAL`: final business failure; same key replays same failure
- `EXPIRED`: retention elapsed; no longer reusable

### Key format

`{operation}:{resourceId}:{actorId}:{clientNonce}`

Examples:
- `ride_create:route_session_abc:uid_1:nonce_1`
- `ride_offer:ride_123:drv_9:nonce_2`
- `ride_select:ride_123:uid_1:nonce_3`
- `payment_cash_collected:ride_123:drv_9:nonce_4`

### Binding rules

- bound to actorId
- bound to operation
- bound to resourceId
- bound to requestHash

### Same key rules

- same key + same payload → replay same logical result
- same key + different payload → `409 IDEMPOTENCY_KEY_REUSED`

### Concurrent same-key behavior

- first request transitions `RECEIVED/PROCESSING`
- concurrent duplicates with same key + same hash:
  - return `202 PROCESSING` if active and result unavailable
  - or block briefly and replay terminal result

### Client durability requirement

Yes: clients **must persist idempotency keys locally** for all business-critical mutations until terminal response is observed or authoritative state is recovered.

#### Local persistence requirements

- storage: secure storage for auth/payment-sensitive operations; durable app-local storage acceptable for non-secret business keys if encrypted app storage is unavailable
- association fields:
  - `operation`
  - `resourceId`
  - `createdAt`
  - `requestHash`
  - `requestId`
  - `statusHint` (`pending` / `resolved`)
- retention:
  - ride/offer/select/cancel/start/complete keys: 7 days
  - payment/refund/payout keys: 30 days
- cleanup:
  - on terminal replay + post-recovery confirmation
  - periodic background cleanup for expired keys

### App kill / device restart recovery

If app dies after sending a mutation:
1. client relaunches
2. reads pending local idempotency records
3. retries same operation with same key or reads authoritative resource state
4. server replays prior terminal result or current final authoritative outcome

No critical mutation may require a new key after restart unless the original request never left client process and was never persisted.

---

## 3. Durable Outbox Projector Freeze

### Outbox event envelope

Collection: `outboxEvents/{eventId}`

```json
{
  "eventId": "evt_01...",
  "aggregateId": "ride_123",
  "aggregateType": "ride",
  "aggregateVersion": 6,
  "eventSequence": 991,
  "schemaVersion": 1,
  "createdAt": "timestamp",
  "eventType": "ride.assigned",
  "payload": {},
  "status": "PENDING | CLAIMED | PUBLISHED | PARTIALLY_DELIVERED | DELIVERED | DEAD_LETTER"
}
```

### Per-subscriber delivery tracking

Subcollection or sibling collection: `outboxDeliveries/{eventId}_{subscriber}`

```json
{
  "eventId": "evt_01...",
  "subscriber": "rtdb_projector | fcm_dispatcher | pubsub_publisher | analytics_sink",
  "attemptCount": 0,
  "leaseOwner": "worker-abc",
  "leaseExpiresAt": "timestamp",
  "lastAttemptedAt": null,
  "lastAcknowledgedAt": null,
  "status": "PENDING | CLAIMED | ACKED | FAILED_RETRYABLE | DEAD_LETTER",
  "lastError": null
}
```

### Delivery semantics

- Delivery is **at-least-once**
- Exactly-once is **not claimed**
- Correctness comes from:
  - durable outbox
  - per-subscriber dedupe by `eventId`
  - aggregateVersion / eventSequence reconciliation

### Worker atomic behavior

1. worker scans `PENDING/FAILED_RETRYABLE` subscriber deliveries where `leaseExpired`
2. worker transactionally claims delivery:
   - set `status=CLAIMED`
   - set `leaseOwner`
   - set `leaseExpiresAt = now + leaseDuration`
3. worker publishes/projection side effect
4. on success:
   - transactionally mark subscriber `ACKED`
   - if all subscribers `ACKED`, mark outbox event `DELIVERED`
5. on crash before publish:
   - lease expires
   - another worker reclaims
6. on crash after publish but before ack:
   - duplicate publish possible
   - subscriber must dedupe by `eventId`
   - next worker replays safely

### Thresholds

- lease duration: 30s
- immediate retry: yes for transient network error if within handler budget
- retry backoff: exponential with jitter
- max automatic retries:
  - RTDB projector: 12 attempts / 15 min window
  - FCM dispatcher: 10 attempts / 30 min
  - Pub/Sub publisher: 20 attempts / 24h
- dead-letter after max retries exhausted
- manual replay allowed only via audited admin/ops tool
- automatic replay allowed only from dead-letter if underlying dependency incident is cleared and replay window valid

### Replay rules

- replay preserves original `eventId`, `aggregateVersion`, `eventSequence`
- subscribers must treat replay as duplicate-safe
- stale version cannot overwrite newer projection state

---

## 4. OTP Contract Freeze

> **AMENDMENT (2026-08-20) — ADR-016 Path A**  
> Phone OTP **delivery and verification** are owned by **Firebase Phone Auth**,
> not by an Ora `otpSessions` aggregate.  
> See `docs/architecture-final/ADRs/ADR-016-Firebase-Native-OTP.md`.  
> The schema and numeric limits below remain as the **historical Path B /
> custom-OTP freeze**. They are **not implemented** and **must not be claimed**
> as Ora-enforced while ADR-016 is in force.  
> Client UX still targets a **30s resend cooldown**. Abuse beyond Firebase
> quotas is mitigated post-auth (App Check, API rate limits, account bans).

### OTP aggregate schema

Collection: `otpSessions/{sessionId}`
*(Path B / deferred — not used under ADR-016)*

```json
{
  "sessionId": "otp_01...",
  "phoneHash": "sha256(phone)",
  "userId": null,
  "state": "OTP_REQUESTED | OTP_SENT | OTP_VERIFIED | OTP_EXPIRED | OTP_INVALID | OTP_LOCKED | OTP_COOLDOWN",
  "attemptCount": 0,
  "resendCount": 0,
  "maxAttempts": 5,
  "maxResends": 3,
  "cooldownUntil": null,
  "lockUntil": null,
  "otpExpiresAt": "timestamp",
  "currentOtpVersion": 2,
  "verificationToken": "opaque server token",
  "createdAt": "timestamp",
  "updatedAt": "timestamp",
  "deviceFingerprint": "optional",
  "ipHash": "optional"
}
```

### State machine

- `OTP_REQUESTED`
- `OTP_SENT`
- `OTP_VERIFIED`
- `OTP_EXPIRED`
- `OTP_INVALID`
- `OTP_LOCKED`
- `OTP_COOLDOWN`

### Frozen limits

- max attempts per session: 5
- OTP expiration: 5 minutes
- resend cooldown: 30 seconds
- max resend count per session: 3
- lock duration after max invalid attempts: 15 minutes
- per-phone request limit: 5 OTP sessions per hour
- per-IP/device limit: 10 OTP requests per hour, 3 concurrent open sessions

### Authority

- Server is sole authority for OTP generation, session state, resend eligibility, validity, expiration, and lock state.
- Client only holds `sessionId` / opaque `verificationToken`.

### Old OTP after new OTP

If OTP A is generated and later OTP B is generated for the same active session/phone:
- increment `currentOtpVersion`
- OTP A becomes invalid immediately
- any verification attempt using A returns `OTP_INVALID` or `OTP_EXPIRED` depending on session state
- only the latest active version can verify

### Concurrent OTP requests

- if an active non-expired session exists and not locked:
  - resend same logical session if cooldown permits
  - otherwise return `OTP_COOLDOWN`
- backend should avoid creating unbounded parallel sessions for the same phone/device tuple

### Duplicate code behavior

- same correct OTP for same verified session is idempotent success only while verification token remains active and before session finalization window closes
- otherwise replay same verified result or reject as already verified based on session state

### Abuse detection

- repeated invalid attempts
- repeated cross-device requests
- IP burst patterns
- same device across many phone numbers

All generate security telemetry; severe abuse may force captcha/manual review in future, but current contract is rate-limit + lock.

---

## 5. Secondary Feature Contract Closure

### A. Support

#### Ticket states
- `OPEN`
- `WAITING_FOR_USER`
- `WAITING_FOR_SUPPORT`
- `RESOLVED`
- `REOPENED`
- `CLOSED`

#### Actors
- user
- support agent
- admin
- backend/system job

#### Rules
- user creates ticket via API
- backend writes `supportTickets` doc and `supportTicketMessages`
- user/support may append messages while ticket not closed
- attachments uploaded via signed URLs only
- resolution requires support/admin actor and audit log
- reopen allowed within 7 days of resolution, max 2 times, otherwise new ticket
- SLA targets:
  - first response: 24h standard, 5m safety-critical
  - resolution target by priority class

### B. Terms / Consent

Collection: `consentRecords`

Fields:
- `consentType`
- `termsVersion`
- `policyVersion`
- `acceptedAt`
- `withdrawnAt`
- `mandatory`
- `evidenceSource` (`mobile`, `web`, `admin`)

Rules:
- mandatory consent required before protected flows proceed
- optional consent may be withdrawn
- historical proof is append-only; no mutation of prior records
- newer mandatory version blocks protected flows until re-consent

### C. Block / Report

#### Block
- one user may block another via backend API
- effect:
  - blocked users must not be matched together for new rides
  - existing active ride is not auto-terminated solely by low-severity block event; escalate through safety/report path if active danger

#### Report
States:
- `REPORTED`
- `TRIAGED`
- `ACTIONED`
- `DISMISSED`
- `APPEALED`
- `RESOLVED`

Rules:
- any authenticated participant may report ride/user/support issue
- false-report patterns are abuse-scored
- admin escalation required for suspension or ride intervention

### D. Trip Sharing

Collection: `tripShareTokens`

Fields:
- `tokenId`
- `rideId`
- `issuedToUserId`
- `scope = ACTIVE_TRIP_READONLY`
- `expiresAt`
- `revokedAt`
- `shareVersion`
- `tokenHash`

Rules:
- entropy: minimum 128 bits random
- active-trip only
- expires at ride completion + 30 min
- revocable by passenger or backend
- browser access uses tokenized API, not direct DB reads
- PII exposed to share page is minimized:
  - first name only
  - masked phone
  - vehicle make/model/plate only as necessary
- rate limit:
  - create max 5 tokens per ride
  - open token max 60 req/min per IP

### E. Reviews

Separate concerns:
- rating stars/tags
- review text
- moderation state

Rules:
- editable window: 15 minutes after submission
- after that, append moderation actions only; do not rewrite history silently
- visibility:
  - public profile surfaces may show moderated aggregate
  - raw abusive text may be hidden
- deletion:
  - soft-delete/moderation only
- abuse:
  - profanity/spam detection
  - reportable by other party/admin

### F. Admin / Moderation

Roles:
- `support_agent`
- `moderator`
- `ops_admin`
- `finance_admin`
- `super_admin`

No admin action may silently bypass invariants.
Any exceptional action must go through:
- audited backend/admin API
- reason code
- actor identity
- before/after state record

Admin capabilities by role:
- `support_agent`: ticket management, low-risk messaging
- `moderator`: reports, review moderation, account warning
- `ops_admin`: ride intervention, suspension, dispatch/safety operational controls
- `finance_admin`: refunds, reconciliation, payout interventions
- `super_admin`: break-glass actions only, heavily audited

---

## 6. Location Stream Resume Freeze

### Canonical stream key

Scope = `{rideId}:{driverId}:{locationStreamId}`

### Lifecycle

1. server issues/accepts active `locationStreamId=A`
2. packets accepted only if:
   - stream is active
   - `locationSeq` strictly greater than last accepted seq for stream A
3. app crashes/restarts
4. client obtains active ride snapshot and requests or is issued new `locationStreamId=B`
5. stream A transitions to `STALE_REPLACED`
6. any late packet from A is rejected because:
   - stream A not active, or
   - stream version less than current active stream

### Stream registry schema

Collection: `locationStreams/{rideId_driverId}`

```json
{
  "rideId": "ride_123",
  "driverId": "drv_9",
  "activeStreamId": "loc_B",
  "activeStreamStartedAt": "timestamp",
  "lastAcceptedSeq": 42,
  "previousStreamIds": ["loc_A"],
  "streamState": "ACTIVE | STALE_REPLACED | CLOSED",
  "expiresAt": "timestamp"
}
```

### Acceptance rule

Server accepts packet only if:
- packet.streamId == activeStreamId
- packet.seq > lastAcceptedSeq for active stream
- packet.timestamp fresh

Late packets from A after B is active are always rejected and never overwrite B.

### Cleanup

- previous stream references retained 15 minutes for replay defense
- active stream closed at ride terminal + 10 minutes
- TTL cleanup by system job

---

## 7. Safety → Ride State Matrix

| Safety Event | Actor | Allowed Ride States | Ride Mutation Allowed? | Authority | Outcome |
|---|---|---|---|---|---|
| SOS before ride | passenger/driver | `DRAFT`,`ROUTE_READY` | no automatic ride mutation | backend+safety ops | create safety event only |
| SOS while searching/offers | passenger | `SEARCHING`,`OFFERS_AVAILABLE` | optional passenger cancel only through normal cancel flow | passenger/server | safety event + optional cancel |
| SOS while driver en route | passenger/driver | `DRIVER_ASSIGNED`,`DRIVER_EN_ROUTE` | no silent force transition; ops/admin may freeze/intervene | ops/admin audited | safety escalation, optional admin cancellation |
| SOS after driver arrival | passenger/driver | `DRIVER_ARRIVED` | admin may terminate ride for safety | ops/admin audited | safety event + ride intervention |
| SOS during active ride | passenger/driver | `RIDE_STARTED` | admin may freeze/escalate/terminate if policy allows | ops/admin audited | safety event + intervention |
| Driver mismatch report | passenger | `DRIVER_EN_ROUTE`,`DRIVER_ARRIVED` | may cancel before boarding via normal cancellation + safety escalation | passenger/server | safety report + optional cancel |
| Route deviation | system | `RIDE_STARTED` | no automatic termination on first deviation | backend/system | alert passenger; escalate on severe persistence |
| SOS after ride completion | passenger/driver | `RIDE_COMPLETED`,`RIDE_CLOSED` | no ride mutation | backend/safety ops | post-ride incident handling |

### Rule

Safety does not casually mutate ride state.
Any ride transition triggered by safety must be:
- server/admin authorized
- audited
- emitted as both safety event and ride event if state changes

---

## 8. Redis Degraded Mode Freeze

### Healthy
- GEO queries active
- dispatch waves active
- select contention lock available
- offer dedupe cache active
- rate-limit counters active

### Slow
- continue with tighter timeouts
- skip optional lock if latency threshold exceeded
- reduce dispatch fanout aggressiveness
- do not scan all drivers

### Unavailable
- no uncontrolled full-driver scan
- new ride creation may continue only if:
  - dispatch can be safely deferred/paused, or
  - a bounded fallback candidate source exists (none is currently canonical)
- therefore:
  - **new dispatch creation degrades to unavailable**
  - existing rides/offers/assignment correctness remains via Firestore
  - select assignment still works if pending offers already exist

### Partially unavailable
- if lock path fails but GEO healthy:
  - dispatch continues; select uses Firestore only
- if GEO fails but lock healthy:
  - no new matching/dispatch; select on existing offers still allowed

### Recovering
- rebuild geo index from fresh validated driver location updates
- do not replay stale cached redis state as truth

---

## 9. Event Schema Versioning Freeze

### Current version
- `schemaVersion = 1`

### Compatibility rules

- Old producer → new consumer:
  - consumer must accept older version if supported
  - unknown missing optional fields use defaults
- New producer → old consumer:
  - producer must not remove required old fields during deprecation period
  - additive unknown fields must be ignored by old consumers

### Unknown version behavior

- if consumer sees unsupported higher major version:
  - do not apply projection blindly
  - log `UNSUPPORTED_SCHEMA_VERSION`
  - fetch authoritative Firestore state for recovery
  - move to safe degraded behavior

### Deprecation period

- minimum 2 released mobile versions or 30 days, whichever is longer, before removing prior event-version compatibility from backend consumers

---

## 10. Nearby Driver Authorization Freeze

Endpoint: `GET /v1/drivers/nearby`

### Who can call

- primary caller: backend/internal services
- passenger client: allowed only for pre-booking coarse availability surfaces if implemented later
- driver client: not for browsing competitors

### Response rules

- passenger pre-booking response, if exposed:
  - returns aggregate availability hints or masked drivers
  - no exact driver coordinates
  - no direct identity unless assignment/offer relationship exists

- internal dispatch response:
  - exact candidate metadata available to backend only

### Privacy

- no raw exact driver live location to unaffiliated passenger
- exact driver identity shown only after:
  - offer snapshot in passenger inbox, or
  - assignment/live trip where authorized

### Rate limit

- passenger pre-booking: 10/min per user
- internal service: service-to-service quota controlled separately

---

## 11. TTL / Index Freeze

### TTL Matrix

| Entity | TTL / Retention | Cleanup Owner | Frequency | Failure Behavior |
|---|---|---|---|---|
| `idempotencyRecords` ride ops | 7 days | system job | hourly | stale records harmless; cleanup retried |
| `idempotencyRecords` financial ops | 30 days | system job | hourly | never purge before audit window |
| `outboxEvents` delivered | 30 days hot, archive after | system job | daily | retain if archival fails |
| `outboxDeliveries` | 30 days hot | system job | daily | safe to retain longer |
| `otpSessions` | expire 24h after terminal | system job | hourly | locked/expired sessions remain safe |
| `tripShareTokens` | active trip + 30 min | system job | 5 min | expired token must deny access |
| RTDB `tripLocations` | delete within 60s of ride terminal | backend projector/system job | near-real-time + sweep | stale data remains inaccessible via rideAccess cleanup |
| RTDB `rideSignals` | 5 min after terminal | system job | 5 min | stale signal ignored by version rules |
| RTDB `rideRequests` | card expiry or assignment/cancel | backend projector/system job | real-time + 30s sweep | stale card still rejected by backend on action |
| `locationStreams` | ride terminal + 10 min | system job | 15 min | old stream packets still rejected |
| `notificationReceipts` | 7 days | system job | daily | observability degradation only |

### Additional index freeze

Required new/explicit indexes:
- `idempotencyRecords`: `actorId + operation + firstReceivedAt`, `expiresAt`
- `outboxEvents`: `status + createdAt`, `aggregateId + aggregateVersion`
- `outboxDeliveries`: `subscriber + status + leaseExpiresAt`
- `otpSessions`: `phoneHash + createdAt`, `state + lockUntil`, `cooldownUntil`
- `supportTickets`: `ownerUserId + createdAt`, `state + priority + updatedAt`
- `reports`: `reportedUserId + createdAt`, `state + severity`
- `tripShareTokens`: `rideId + expiresAt`, `tokenHash`
- `consentRecords`: `userId + consentType + acceptedAt`

---

## 12. Telemetry / Log Sampling Freeze

### Principles

- never log access tokens, refresh tokens, OTP values, payment secrets, full CNIC, raw webhook secrets
- keep traceability via `requestId`, `rideId`, `eventId`, `operationId`, `driverId/passengerId` where authorized

### Sampling

#### GPS
- DEBUG: off in production by default; can be temporarily enabled per ride/driver under ops flag
- INFO: sample 1 in 100 accepted packets
- WARNING: all rejected packets with redacted metadata
- ERROR/FATAL: all

#### Dispatch/offers
- INFO: all ride create / offer create / select / cancel / assignment events
- DEBUG: sampled 1 in 20 candidate-ranking detail logs

#### Realtime projections
- INFO: assignment projection success/failure
- DEBUG: sampled dedupe/stale discard logs

#### Notifications
- INFO: send summary per batch, not full payload dump
- WARNING/ERROR: all delivery failures with token redaction

---

## 13. Mandatory Test Additions

### Security
- every sensitive collection unauthorized read/write
- cross-user access denial
- admin escalation path audit assertions

### Idempotency
- same key + same payload replay
- same key + different payload conflict
- timeout then retry
- app kill/restart with same key recovery
- concurrent same-key `PROCESSING` behavior

### Outbox
- crash before publish
- crash after publish before ack
- duplicate publish
- subscriber restart
- manual replay
- dead-letter after max retries

### OTP
- resend cooldown
- max invalid attempts → lock
- expired code
- old OTP after new OTP
- concurrent OTP requests
- per-phone/IP rate limiting

### Location
- old stream A after new stream B rejected
- duplicate packet on same stream rejected
- stale packet rejected
- reconnect resumes with new streamId

### Events/versioning
- old schema accepted by new consumer
- additive new schema tolerated by old-safe consumer path
- unknown schema version fails safe
- out-of-order event rejected

---

## 14. Invariant Re-Check

New contracts were checked against `23-architecture-invariants.md`.
No new contract violates the invariant set.

Additional implied invariants introduced by Phase 1.6:
- old `locationStreamId` packets must never overwrite a newer active stream
- idempotency keys for critical mutations must survive app kill/restart through durable local persistence
- unsupported event schema versions must fail safe and fall back to authoritative read-repair
- support/moderation/admin actions must be audited and cannot silently bypass invariants

---

## 15. Final Cross-Feature Review

No unresolved HIGH conflict remains across:
- Auth × OTP
- Auth × Security
- Auth × Driver
- Auth × Passenger
- Ride × Dispatch
- Ride × Offers
- Ride × Location
- Ride × Safety
- Ride × Payment
- Ride × Notifications
- Payment × Ledger
- Payment × Refund
- Payment × Earnings
- Offline × Realtime
- Offline × Payment
- App Restart × Active Ride
- Versioning × Realtime
- Versioning × API
- Admin × Security

Residual medium/low tradeoffs remain operational, not architecture-gating.

