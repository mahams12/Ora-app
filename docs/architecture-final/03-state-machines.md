# Explicit State Machines (Locked Contracts)

This package defines the explicit state machines required by Phase 1.5.

Some machines are fully specified in existing authoritative docs (ride lifecycle, payment lifecycle).
Others are defined here by consolidating locked product/DB schemas and security models; where the authoritative definition is not fully detailed in the doc set, this file marks **(Gap)**.

## 1) Authentication

**States**
- `UNAUTHENTICATED`
- `AUTHENTICATION_REQUIRED` (token missing/expired)
- `OTP_REQUIRED`
- `OTP_SENT`
- `AUTHENTICATED`
- `AUTH_FAILED`

**Allowed transitions**
- `UNAUTHENTICATED → OTP_REQUIRED` (user initiates sign-in)
- `OTP_REQUIRED → OTP_SENT` (server sends OTP or verifies sender constraints)
- `OTP_SENT → AUTHENTICATED` (OTP verification succeeds)
- `* → AUTH_FAILED` (verification fails or token is rejected)

**Authority**
- Server-authoritative (Firebase Auth).

**Client authority**
- Client can request/submit OTP; cannot claim authenticated state without successful verification.

## 2) OTP Verification

**States**
- `OTP_IDLE`
- `OTP_SENDING`
- `OTP_SENT`
- `OTP_VERIFYING`
- `OTP_VERIFIED`
- `OTP_FAILED`

**Timeout / retry**
- **Authoritative OTP provider (ADR-016):** Firebase Phone Auth owns send,
  verify, expiry, and quota/throttle behavior.
- **Ora client UX:** resend cooldown display ≈ `30s`.
- Historical custom `otpSessions` numeric freeze remains in
  `docs/architecture-final/24-phase-1.6-condition-closure.md` section 4 for
  Path B only — **not claimed as Ora-enforced** while ADR-016 is active.

## 3) Passenger Onboarding

**States**
- `PASSENGER_PROFILE_INCOMPLETE`
- `PASSENGER_READY`

**Transitions**
- profile creation/update → `PASSENGER_READY` (server validates only non-sensitive fields)

## 4) Driver Onboarding (Application Flow)

**States**
- `DRIVER_ONBOARDING_PERSONAL`
- `DRIVER_ONBOARDING_VEHICLE`
- `DRIVER_ONBOARDING_DOCUMENTS`
- `DRIVER_REVIEW_PENDING`
- `DRIVER_APPROVED`
- `DRIVER_REJECTED`
- `DRIVER_SUSPENDED`

**Authority**
- Admin/server writes final statuses.

## 5) Driver Verification / KYC (Document-Level)

**States (per document record)**
- `missing`
- `uploaded`
- `approved`
- `rejected`

**Driver can transition** only after all required documents are `approved` (Gap: exact required-set rules are not exhaustively enumerated).

## 6) Driver Availability (Online/Offline)

**States**
- `OFFLINE`
- `ONLINE_AVAILABLE`
- `BUSY` (optional product-level meaning; mapping to `activeRideId != null` is server-derived)
- `SUSPENDED`

**Transitions**
- `OFFLINE → ONLINE_AVAILABLE` (driver approved + “go online”)
- `ONLINE_AVAILABLE → OFFLINE` (go offline, disconnect, or stale presence)
- `ONLINE_AVAILABLE → SUSPENDED` (admin action)

**Authority**
- Firestore `drivers.availabilityState` and presence in RTDB (ephemeral).

## 7) Ride Request Lifecycle (Ride State Machine)

Authoritative definition: `docs/ORA_STATE_MACHINE.md`.

**States**
`DRAFT → ROUTE_READY → REQUEST_CREATED → SEARCHING → OFFERS_AVAILABLE → DRIVER_ASSIGNED → DRIVER_EN_ROUTE → DRIVER_ARRIVED → RIDE_STARTED → RIDE_COMPLETED → RIDE_CLOSED`

**Cancellation/terminal states**
`CANCELLED, EXPIRED, NO_SHOW, DRIVER_CANCELLED, PASSENGER_CANCELLED`

**Impossible-state rule**
- Ride state must never embed payment states such as `PAYMENT_PENDING` or `PAYMENT_FAILED`.
- Those are payment-aggregate states only.
- Therefore combinations like `ride.state = PAYMENT_FAILED` are forbidden by design.

## 8) Driver Offer Lifecycle (Per Offer)

