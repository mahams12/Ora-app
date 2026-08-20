# Cross-Feature Clash Matrix (Major Interactions)

Format: `Feature A × Feature B` → shared state, owner, event, conflict risk, resolution.

Resolution rule: **durable Firestore/payment aggregates win**, realtime is projected, dedupe is mandatory, and each mutation is idempotent.

## Key Clashes

- Auth × Ride
  - Shared state: `users` role + ride ownership
  - Owner: Cloud Run authorization (JWT + App Check)
  - Event: auth-validated command handlers
  - Conflict risk: unauthorized select/create
  - Resolution: strict authorization matrix + Firestore predicates

- Auth × Payment
  - Shared state: `paymentIntents.ownerUserId`
  - Owner: Cloud Run payment handlers
  - Conflict risk: driver/patient mismatch
  - Resolution: server-only validation + idempotency keys

- Location × Dispatch
  - Shared state: dispatch candidate eligibility depends on freshness/accuracy
  - Owner: Location service + matching engine
  - Conflict risk: stale/stolen GPS causing fake proximity
  - Resolution: server validation + geofence + speed plausibility

- Ride × Notification
  - Shared state: notification must follow durable state, not vice versa
  - Owner: outbox publisher + notification dispatcher
  - Conflict risk: push delivered but ride canceled/assigned changed
  - Resolution: client read-repair from Firestore; events are projected based on outbox + version checks

- Ride × Safety
  - Shared state: safety events reference `rideId` and can trigger ride cancellation (e.g. driver mismatch) (Frozen in `docs/architecture-final/24-phase-1.6-condition-closure.md` section 7)
  - Owner: safety events service + admin tooling
  - Resolution: any ride-state change must go through ride engine and ride state machine predicates

- Ride × Payment
  - Shared state: payment created from `agreedFareMinor`
  - Owner: payment service
  - Conflict risk: payment inferred from ride completion incorrectly
  - Resolution: agreedFare snapshot at assignment + payment SM separate from ride SM

- Payment × Ledger
  - Shared state: ledger entries must be immutable
  - Conflict risk: duplicate ledger posting on retries/webhooks
  - Resolution: provider callback dedupe + durable idempotency + ledger idempotency keys

- Offline × Realtime
  - Shared state: missing RTDB events during disconnect
  - Owner: consistency model + stale-event handling
  - Conflict risk: UI showing stale cards or wrong state
  - Resolution: read-repair from Firestore + discard stale by version/sequence

- App Restart × Active Ride
  - Shared state: live trip UI correctness
  - Owner: consistency model reconnect protocol
  - Conflict risk: resetting location seq incorrectly
  - Resolution: locationStreamId negotiated by server transitions; discard stale streams

- Auth × OTP
  - Shared state: phone identity, verification session, rate limits
  - Owner: server OTP session aggregate
  - Conflict possibility: old OTP verifies after resend/new OTP
  - Resolution: currentOtpVersion latest-wins, old code invalid immediately

- Versioning × Realtime
  - Shared state: event schemaVersion + aggregateVersion
  - Owner: backend producer/consumer compatibility rules
  - Conflict possibility: unknown newer event payload applied by old consumer
  - Resolution: fail safe, log unsupported version, read-repair from Firestore

- Admin × Security
  - Shared state: intervention flows on rides/payments/safety
  - Owner: audited backend admin APIs
  - Conflict possibility: silent invariant bypass
  - Resolution: reason-coded audited correction tooling only; no raw DB mutation shortcuts

