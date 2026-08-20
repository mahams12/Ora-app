# ORA — Phase 0.5 Architecture Audit

**Status:** HISTORICAL SNAPSHOT of Phase 0.5. Findings were corrected in Phase 0.6 and product-model-locked in Phase 0.7. Do not implement from this file. Canonical docs live under `docs/architecture/`, `docs/algorithms/`, and `docs/architecture-review/phase-0.7-approval.md`.

**Documents reviewed:** 52  
**Review scope:** all markdown documents under `docs/`  
**Method:** cross-document consistency review, adversarial correctness review, failure-mode review, concurrency audit, security audit, and package/version audit

## Cross-Document Contradictions Found

1. `rideRequests` is listed as a Firestore collection in `ORA_MASTER_PLAN.md`, but no Firestore schema exists for it; the actual request fan-out path is RTDB `rideRequests/{driverId}/pending/{rideId}`.
2. The master plan uses `tripLocations/{rideId}/{timestamp}` while the RTDB schema and location docs use `tripLocations/{rideId}/{sequenceNumber}`.
3. Assignment correctness is described as being guaranteed by Redis in `ORA_MASTER_PLAN.md` and `security/security-model.md`, while `algorithms/ride-assignment.md` correctly uses Firestore transaction validation as the durable barrier.
4. `rideSignals.seq` is sometimes treated as ride version and sometimes as a generic realtime sequence; this is mixed with GPS `sequenceNumber`.
5. `ride-api.md` uses `POST /v1/rides/:id/status`, while `ORA_MASTER_PLAN.md` and `backend-architecture.md` call the route `PATCH /rides/{id}/status`.
6. `backend-architecture.md` says `GET /v1/location/nearby` is internal use, while `ORA_MASTER_PLAN.md` lists `GET /drivers/nearby` as a public Driver API.
7. Cash payment is modeled as `RIDE_COMPLETED → PAYMENT_PENDING → COMPLETED`, but `payment-flow.md` gives the driver a post-trip `Cash Received` action that materially changes business state.
8. `ORA_SECURITY_MODEL.md` and `database/realtime-schema.md` allow RTDB `tripLocations` reads for any authenticated user, while `security/authorization-matrix.md` implies resource-scoped access.
9. Redis key names differ: `dispatch:request:{rideId}` in `ORA_MASTER_PLAN.md` vs `dispatch:notified:{rideId}` elsewhere.
10. `drivers.isOnline`, RTDB `driverPresence`, and Redis `driver:online:{driverId}` all represent availability without a formal reconciliation owner.
11. `security/threat-model.md` says App Check detects mock GPS “on most devices”, while other docs implicitly lean on it as a strong anti-spoofing control.
12. `ORA_TECH_STACK.md` recommends `Hive 2.x`, but package audit evidence shows the original `hive` package is stale and effectively superseded by `hive_ce`.

---

## [BLOCKER] Redis Is Treated As The Authoritative Assignment Barrier

### Evidence
`ORA_MASTER_PLAN.md`, `security/security-model.md`, `security/threat-model.md`, `algorithms/ride-assignment.md`

### Problem
Several documents overstate Redis `SETNX` as the correctness guarantee for exactly-one assignment. Redis is only a contention optimization. Durable correctness must come from a conditional Firestore state transition that checks current state, current version, and absence of an assigned driver inside a transaction.

### Failure scenario
1. Driver A acquires Redis lock.
2. Cloud Run crashes before Firestore commit.
3. Lock expires 30 seconds later.
4. Driver B retries and wins.
5. If the architecture narrative says “Redis guaranteed exactly one winner,” that statement is false; Redis guaranteed only temporary exclusivity, not durable assignment.

### Impact
The current wording mislocates the safety barrier and will likely lead implementers to over-trust Redis and under-specify Firestore transaction predicates.

### Recommendation
Declare the Firestore transaction as the **authoritative atomic operation**:
- read ride document
- assert `state in {SEARCHING, OFFERS_AVAILABLE}`
- assert selected offer is `PENDING`, not expired, matching `requestVersion`
- assert `assignedDriverId == null`
- assert `version == expectedVersion`
- write assignment, `agreedFareMinor` from offer, increment version

Redis should be documented only as a best-effort contention reducer.

### Implementation consequence
Impacts Phase 8, Phase 9, `ride-engine`, ride API contract, tests, observability, and security wording.

### Status
OPEN

## [BLOCKER] No Durable Outbox For Firestore-To-RTDB/PubSub/FCM Side Effects

