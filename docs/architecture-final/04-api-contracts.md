# API Contract Freeze (Mobile ↔ Backend)

This file freezes the **canonical Cloud Run HTTP API contract** used by the Ora Flutter client and other services.

Authoritative sources:
- `docs/api/api-contract.md`
- `docs/api/ride-api.md`
- `docs/ORA_MASTER_PLAN.md`
- `docs/architecture/backend-architecture.md`
- `docs/architecture-review/event-contracts.md`
- `docs/product/payment-flow.md`
- `docs/security/abuse-prevention.md`
- `docs/api/error-codes.md`

## Common Headers

- `Authorization: Bearer {firebase_id_token}`
- `X-Firebase-AppCheck: {app_check_token}`
- `Idempotency-Key: {key}` (required on business-critical mutations)
- `X-Request-Id: {uuid}` (for trace correlation; client-generated)
- `X-Client-Version: {appVersion}`
- `X-Platform: android | ios`

## Common Error Contract

Errors use `docs/api/error-codes.md` with logical codes such as:
`UNAUTHENTICATED, UNAUTHORIZED, APP_CHECK_FAILED, ALREADY_ASSIGNED, STATE_CONFLICT, VERSION_CONFLICT, OFFER_EXPIRED, OFFER_STALE, OFFER_NOT_SELECTABLE, PAYMENT_FAILED, RECONCILIATION_REQUIRED, RATE_LIMITED`, etc.

## Endpoint Inventory

### Ride (core marketplace lifecycle)

1. `POST /v1/rides`
   - Auth: passenger
   - Idempotency-Key: required
   - Side effects: creates `rides` doc; triggers dispatch start
   - Emits (durable): `ride.created`, then dispatch fanout events via outbox
   - Request: `pickup, destination, category, passengerOfferMinor, pricingSnapshotId, paymentMethod, serviceType, passengerCount`
   - Errors: `VALIDATION_ERROR, FARE_OUT_OF_BOUNDS, PRICING_SNAPSHOT_EXPIRED, SERVICE_AREA_VIOLATION, 429`

2. `GET /v1/rides/{rideId}`
   - Auth: passenger (own ride) or assigned driver (read restricted)
   - Side effects: none
   - Errors: `RIDE_NOT_FOUND`

3. `GET /v1/rides/{rideId}/offers`
   - Auth: passenger (own ride)
   - Side effects: none
   - Errors: `OFFER_NOT_FOUND` (for any requested offer)

4. `POST /v1/rides/{rideId}/offers`
   - Auth: driver (eligible/dispatched only)
   - Idempotency-Key: required
   - Side effects: creates `rideOffers` document with status `PENDING`
   - Emits (durable): `ride.offer.received`
   - Errors: `DRIVER_NOT_ELIGIBLE, STATE_CONFLICT, OFFER_ALREADY_EXISTS, FARE_OUT_OF_BOUNDS`

5. `POST /v1/rides/{rideId}/offers/{offerId}/select`
   - Auth: passenger (own ride)
   - Idempotency-Key: required
   - Side effects: **atomic assignment** in Firestore transaction; writes `agreedFareMinor` snapshot; outbox ride.assigned
   - Emits (durable): `ride.offer.selected`, `ride.assigned`
   - Errors: `ALREADY_ASSIGNED, VERSION_CONFLICT, OFFER_EXPIRED, OFFER_STALE, OFFER_NOT_SELECTABLE, DRIVER_NOT_ELIGIBLE`

6. `POST /v1/rides/{rideId}/offers/{offerId}/withdraw`
   - Auth: offering driver
   - Idempotency-Key: required
   - Side effects: withdraws offer (no assignment)

7. `POST /v1/rides/{rideId}/arrive`
   - Auth: assigned driver
   - Idempotency-Key: required
   - Side effects: validates proximity; may transition `DRIVER_EN_ROUTE → DRIVER_ARRIVED`
   - Errors: `PROXIMITY_VIOLATION, VERSION_CONFLICT, INVALID_STATE_TRANSITION`

8. `POST /v1/rides/{rideId}/start`
   - Auth: assigned driver
   - Idempotency-Key: required
   - Side effects: proximity-validated transition `DRIVER_ARRIVED → RIDE_STARTED`

9. `POST /v1/rides/{rideId}/complete`
   - Auth: assigned driver
   - Idempotency-Key: required
   - Side effects: transition `RIDE_STARTED → RIDE_COMPLETED` (payment aggregate continues separately)
   - Emits (durable): `ride.completed`

