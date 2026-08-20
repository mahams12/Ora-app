# Concurrency / Race Condition Audit (28 Required Cases)

Authoritative sources:
- `docs/architecture-review/system-invariants.md`
- `docs/architecture-review/idempotency-matrix.md`
- `docs/architecture-review/event-contracts.md`
- `docs/architecture-review/outbox-design.md`
- `docs/algorithms/stale-event-handling.md`
- `docs/algorithms/ride-assignment.md`

Notation:
- “Authoritative source of truth” = what must be trusted to determine the outcome.
- “Transaction boundary” = where the server enforces correctness.

## Case 1: Two drivers accept/counter simultaneously
- Authoritative truth: `rideOffers` + `rides.state` remain unassigned until passenger selects
- Transaction boundary: offer create endpoint (`POST /rides/{id}/offers`) per driver request
- Idempotency key: `ride_offer:{rideId}:{driverId}:{clientNonce}`
- Expected result: **multiple** offers in `PENDING`, `rides.assignedDriverId == null`, ride enters/keeps `OFFERS_AVAILABLE`
- Rejected result: none (except offer de-dup / eligibility)
- Events emitted: `ride.offer.received` (durable) per successful offer
- Client behavior: show each pending offer card; do not interpret driver Accept as assignment
- Recovery: retries use same key; duplicates replay stored response

## Case 2: Passenger selects two drivers almost simultaneously
- Authoritative truth: `rides` assignment committed by Firestore conditional transaction
- Transaction boundary: `POST /rides/{rideId}/offers/{offerId}/select` Firestore transaction predicates
- Idempotency key: `ride_select:{rideId}:{passengerId}:{clientNonce}`
- Expected result: exactly one commit transitions ride → `DRIVER_ASSIGNED`
- Rejected result: one request returns `409 ALREADY_ASSIGNED` / `409 VERSION_CONFLICT` / `422 OFFER_*`
- Events emitted: `ride.assigned` + `ride.offer.selected` for winner; loser may emit no assignment side effects
- Client behavior: on conflict, re-read Firestore ride and replace offer inbox with assigned-trip UI
- Recovery: idempotent retries return the same winner result

## Case 3: Passenger selects Driver A while Driver A becomes unavailable
- Authoritative truth: Firestore `rides` and eligibility checks at select time
- Transaction boundary: select transaction includes driver eligibility re-check
- Idempotency key: `ride_select:{rideId}:{passengerId}:{clientNonce}`
- Expected result: **no assignment** for A if eligibility fails at select time
- Rejected result: `422 DRIVER_NOT_ELIGIBLE` (or offer becomes non-selectable)
- Events emitted: none for assignment; offer may transition to `WITHDRAWN/EXPIRED` later
- Client behavior: refresh offer list from Firestore; allow selecting an eligible offer
- Recovery: read-repair from Firestore on reconnect

## Case 4: Driver goes offline while passenger is selecting them
- Authoritative truth: Firestore transaction + driver eligibility predicate (availability state + eligibility)
- Transaction boundary: select endpoint
- Idempotency key: `ride_select...`
- Expected result: selection fails (no assignment) if eligibility changes before commit
- Rejected result: `422 DRIVER_NOT_ELIGIBLE`
- Events emitted: none for assignment
- Client behavior: remove unavailable offer; compare remaining pending offers
- Recovery: retry with same idempotency key returns deterministic failure until state changes

## Case 5: Ride expires while selection occurs
- Authoritative truth: Firestore state transition enforced by select transaction predicates + expiry fields
- Transaction boundary: select transaction asserts ride state in `{SEARCHING, OFFERS_AVAILABLE}` and offer TTL validity
- Idempotency key: `ride_select...`
- Expected result: no assignment if TTL exceeded
- Rejected result: `422 OFFER_EXPIRED` or `409 STATE_CONFLICT` / `410 RIDE_EXPIRED`
- Events emitted: ride expiration event (`ride.expired`) if/when expiry sweeper commits
- Client behavior: remove ride and show expired/offer-unavailable state
- Recovery: subsequent retries replay the same conflict result via idempotency record