### Evidence
`architecture/realtime-architecture.md`, `architecture/backend-architecture.md`, `operations/observability.md`, `operations/disaster-recovery.md`

### Problem
The architecture assumes this sequence:

`Firestore transaction succeeds → RTDB cleanup succeeds → Pub/Sub publish succeeds → FCM succeeds`

There is no durable mechanism to recover when Firestore succeeds but one or more downstream side effects fail.

### Failure scenario
1. Driver A is assigned in Firestore.
2. RTDB delete for losing drivers fails transiently.
3. Pub/Sub publish fails transiently.
4. Passenger Firestore listener eventually updates, but losing drivers keep stale request cards.
5. No durable retry record exists for cleanup or notifications.

### Impact
Stale request cards, missed passenger assignment notifications, inconsistent UI, missing analytics, and fragile disaster recovery.

### Recommendation
Adopt a durable outbox pattern:

`Firestore transaction: ride state update + outbox event record`

Then a publisher/dispatcher:
- reads unpublished outbox records
- publishes to Pub/Sub
- performs RTDB cleanup/signal fan-out
- records delivery state
- retries idempotently
- dead-letters after threshold

### Implementation consequence
Impacts Phase 8, Phase 9, `ride-engine`, notification service, observability, event contracts, and disaster recovery.

### Status
OPEN

## [BLOCKER] Critical Idempotency Design Is Invalid And Incomplete

### Evidence
`algorithms/idempotency.md`, `architecture/backend-architecture.md`, `ORA_SECURITY_MODEL.md`

### Problem
The proposed Redis command `GETSET ... NX EX 30` is not a valid Redis operation. The design also assumes Redis-only 24-hour retention for all critical idempotency outcomes, while disaster recovery refers to a Firestore `idempotencyKeys` collection that is never defined anywhere.

### Failure scenario
1. Passenger sends `POST /rides`.
2. Cloud Run times out after Firestore commit but before HTTP response.
3. Passenger retries with same idempotency key after Redis eviction or Redis outage.
4. Without durable idempotency state, a duplicate ride can be created.

### Impact
Duplicate rides, duplicate cancels, duplicate payment attempts, inconsistent response replay, and undefined behavior under Redis outage.

### Recommendation
Split idempotency into classes:
- **financial and ride-creation mutations:** durable store in Firestore / SQL-grade durable table
- **short-lived contention hints:** Redis optional

For each mutation define:
- key shape
- ownership scope
- pending state record
- success/failure replay payload
- retention
- retry behavior after timeout

### Implementation consequence
Impacts all mutation endpoints, Phase 7, Phase 9, Phase 11, payment callbacks, and race tests.

### Status
OPEN

## [BLOCKER] Payment Architecture Lacks Required Financial Entities And Reconciliation

### Evidence
`product/payment-flow.md`, `implementation/phase-11-payments.md`, `ORA_MASTER_PLAN.md`, `database/firestore-schema.md`

### Problem
The documents mention a `payments` collection in summary form, but no Firestore schema exists for:
- payment intent
- payment attempt
- provider callback record
- refund
- adjustment
- payout
- reconciliation record

The current model jumps directly from ride completion to ledger updates.

### Failure scenario
1. PSP charge request times out.
2. PSP actually captures funds.
3. Ora retries capture.
4. Callback arrives twice or out of order.
5. There is no explicit durable payment-attempt entity to reconcile request, provider reference, callback, and ledger posting.

### Impact
Double capture risk, missing refunds, irreconcilable ledger drift, payout corruption, and audit gaps.

### Recommendation
Introduce explicit durable entities:
- `paymentIntents`
- `paymentAttempts`
- `providerCallbacks`
- `ledgerEntries`
- `payouts`
- `refunds`
- `reconciliationRuns`

Wallet balance must remain a cache, not the financial source of truth.

### Implementation consequence
Impacts Phase 11, database design, payment API, callbacks, observability, and support operations.

### Status
OPEN

## [BLOCKER] Ride Lifecycle And Payment Lifecycle Are Conflated

### Evidence
`ORA_STATE_MACHINE.md`, `product/ride-lifecycle.md`, `product/payment-flow.md`, `api/ride-api.md`

### Problem
The current ride state machine includes `PAYMENT_PENDING`, `PAYMENT_FAILED`, and `COMPLETED` inside the ride lifecycle. That makes payment outcome a prerequisite for ride terminality, which is a poor fit for:
- cash rides
- offline driver confirmation
- delayed provider callbacks
- later settlement/payout disputes

