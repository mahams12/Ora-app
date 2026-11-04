# Ora Courier — Send Parcel

Status: implemented (backend + mobile). Local/unit-tested only — not yet
verified end-to-end on real devices or deployed.

## What this is

inDrive-style parcel delivery built on the existing ride marketplace.
A courier booking is a ride document with `serviceType: 'courier'` — it reuses
matching, dispatch waves, invitations, offers/counteroffers, assignment,
payout snapshot, location tracking, history, ratings, and earnings unchanged.

## Lifecycle mapping

| Courier phase              | Ride state            |
|---------------------------|-----------------------|
| Request created           | `SEARCHING` / `OFFERS_AVAILABLE` |
| Courier assigned          | `DRIVER_ASSIGNED`     |
| Heading to sender         | `DRIVER_EN_ROUTE`     |
| At pickup                 | `DRIVER_ARRIVED`      |
| Parcel onboard (pickup OTP) | `RIDE_STARTED`      |
| Delivered (delivery OTP)  | `RIDE_COMPLETED`      |
| Closed after completion   | `RIDE_CLOSED`         |
| Delivery attempt failed   | `DELIVERY_FAILED`     |
| Returning to sender       | `RETURNING`           |
| Return confirmed (return OTP) | `RETURNED`        |

`DELIVERY_FAILED` is not aggregate-terminal: `retryDelivery` transitions it
back to `RIDE_STARTED`, `startReturn` moves it to `RETURNING`.
`RETURNED` and `DELIVERY_FAILED` are closeable via the normal close path
(`RIDE_COMPLETED`/`RETURNED` are the closeable states).

Pickup-side failure: the driver cancels with a reason while still in
`DRIVER_ASSIGNED`/`DRIVER_EN_ROUTE`/`DRIVER_ARRIVED` — no separate
`PICKUP_FAILED` state exists.

## Confirmation codes (OTPs)

- Three server-generated codes (`pickupCode`, `deliveryCode`, `returnCode`)
  created inside the `selectOffer` transaction — never client input.
- Single-use, expiring, attempt-capped (`parcelOtp.attempts`,
  `PARCEL_OTP_MAX_ATTEMPTS`).
- The pre-transaction check verifies the caller is the **assigned driver**
  before touching the attempt counter — arbitrary drivers cannot lock a
  parcel by brute-forcing codes.
- Validity is re-verified inside the Firestore transaction; the `usedAt`
  stamp is written atomically with the state transition.
- Codes surface **only to the passenger** via `publicRide.otpCodes`
  (`pickup`, `delivery`, `return`, `expiresAt`, `*UsedAt`). Drivers never
  see the expected values.
- API: driver submits `otp` in the body of `POST /rides/:id/start`
  (pickup), `POST /rides/:id/complete` (delivery),
  `POST /rides/:id/return-complete` (return). `start` also accepts an
  optional `pickupPhotoUrl`.

## Parcel manifest

`RideDoc.parcel` (booking-time, server-validated via `parseParcelDetails`):

- `senderName`, `senderPhone`, `receiverName`, `receiverPhone`
- `parcelCategory`: documents | food | fragile | electronics | clothing | gifts | other
- `size`: SMALL | MEDIUM | LARGE · `weightKg` ≤ 30 · `quantity` 1–50
- `description`, optional `handlingInstructions`, optional `photoUrl` (https)

Visibility rules:

- `publicRide.parcel` — full manifest incl. contacts: passenger + assigned
  driver only (the endpoint is only callable by those two).
- Invite items + open-ride discovery — non-contact summary only
  (`parcelCategory`, `size`, `weightKg`, `quantity`, `description`).
- `parcel` is rejected on non-courier `serviceType`; unknown keys rejected.

## Cancellation rules

- Pre-assignment (`SEARCHING`/`OFFERS_AVAILABLE`): either side cancels as usual.
- Post-assignment through `DRIVER_ARRIVED`: both sides may cancel
  (`cancellationFeeMinor: 0` — no fees charged).
- After pickup (`RIDE_STARTED`/`DELIVERY_FAILED`/`RETURNING` —
  `COURIER_PARCEL_IN_TRANSIT`): **cancellation is refused**. A parcel in a
  courier's hands can never be "cancelled" — the only exits are delivery,
  failed-delivery → retry, or return-to-sender.

## Endpoints

| Method | Purpose |
|--------|---------|
| `POST /v1/rides` (`serviceType:'courier'`, `parcel`) | booking |
| `POST /v1/rides/:id/start` `{otp, pickupPhotoUrl?}` | confirm pickup |
| `POST /v1/rides/:id/complete` `{otp}` | confirm delivery |
| `POST /v1/rides/:id/delivery-failed` `{reason}` | record failed attempt |
| `POST /v1/rides/:id/retry-delivery` | DELIVERY_FAILED → RIDE_STARTED |
| `POST /v1/rides/:id/return-start` | DELIVERY_FAILED → RETURNING |
| `POST /v1/rides/:id/return-complete` `{otp}` | RETURNING → RETURNED |

