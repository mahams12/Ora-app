# Fare Engine Architecture (Recommended vs Offered vs Agreed)

Authoritative sources:
- `docs/algorithms/fare-engine.md`
- `docs/algorithms/offer-model.md`
- `docs/product/payment-flow.md`

## Four Fare Concepts (Distinct Values)

1. `recommendedFareMinor` (guidance)
   - Owner: Pricing service (server)
   - Persisted as part of `pricingSnapshots`
   - Snapshotted at ride creation; may expire before ride create

2. `passengerOfferMinor` (passenger input; immutable per `requestVersion`)
   - Owner: Passenger (via API)
   - Server validates bounds using configurable `OfferBoundPolicy`
   - Not equal to trip final price

3. `driverCounterOfferMinor` (driver offer amount)
   - Owner: Driver (via offers API)
   - Validated against `OfferBoundPolicy`

4. `agreedFareMinor` (final, immutable after assignment)
   - Owner: Server at assignment transaction
   - Copied from selected offer amount
   - Used to create payment intent obligations

## Recommended Fare Formula (Guidance Only)

Formula in `docs/algorithms/fare-engine.md`:
`R = (B + D×rKm + T×rMin + tolls + airportFee) × catMult × clamp(demandMult, 1.0, 1.8) × nightAdj`
Then rounding:
- `round(R/10) × 10`
- clamp to `minFare/maxFare` for recommendation
- persisted in integer minor units (`paisas`)

## Offer Bound Policy (Anti-Abuse Clamp)

`0.70R → 2.50R` is an example of an anti-abuse clamp, **not** pricing authority.
- configurable `offerMinRatio` / `offerMaxRatio`
- server rejects out-of-bounds passenger offers and driver counter offers with `422 FARE_OUT_OF_BOUNDS`

## Rounding / Units / Currency

- All persisted monetary amounts use **integer minor units** (PKR paisas).
- UI formatting is presentation-only; arithmetic uses minor units.

## Fare Locking / Authority

- Client cannot set `agreedFareMinor`.
- Backend must snapshot `FeePolicy` and `agreedFareMinor` at assignment/payment boundaries.

## Audit Trail

- `pricingSnapshots` immutable for the recommendation inputs
- `rideOffers` immutable amount + type
- `rides.agreedFareMinor` immutable after assignment