### Failure scenario
1. Driver physically completes a cash trip.
2. Ride enters `PAYMENT_PENDING`.
3. Driver goes offline before tapping “Cash Received.”
4. The platform now lacks a clean separation between “trip operationally complete” and “payment settlement complete.”

### Impact
Terminality is ambiguous, retries become messy, reporting is wrong, and cancellation/dispute logic becomes harder.

### Recommendation
Separate state machines:
- **Ride lifecycle:** operational trip state
- **Payment lifecycle:** authorization, capture, settlement, refund

Recommended ride terminal state: `RIDE_COMPLETED` or `RIDE_CLOSED`

Payment should be a separate aggregate with states such as:
- `PAYMENT_NOT_REQUIRED`
- `PAYMENT_PENDING`
- `PAYMENT_AUTHORIZED`
- `PAYMENT_CAPTURED`
- `PAYMENT_FAILED`
- `PAYMENT_REVERSED`
- `PAYMENT_SETTLED`

### Implementation consequence
Impacts state machine, ride API, payments, wallet, receipts, reporting, and tests.

### Status
OPEN

## [HIGH] Source-Of-Truth Definitions Are Inconsistent Across Documents

### Evidence
`ORA_MASTER_PLAN.md`, `database/firestore-schema.md`, `database/realtime-schema.md`, `architecture/system-overview.md`

### Problem
The intended source model is good, but implementation details drift:
- Firestore `rideRequests` is named as durable truth but not actually modeled.
- RTDB `rideRequests` is the real fan-out structure.
- `drivers.isOnline` in Firestore duplicates RTDB presence.
- Redis `driver:online` duplicates both.

### Failure scenario
Driver goes offline. RTDB presence clears, Redis TTL expires, but `drivers.isOnline` remains true due to a failed sync path. Matching and admin tooling may disagree.

### Impact
Confusing ownership, stale availability, incorrect admin views, and harder reconciliation.

### Recommendation
Define one owner per data category:
- Identity → Firebase Auth
- User profile → Firestore
- Driver availability → RTDB authoritative projection; Firestore optional denormalized mirror marked non-authoritative
- Driver location → RTDB current-trip projection + Redis spatial index
- Ride state → Firestore
- Assignment → Firestore
- Fare snapshot → Firestore
- Realtime signal → RTDB
- Dispatch candidate set → Redis ephemeral

### Implementation consequence
Impacts admin UI, matching, observability, and schema wording.

### Status
OPEN

## [HIGH] Version, GPS Sequence, And Event Ordering Are Mixed Together

### Evidence
`ORA_STATE_MACHINE.md`, `algorithms/stale-event-handling.md`, `architecture/realtime-architecture.md`, `database/firestore-schema.md`

### Problem
Three independent ordering systems are present but not formally separated:
- ride aggregate version
- GPS packet sequence
- event sequence / outbox ordering

`rideSignals.seq` is treated as ride version in some places, while GPS events also use `seq`. `rideEvents.sequenceNumber` exists but is not defined as producer-owned or globally monotonic.

### Failure scenario
App restarts during a trip, local GPS sequence resets to 1, server compares against last accepted sequence 142, and all new packets are rejected until client state is repaired.

### Impact
Undefined reconnect behavior, stale-event confusion, impossible debugging, and broken packet acceptance after restart or process death.

### Recommendation
Formalize:
- `rideVersion`: server-generated, stored on ride aggregate, increments on ride-state transitions only
- `locationSeq`: client-generated per driver-session-per-ride, monotonic within that stream, server stores last accepted seq per ride+driver stream
- `eventSequence`: server-generated outbox ordering for durable events only

### Implementation consequence
Impacts RTDB schema, location API, event contracts, reconnect logic, and tests.

### Status
OPEN

## [HIGH] RTDB Authorization Is Too Broad For Sensitive Realtime Data

### Evidence
`ORA_SECURITY_MODEL.md`, `database/realtime-schema.md`, `security/authorization-matrix.md`

### Problem
Current RTDB rules allow `tripLocations` and `rideSignals` reads for any authenticated user in some documents. That is broader than the authorization matrix and broader than the privacy model.

### Failure scenario
Passenger A guesses or enumerates ride IDs and listens to unrelated `tripLocations/{rideId}` paths.

### Impact
Location privacy breach, internal ride-state leakage, and unsafe exposure of protected realtime data.

### Recommendation
RTDB rules must be resource-scoped. Reads should require proof that caller is:
- the ride passenger
- the assigned driver
- an admin service account