## Case 6: Passenger cancels while driver accepts
- Authoritative truth: Firestore ride cancellation state + offer create state assertions
- Transaction boundary: cancel endpoint transaction + offer create eligibility checks
- Idempotency key: cancel uses `ride_cancel:{rideId}:{actorId}:{clientNonce}`; offer create uses `ride_offer...`
- Expected result: either
  - cancel commits first → driver accept fails with conflict; or
  - driver offer commits first → cancellation later marks offers non-selectable/expired
- Rejected result: one of the two operations returns `409/422 STATE_CONFLICT`
- Events emitted: `ride.cancelled` durable + any offer-related durable events that occurred before cancellation
- Client behavior: remove cancelled ride; do not show new offers on cancelled ride
- Recovery: read repair from Firestore after reconnect

## Case 7: Driver cancels while passenger selects
- Authoritative truth: offer `status` and select transaction predicates
- Transaction boundary: withdraw/cancel of offer + select transaction
- Idempotency key: withdraw uses idempotency record; select uses `ride_select...`
- Expected result: if withdraw/expiry wins, select fails
- Rejected result: `422 OFFER_NOT_SELECTABLE` or `404 OFFER_NOT_FOUND`
- Events emitted: none for assignment; offers remain non-selectable
- Client behavior: refresh inbox; if assigned already, show assigned-trip UI
- Recovery: retry select with same key replays deterministically

## Case 8: Network retry repeats mutation
- Authoritative truth: durable idempotency record
- Transaction boundary: first successful request processes and stores result snapshot
- Idempotency key: per idempotency matrix
- Expected result: replay stored logical outcome (same assignment or same conflict)
- Rejected result: none (unless key reused with different payload)
- Events emitted: at most once for correctness-critical side effects due to outbox/consumer idempotency
- Client behavior: safe to retry using same key; show stable outcome

## Case 9: Same mutation arrives twice
- Authoritative truth: durable idempotency record (requestHash + key)
- Transaction boundary: server handler uses idempotency record
- Idempotency key: same as case 8
- Expected result: deterministic replay
- Rejected result: if payload differs under same key → `409 IDEMPOTENCY_KEY_REUSED`
- Client behavior: generate a new key if `IDEMPOTENCY_KEY_REUSED`

## Case 10: Old request arrives after newer request
- Authoritative truth: ride aggregate version + expected version checks + offer `requestVersion` checks
- Transaction boundary: server predicates compare current version / expectedVersion / requestVersion
- Idempotency key: whichever request has its own key
- Expected result: older request fails with `409 VERSION_CONFLICT` / `422 OFFER_STALE`
- Rejected result: no state rollback; newer state persists
- Client behavior: discard UI assumptions; re-read authoritative Firestore ride/offer state

## Case 11: Realtime event arrives before REST response
- Authoritative truth: Firestore ride document state + version
- Transaction boundary: REST mutation commits first; RTDB may fan out earlier
- Idempotency key: REST mutation idempotency record
- Expected result: realtime wakes UI but must not override until REST/Firestore read confirms
- Client behavior:
  1. apply version checks
  2. if REST not yet finished, still treat realtime as wake-up and re-fetch Firestore

## Case 12: REST response arrives before realtime
- Authoritative truth: REST mutation response corresponds to authoritative commit in Firestore/outbox
- Transaction boundary: server mutation commit
- Expected result: UI updates immediately; later realtime signals are discarded if stale by `aggregateVersion/eventSequence`
- Client behavior: reconcile on realtime arrival using monotonic discard rules

## Case 13: Realtime events arrive out of order
- Authoritative truth: ordering domain counters + read-repair invariants
- Transaction boundary: none (projection); client discard logic is correctness barrier for projection only
- Expected result: out-of-order packets are discarded
- Client behavior: use `aggregateVersion/eventSequence` and `locationSeq` monotonic checks

## Case 14: Device disconnects during assignment
- Authoritative truth: Firestore assignment transaction
- Transaction boundary: select transaction
- Idempotency key: `ride_select...` retained by client across retries (must reuse same key)
- Expected result: server either commits assignment or returns conflict
- Client behavior: on reconnect/app restart, read authoritative ride from Firestore and rebuild UI from snapshot
- Recovery: ignore any stale RTDB signals captured during disconnect window