10. `POST /v1/rides/{rideId}/cancel`
   - Auth: passenger or assigned driver
   - Idempotency-Key: required
   - Side effects: cancels ride; makes pending offers non-selectable; emits `ride.cancelled`

11. `GET /v1/rides`
   - Auth: passenger/driver for own history
   - Side effects: none

### Driver

12. `POST /v1/drivers/go-online`
   - Auth: driver
   - Side effects: updates durable availability state; presence projection begins
   - Errors: `DRIVER_NOT_APPROVED`

13. `POST /v1/drivers/go-offline`
   - Auth: driver
   - Side effects: stops presence projection

14. `GET /v1/drivers/nearby`
   - Auth:
     - backend/internal services: full candidate metadata
     - passenger client: optional future coarse availability surface only
   - Privacy:
     - no exact raw driver coordinates to unaffiliated passenger
     - no driver identity unless ride/offer/assignment relationship exists
   - Rate limit:
     - passenger pre-booking: 10/min per user
   - Frozen by `docs/architecture-final/24-phase-1.6-condition-closure.md` section 10

### Location

15. `POST /v1/location/update`
   - Auth: driver
   - Idempotency-Key: **not required** (GPS updates are fire-and-forget)
   - Side effects: validates and writes server projection to RTDB + updates Redis GEO
   - Errors: `INVALID_LOCATION, STALE_LOCATION, SEQUENCE_VIOLATION`

### Pricing

16. `POST /v1/pricing/estimate`
   - Auth: passenger (read-only mutation)
   - Side effects: creates `pricingSnapshots` document; dispatches estimate result for UI

17. `GET /v1/pricing/rules`
   - Auth: any authenticated user

18. `GET /v1/pricing/snapshot/:rideId`
   - Auth: passenger (own estimate context)

### Payments

19. `POST /v1/payments/initiate`
   - Auth: passenger (own ride)
   - Idempotency-Key: required
   - Side effects: creates `paymentIntents`, `paymentAttempts`

20. `POST /v1/payments/cash-collected`
   - Auth: driver (assigned)
   - Idempotency-Key: required
   - Side effects: moves payment intent state, posts cash capture + ledger obligations

21. `POST /v1/payments/refund`
   - Auth: admin/server
   - Idempotency-Key: required

### Auth / Admin

22. `POST /v1/auth/verify-driver`
   - Auth: admin/server

23. `GET /v1/auth/me`
   - Auth: any authenticated user
   - Response body (frozen, Phase 2 correction pass):

   ```json
   {
     "uid": "string",
     "phoneNumber": "string (E.164)",
     "displayName": "string | null",
     "role": "passenger | driver | admin",
     "driverStatus": "none | pending | approved | suspended",
     "isActive": true,
     "banned": false,
     "profileComplete": true
   }
   ```

   - `profileComplete` is **server-derived and required**. The server decides
     whether the `users/{uid}` document holds every field the ride flows need.
     Clients must read this field verbatim and must never recompute it from
     `role`, `isActive`, or `banned` — those inputs are not sufficient and the
     completeness rule may change server-side without a client release.
   - `role` and `driverStatus` are server-authoritative custom claims. Clients
     treat them as read-only.
   - Until the backend exists, the client fails closed: a missing
     `profileComplete` is read as `false`, which routes the user to onboarding
     rather than granting access to home.

23a. `POST /v1/auth/register`
   - Auth: any authenticated user (own uid only)
   - Idempotency-Key: required — client uses `register_{uid}`
   - Side effects: creates `users/{uid}` in Firestore on first sign-in; assigns
     `role: "passenger"` server-side
   - Duplicate calls with the same idempotency key must replay the same outcome
     without creating a second document.

24. `POST /v1/admin/force-transition`
   - Auth: admin
   - Side effects: server-only correction for pre-terminal violations; must append audit log.

25. `POST /v1/admin/suspend-driver`
   - Auth: admin

## Phase 1.6 Freeze

The following contracts are now explicitly frozen and no longer TBD:
- idempotency lifecycle and local persistence requirements: `24-phase-1.6-condition-closure.md` section 2
- OTP state machine and throttling semantics: section 4
- nearby-driver authorization/privacy contract: section 10

## Event Emission Contract (Durable)

Durable events come from `docs/architecture-review/event-contracts.md` and must include:
`eventId, eventType, aggregateType, aggregateId, aggregateVersion, schemaVersion, correlationId, causationId`.

Correctness-critical projections must derive from Firestore + outbox; FCM/FCM are best-effort.