If RTDB rules cannot express the necessary joins cleanly, mirror authorized participant lists into the RTDB node or use server-issued scoped tokens.

### Implementation consequence
Impacts Phase 9, RTDB schema, security rules, privacy model, and threat model.

### Status
OPEN

## [HIGH] Location Trust Model Overstates App Check And Understates Adversarial GPS Risk

### Evidence
`ORA_SECURITY_MODEL.md`, `security/threat-model.md`, `security/abuse-prevention.md`, `architecture/location-architecture.md`

### Problem
App Check is useful for app attestation, but it is not a strong anti-spoofing guarantee. Kalman filtering smooths noise; it does not verify honesty. The current documents occasionally imply stronger protection than actually exists.

### Failure scenario
Driver runs a modified but otherwise attested environment or uses device-level GPS spoofing that passes basic integrity checks. The server sees plausible but false points unless stronger correlation checks exist.

### Impact
False arrivals, fake trip completion, inflated earnings, and trust erosion.

### Recommendation
State clearly:
- client location is untrusted input
- Kalman filter is smoothing only
- App Check is not a location integrity proof

Add server-side heuristics:
- impossible travel
- teleport gaps
- route plausibility
- dwell-time plausibility at pickup/destination
- callback challenge on suspicious arrival claims

### Implementation consequence
Impacts Phase 4, Phase 10, fraud review, and safety.

### Status
OPEN

## [HIGH] Simultaneous Top-30 Dispatch Is Likely Too Noisy And Too Contended

### Evidence
`algorithms/matching-engine.md`, `implementation/phase-08-dispatch.md`, `product/driver-flow.md`

### Problem
Notifying the top 30 drivers simultaneously maximizes contention, notification spam, and stale-card cleanup work.

### Failure scenario
At 1,000 active drivers, every ride fans out to 30 RTDB writes + 30 FCM sends immediately. Most rides are accepted by the first few strong candidates, but 25+ extra drivers are spammed anyway.

### Impact
Poor driver experience, elevated Redis/RTDB/FCM costs, more accept conflicts, and noisier metrics.

### Recommendation
Use deterministic wave dispatch:
- Wave 1: top 5 drivers, 4–6 second window
- Wave 2: next 10 if no assignment / insufficient offers
- Wave 3: next 15 only if still unresolved

Wave progression must be server-driven and cancelable on assignment.

### Implementation consequence
Impacts matching, dispatch, latency expectations, cost, and driver UX.

### Status
OPEN

## [HIGH] Redis Failure Recovery References Nonexistent Durable Fallbacks

### Evidence
`database/redis-schema.md`, `operations/disaster-recovery.md`, `algorithms/idempotency.md`

### Problem
Redis outage handling mentions:
- fallback Firestore `idempotencyKeys` collection
- fallback Firestore driver query for nearby drivers in `< 1s`

Neither is formally defined or validated.

### Failure scenario
Redis goes down during peak. The system tries to fall back to undefined durable stores or expensive Firestore scans with no geospatial index.

### Impact
Unrealistic outage promises, incorrect recovery assumptions, and degraded behavior that is not actually implementable from current docs.

### Recommendation
Document explicit degraded modes:
- assignment can proceed via Firestore transaction only
- new rides may be rate-limited or temporarily blocked if nearby-driver lookup becomes too expensive
- idempotency for critical financial and ride-create mutations must rely on a durable store already designed up front

### Implementation consequence
Impacts disaster recovery, operational runbooks, and MVP complexity.

### Status
OPEN

## [MEDIUM] Published Latency SLOs Are Too Strongly Framed For Background/Killed-App Paths

### Evidence
`ORA_LATENCY_SLO.md`, `implementation/phase-08-dispatch.md`, `operations/observability.md`

### Problem
The documented P95 targets assume active listeners and favorable network conditions. They are reasonable stretch targets for foreground, connected clients, but not for backgrounded or killed apps.

### Failure scenario
Driver app is backgrounded on iOS. FCM delivery and app wakeup exceed the published 900ms request-delivery target, yet the SLO document reads as a blanket system guarantee.

### Impact
Misleading expectations, false alerting, and difficult operational interpretation.

### Recommendation
Split SLOs by path:
- foreground connected path
- background resumable path
- killed-app push path

### Implementation consequence
Impacts observability, acceptance criteria, and on-call thresholds.

### Status
OPEN

## [MEDIUM] Matching Score Uses Raw Ratings Without Sample-Size Correction

### Evidence
`algorithms/matching-engine.md`, `ORA_MASTER_PLAN.md`