## Case 15: App is killed immediately after a successful server mutation
- Authoritative truth: Firestore transaction outcome
- Transaction boundary: server commit
- Idempotency key: stored/reused by client next launch (client must preserve nonce or keep it in durable local storage)
- Expected result: correctness recovered from Firestore; downstream outbox projections replay idempotently
- Client behavior: on next launch, re-fetch ride/offer state and attach listeners

## Case 16: App reconnects after missed events
- Authoritative truth: Firestore + durable outbox replay readiness
- Transaction boundary: none (read repair)
- Expected result: client re-reads current ride state and discards stale signals
- Client behavior: per `docs/architecture-review/consistency-model.md` read-repair protocol

## Case 17: Two backend workers process the same event
- Authoritative truth: consumers must dedupe by `eventId`
- Transaction boundary: consumer idempotency in projector/dispatcher
- Expected result: only one logical side-effect occurs
- Client behavior: none (server correctness)

## Case 18: Outbox event delivered twice
- Authoritative truth: outbox consumer dedupes by `eventId`
- Transaction boundary: consumer idempotency + projection version checks
- Expected result: duplicate projection updates are ignored
- Recovery: projector replays until success or dead-letter

## Case 19: Outbox projector crashes midway
- Authoritative truth: outbox durable records still exist until marked delivered
- Transaction boundary: projector transactionally claims delivery (CLAIMED + lease fields) and transactionally marks subscriber `ACKED` and the outbox event `DELIVERED`; delivery is **at-least-once** with per-subscriber dedupe by `eventId`.
  (Frozen in `docs/architecture-final/24-phase-1.6-condition-closure.md` section 3.)
- Expected result: on restart, projector resumes and republishes safely
- Client behavior: read-repair on next reconnect if signals lag

## Case 20: Redis becomes unavailable
- Authoritative truth: Firestore correctness barrier and durable idempotency
- Transaction boundary: assignment transaction does not require Redis correctness
- Expected result: dispatch may degrade; assignment still works once offers exist
- Client behavior: if ride/offer exists, proceed; if no offers due dispatch failure, show degraded mode and retry
- Recovery: degraded-mode dispatch per runbook; correctness intact

## Case 21: Firestore becomes temporarily unavailable
- Authoritative truth: Firestore is unavailable, so no new authoritative mutation can safely commit
- Transaction boundary: none available while outage persists
- Idempotency key: still required on client-originated mutations; requests may be retried after outage with the same key
- Expected result: new ride creation, offer create, select, cancel, and status mutations fail closed with `503 SERVICE_UNAVAILABLE` / dependency error
- Rejected result: no fallback may invent assignment or write ride truth into RTDB/Redis/client cache
- Event emitted: operational alert / dependency error log only; no business event without durable commit
- Client behavior: show degraded mode; active-trip UI can keep last known projection but must mark reconnecting
- Recovery behavior: on Firestore recovery, client re-reads authoritative ride/payment state; server reconciles rides stuck in non-terminal states

## Case 22: FCM delivery fails
- Authoritative truth: Firestore ride truth + RTDB projection remain primary for correctness
- Transaction boundary: none; FCM is outbox side effect only
- Idempotency key: eventId/outbox delivery state for notification side effects
- Expected result: foreground listeners still converge from Firestore/RTDB; background-only wake-up may be delayed/missed
- Rejected result: no assumption that lack of push means state mutation failed
- Event emitted: outbox delivery failure / notification failure metric
- Client behavior: foreground clients continue via listeners; background clients recover when app opens
- Recovery behavior: outbox retry, dead-letter on repeated failure, ops alert if delivery failure threshold exceeded

## Case 23: Driver location becomes stale
- Authoritative truth: server-validated location freshness state and last accepted location cursor
- Transaction boundary: location validation + scheduler staleness sweep
- Idempotency key: none for location updates
- Expected result: stale driver removed from Redis GEO index; active-trip passenger may see stale-location warning; driver may become temporarily unavailable for new dispatch
- Rejected result: stale location must not continue to qualify driver as fresh/eligible
- Event emitted: `GPS_STALE` or equivalent audit/safety/health event
- Client behavior: passenger sees stale indicator; driver sees GPS warning; dispatch card eligibility may end
- Recovery behavior: fresh accepted GPS packet restores health; matching re-qualifies driver if still valid