Authoritative definition: `docs/algorithms/offer-model.md` + Firestore schema `rideOffers`.

**States**
- `PENDING` (canonical selectable state)
- `SELECTED`
- `SUPERSEDED`
- `REJECTED` (optional UX dismissal)
- `WITHDRAWN`
- `EXPIRED`

**Allowed transitions (high-level)**
- create offer → `PENDING`
- passenger selects → `SELECTED`
- later passenger selects sibling offer → `SUPERSEDED`
- expiry/sweep → `EXPIRED`
- driver withdraw/decline before selection → `WITHDRAWN` (or implicit non-terminal removal)

**Forbidden**
- terminal/non-selectable offers must never become assignments.

## 9) Passenger Offer Selection & Ride Assignment

**Command**
- `POST /rides/{rideId}/offers/{offerId}/select`

**Outcomes**
- Success → ride transitions to `DRIVER_ASSIGNED` + `agreedFareMinor` immutable snapshot
- Conflict → `409 ALREADY_ASSIGNED / VERSION_CONFLICT`
- Business denial → `422 OFFER_* / DRIVER_NOT_ELIGIBLE`

Authority: server transaction only (`docs/algorithms/ride-assignment.md`).

## 10) Driver Arrival

**State**
- `DRIVER_ARRIVED` enabled only after server proximity/geofence validation.

Transitions
- `DRIVER_EN_ROUTE → DRIVER_ARRIVED`

Timeout
- `DRIVER_ARRIVED wait TTL → NO_SHOW` (`docs/ORA_STATE_MACHINE.md`).

## 11) Active Ride (Operational Trip)

**States**
- `DRIVER_EN_ROUTE`
- `DRIVER_ARRIVED`
- `RIDE_STARTED`
- `RIDE_COMPLETED`

**Authority**
- Driver taps for en-route / start / complete, but server validates proximity and plausibility.

## 12) Ride Cancellation

**Terminal states**
- `CANCELLED`
- or dedicated terminal cancellation codes: `DRIVER_CANCELLED, PASSENGER_CANCELLED`

**Forbidden**
- `RIDE_CLOSED` and other terminals cannot transition.

## 13) Ride Completion

**Outcome**
- `RIDE_COMPLETED → RIDE_CLOSED` via server closure.

Payment begins from `agreedFareMinor` (separate payment SM).

## 14) Payment (Payment Intent / Attempt)

Authoritative definition: `docs/product/payment-flow.md`, Firestore schema `paymentIntents/paymentAttempts`.

**States**
`NOT_REQUIRED → PENDING → AUTHORIZED → CAPTURE_PENDING → CAPTURED`
`→ FAILED`
`→ REFUND_PENDING → REFUNDED`
`→ RECONCILIATION_REQUIRED`

**Authority**
- Server only.

**Impossible-state rule**
- Payment success/failure must not reopen or rewrite terminal ride history.
- `RIDE_COMPLETED` with payment `PENDING/FAILED/RECONCILIATION_REQUIRED` is valid.
- `RIDE_STARTED` with payment `CAPTURED` before completion is invalid unless a future preauth flow is explicitly introduced and documented.

## 15) Refund

**State**
- `REFUND_PENDING → REFUNDED` via server reconciliation and/or provider callbacks.

## 16) Driver Earnings

**States**
- Derived from ledger and payout workflow.
- Payout states from Firestore `driverPayouts`:
  `PENDING → PROCESSING → COMPLETED` or `FAILED` or `RECONCILIATION_REQUIRED`

## 17) Notification Delivery

Modelled via outbox and best-effort channels:
- Outbox publish `publishState` is durable (`PENDING` then success/failure)
- Pub/Sub is at-least-once
- FCM is best-effort

**Forbidden**
- Notification success cannot be correctness-critical for assignment/payment.

## 18) Location Session

**States (conceptual)**
- `GPS_UPDATING`
- `GPS_STALE` (server classification)
- `GPS_REJECTED` (accuracy/plausibility violation)
- `LOCATION_SEQ_VALIDATED`

**Authority**
- Server validates.

## 19) Safety Incident

Firestore schema `safetyEvents` defines:
- `resolved` boolean + `resolvedAt` and `resolvedBy`
- types: `SOS | ROUTE_DEVIATION | DRIVER_MISMATCH | REPORT` and severity

**Lifecycle**
- create event (unresolved)
- optional resolution (admin/support flow)