### Problem
A driver with 1 five-star ride can outrank a driver with 500 rides at 4.92. Raw average ratings are noisy and unfair at low sample sizes.

### Failure scenario
Brand-new driver with one perfect rating repeatedly outranks stable, reliable drivers because the formula treats 5.0 from one sample as superior evidence.

### Impact
Unfair ranking, volatile marketplace quality, and easier gaming.

### Recommendation
Use a Bayesian or Wilson-style prior-adjusted rating:

`adjustedRating = (priorWeight * globalMean + ratingCount * rawMean) / (priorWeight + ratingCount)`

### Implementation consequence
Impacts Phase 8 ranking, analytics, and fairness.

### Status
OPEN

## [MEDIUM] `stateHistory` On The Ride Aggregate Will Grow Without Bound

### Evidence
`ORA_STATE_MACHINE.md`, `database/firestore-schema.md`

### Problem
The ride aggregate stores both a growing `stateHistory` array and a separate `rideEvents` audit log. This duplicates audit data and can grow document size unnecessarily.

### Failure scenario
Long-lived rides with many retries, offers, cancels, safety events, or admin corrections inflate the ride document and increase read costs.

### Impact
Larger ride reads, duplicated audit logic, and unnecessary Firestore document growth.

### Recommendation
Keep only compact current-state metadata on `rides` and move full history to `rideEvents`. At most retain a short bounded transition summary on the ride document.

### Implementation consequence
Impacts ride schema, reads, and observability.

### Status
OPEN

## [MEDIUM] Money Representation Is Not Consistently Specified As Integer Minor Units

### Evidence
`product/payment-flow.md`, `database/firestore-schema.md`, `algorithms/fare-engine.md`

### Problem
Some docs use rupee decimals in examples (`Rs 40.80`), while schema prose says “PKR; in paisas internally.” This is not consistently enforced across fare, wallet, ledger, payout, or API examples.

### Failure scenario
One service rounds in rupees, another stores paisas, and receipts drift by small amounts under commission/refund calculations.

### Impact
Rounding drift, reconciliation noise, and ledger mismatches.

### Recommendation
Standardize all persisted and API monetary amounts to integer `amountMinor` in paisas. Presentation-layer formatting to rupees belongs in client/UI only.

### Implementation consequence
Impacts pricing, payment API, ledger, payouts, refunds, and receipts.

### Status
OPEN

## [LOW] RTDB Trip Location Storage Needs A Long-Trip Growth Limit

### Evidence
`database/realtime-schema.md`, `architecture/location-architecture.md`

### Problem
Appending every GPS point by sequence number under a single ride node can create large RTDB nodes for long trips.

### Failure scenario
A 4-hour intercity ride at 1-second active-trip cadence produces >14,000 child nodes.

### Impact
Heavier sync, larger cleanup operations, and higher bandwidth on reconnect.

### Recommendation
Keep:
- `latest` position node for active rendering
- bounded recent history ring buffer
- optional batched archival if needed for fraud analytics

### Implementation consequence
Impacts RTDB schema and long-trip performance.

### Status
OPEN

## [LOW] Original `hive` Package Choice Is Stale

### Evidence
`ORA_TECH_STACK.md`; package audit evidence from pub.dev

### Problem
The docs recommend `Hive 2.x`, but the original `hive` package stable line is old and community momentum has moved toward `hive_ce`. Keeping `hive 2.x` is a maintenance risk.

### Failure scenario
Phase 1 implementation adopts a stale package with weaker maintenance and unclear forward migration path.

### Impact
Technical debt and upgrade friction.

### Recommendation
Replace the current recommendation with either:
- `hive_ce` for lightweight cache needs, or
- reassess whether `shared_preferences` + secure storage is enough for MVP

### Implementation consequence
Impacts Phase 1 and Phase 3 local storage decisions.

### Status
OPEN

## [INFO] Paid Background Geolocation Plugin Is Justified But Adds Procurement Risk

### Evidence
`ORA_TECH_STACK.md`; package audit evidence for `flutter_background_geolocation`

### Problem
The selected plugin is actively maintained and technically strong, but Android release builds require licensing. That is an operational dependency, not just a code dependency.

### Failure scenario
Team defers license procurement until late testing; release builds are blocked or silently misconfigured.

### Impact
Schedule risk rather than correctness risk.

### Recommendation
Keep the plugin choice for now, but add a Phase 4 procurement/licensing gate and a documented fallback plan.

### Implementation consequence
Impacts Phase 4 delivery planning and budget.

### Status
OPEN