## Case 24: Driver sends impossible GPS jumps
- Authoritative truth: server validation of speed, distance/time plausibility, geofence, and sequence monotonicity
- Transaction boundary: `POST /v1/location/update` validation
- Idempotency key: none
- Expected result: packet rejected with `422 INVALID_LOCATION` / `SEQUENCE_VIOLATION` as applicable
- Rejected result: impossible jump must not update Redis GEO or RTDB tripLocations
- Event emitted: suspicious-location / fraud / safety log entry on repeated violations
- Client behavior: driver may see “waiting for better GPS” UX; passenger retains last accepted good position
- Recovery behavior: subsequent valid packet resumes stream; repeated violations can trigger suspension review

## Case 25: Payment succeeds but client receives timeout
- Authoritative truth: payment aggregate (`paymentIntents`, `paymentAttempts`) and ledger state
- Transaction boundary: payment initiation/capture mutation + provider confirmation/writeback
- Idempotency key: `payment_initiate:{paymentIntentId}:{clientNonce}` or provider-specific capture key
- Expected result: client retry with same key replays original success or current terminal payment state
- Rejected result: client must not create second payment attempt solely because it timed out locally
- Event emitted: payment success event (`payment.captured` / `payment.cash.collected`) if committed
- Client behavior: show pending/reconnecting until authoritative payment status is re-read
- Recovery behavior: retry same request with same key; if still ambiguous, read payment aggregate and receipts from server

## Case 26: Payment webhook is delivered twice
- Authoritative truth: provider callback dedupe store `paymentProviderCallbacks/{provider}_{providerEventId}` + payment aggregate + ledger idempotency key
- Transaction boundary: webhook handler stores unseen callback and applies state transition once
- Idempotency key: `{provider}:{providerEventId}`
- Expected result: duplicate callback ACKed without duplicate ledger posting
- Rejected result: second callback must not change payment state again or create duplicate ledger entries
- Event emitted: first callback may emit `payment.captured` / `payment.failed`; duplicate emits only duplicate-detected audit log
- Client behavior: no visible duplicate effect; existing payment state remains stable
- Recovery behavior: dedupe record persists permanently/audit-retained; retries remain harmless

## Case 27: Payment webhook arrives out of order
- Authoritative truth: payment aggregate state machine + attempt state + provider callback ordering rules
- Transaction boundary: webhook handler compares current payment/attempt state before applying transition
- Idempotency key: `{provider}:{providerEventId}` plus payment aggregate state predicates
- Expected result: older callback cannot roll payment state backward; stale/out-of-order callback is ignored or mapped to reconciliation
- Rejected result: `CAPTURED` must not revert to `AUTHORIZED`; `REFUNDED` must not be overwritten by late success without explicit reconciliation
- Event emitted: payment event only if transition is valid; otherwise anomaly/reconciliation log
- Client behavior: continue showing latest authoritative payment state
- Recovery behavior: unresolved ordering anomaly moves payment to `RECONCILIATION_REQUIRED` for manual/automated reconciliation

## Case 28: Ride completes while payment is still processing
- Authoritative truth: separate ride and payment aggregates
- Transaction boundary: ride completion transaction is distinct from payment state transitions
- Idempotency key: `ride_complete:{rideId}:{driverId}:{clientNonce}` for ride; payment keys separate
- Expected result: ride can be `RIDE_COMPLETED` / `RIDE_CLOSED` while payment remains `PENDING`, `CAPTURE_PENDING`, `FAILED`, or `RECONCILIATION_REQUIRED`
- Rejected result: ride must not be reopened or marked unpaid-paid by client mutation; payment state must not be inferred from ride completion
- Event emitted: `ride.completed` and later `payment.*` events independently
- Client behavior: show completed trip with payment pending/processing state if needed
- Recovery behavior: payment retries/reconciliation continue independently; receipts update from payment aggregate/ledger, not by mutating ride history