Failure reasons (allow-list): `RECEIVER_UNREACHABLE`, `ADDRESS_INCORRECT`,
`RECEIVER_REJECTED`, `PARCEL_DAMAGED`, `OTHER`.

All mutations keep `Idempotency-Key`, `expectedVersion`, transaction-level
authorization, outbox events (`ride.delivery.failed`, `ride.delivery.retry`,
`ride.return.started`, `ride.returned`), and terminal trip-location cleanup
(fires on `RIDE_COMPLETED`/`RETURNED` only — `DELIVERY_FAILED` keeps
tracking alive for retry).

## Pricing

Courier bookings use the normal pricing pipeline with `category: 'courier'`.
Each active city needs a `pricingRules/{city}_courier` rule doc or the
estimate fails closed with `PRICING_UNAVAILABLE`. The local emulator E2E
seeds `lahore_courier`; **staging/prod need a seeded courier rule per city
before the feature is usable there** (ops step, not yet done).

## Mobile

- `ParcelDraft` (`domain/models/parcel_draft.dart`) — client-side manifest
  mirroring the server contract; validity gates submit.
- Passenger compose: courier chip in `_ServiceTypeSelector` → parcel form
  (`_ParcelSection`) with size/weight limits + prohibited-item list;
  review pane shows `_ParcelSummaryCard` instead of the ride-category grid.
- Home "Courier" tile → ride request with `serviceType: 'courier'`.
- Passenger active ride: parcel card + the three codes with used/active
  status; cancel button hidden once the parcel is onboard.
- Driver assigned job: courier copy for every state, parcel card with
  contacts, OTP bottom sheet for pickup/delivery/return confirms, failure
  sheet with reason chips, retry + return buttons. Cancel hidden after
  pickup.
- Invite/open-ride cards: `serviceLabel` shows "Courier · small · 2kg × n".
- History: rides/deliveries list with `serviceType: courier` filter;
  `RETURNED`/`DELIVERY_FAILED` treated as terminal.

## Verified

- `npm test` — 613/613 backend tests pass (serial), incl. 30 courier cases
  (booking validation, OTP expiry/single-use/attempt cap,
  unauthorized-driver attempt-lock prevention, cancellation gates,
  fail/retry/return, concurrent selects). Parallel runs occasionally flake
  on unrelated pre-existing concurrency tests (different tests each run).
- `scripts/run_local_emulator_e2e.ts` — **44/44 pass** on full emulators:
  ordinary ride regression leg (register → geo → estimate → dispatch →
  invite → decline → offer → assign → lifecycle → rating → expired-invite
  rejection) plus the courier leg: estimate → booking with manifest →
  invite with parcel summary (no contacts) → accept → select → passenger
  OTP visibility → wrong-OTP rejection → pickup OTP start → post-pickup
  cancel refusal → delivery OTP completion → consumed codes.
- `flutter analyze` — clean. `flutter test` — all suites pass.

## Not yet done / limitations

- No real-device E2E and no staging/prod deploy yet.
- Courier pricing rule docs must be seeded per city before use on staging/prod.
- `photoUrl`/`pickupPhotoUrl` are URL fields only — no upload pipeline in
  this phase.
- No return/cancellation fee logic — everything stays `feeMinor: 0` per spec.
- Buy & Deliver, pharmacy, vendor integrations, Loader: out of scope.

## Staging rollout — pricing rules (prepared, not deployed)

Courier estimates/acceptance read `pricingRules/{city}_{category}` from
Firestore via `buildPricingRuleSeed` (`src/pricing/pricing_rules_repository.ts`).
Before enabling courier on staging, seed a `courier` rule per active city —
there is no fallback: a missing rule fails the estimate and blocks booking.

Per-city document shape (values verified locally; tune per market):

| Field | Meaning | Local e2e (lahore_courier) |
|---|---|---|
| `ruleId` / doc id | `{citySlug}_courier` | `lahore_courier` |
| `city` / `category` | slug + `courier` | `lahore` / `courier` |
| `version` | rule version tag (audited) | `staging-1` suggested |
| `baseFare` | PKR base | `150` |
| `ratePerKm` | PKR/km | `70` |
| `ratePerMin` | PKR/min (est. duration) | `5` |
| `categoryMultiplier` | optional scalar, default `1` | `1` |
| `minFare` | PKR floor | `150` |
| `maxFare` | PKR cap | `8000` |
| `offerMinRatio` / `offerMaxRatio` | driver counteroffer bounds (defaults 0.7 / 2.5) | defaults |
| `active` | gate | `true` |

Notes:
- Rule values are PKR; the estimate service returns minor units
  (`recommendedFareMinor`). Local check: 3.6 km courier → Rs 440.
- Seed with the same helper used by
  `scripts/run_local_emulator_e2e.ts` (`lahore_courier` seed) against the
  staging project — do NOT run against production without approval.
- Every ride-category city needs a matching `courier` rule or courier
  booking fails closed for that city; the seven ride categories are
  unaffected either way.
