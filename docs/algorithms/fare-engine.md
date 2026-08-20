# ORA — Fare Engine

## Product Model (Locked)

Ora uses a **peer-to-peer offered-fare** model, matching publicly observable inDrive-style behavior:

1. Route is calculated.
2. System calculates a **recommended fare**.
3. Passenger chooses their **offer price**.
4. Ride request is published with that offer.
5. Eligible drivers receive the request (dispatch).
6. Driver can **accept** the passenger price, **counteroffer**, or **decline**.
7. Passenger receives driver offers.
8. Passenger selects one driver/offer.
9. Selected driver is assigned through an authoritative Firestore transaction.
10. **Agreed fare** becomes immutable.
11. Trip proceeds.
12. Payment obligation is created from **agreed fare**, not from recommended fare.

This is **not** a conventional fixed-price ride-hailing service.

Public inDrive reference (external behavior only):

- pickup and destination determine a suggested fare
- passenger may submit the suggestion or a custom price
- drivers accept, counter, or decline
- passenger chooses among drivers using price, rating, vehicle, and ETA
- Ora does **not** claim knowledge of inDrive's private algorithm or infrastructure

---

## Four Fare Concepts

| Field | Meaning | Authority | Mutability |
|---|---|---|---|
| `recommendedFareMinor` | Server guidance from the fare engine | Pricing service | Mutable before request; snapshotted at create |
| `passengerOfferMinor` | Price the passenger is willing to pay | Passenger via API | Immutable for that `requestVersion` |
| `driverCounterOfferMinor` | Price on a `DRIVER_COUNTEROFFER` offer | Driver via API | Immutable offer record |
| `agreedFareMinor` | Selected offer amount | Server at assignment | **Immutable after assignment** |

No client may write `agreedFareMinor`.

---

## Recommended Fare Formula

The formula below produces **guidance only**. It does not set the trip price.

```
R = (B + D × rKm + T × rMin + tolls + airportFee)
    × catMult
    × clamp(demandMult, 1.0, 1.8)
    × nightAdj

R_rounded = round(R / 10) × 10
R_final = clamp(R_rounded, minFare, maxFare)
recommendedFareMinor = R_final × 100   // persist integer paisas
```

All persisted and API amounts use **integer minor units** (`amountMinor`, paisas). UI may format rupees.

### Variable Definitions

| Variable | Description |
|---|---|
| `B` | Base fare (per category, per city zone) |
| `D` | Route distance in km (Google Routes API) |
| `rKm` | Rate per km |
| `T` | Estimated duration in minutes |
| `rMin` | Rate per minute |
| `tolls` | Toll estimate from Routes API |
| `airportFee` | Airport surcharge if applicable |
| `catMult` | Category multiplier |
| `demandMult` | Zone demand adjustment, clamped |
| `nightAdj` | Night adjustment if policy enabled |
| `minFare` / `maxFare` | Category floors/ceilings for the **recommendation** |

Parameters live in `pricingRules/{city}_{category}` and are admin-configurable.

### Demand and historical median

Demand multiplier and historical median remain **recommendation smoothers**. They must not silently rewrite a passenger offer or an agreed fare.

If a pricing snapshot expires (10 minutes) before ride create, the server returns a new recommendation. The passenger must confirm a new `passengerOffer`.

---

## Offer Bound Policy (Anti-Abuse, Not The Pricing Model)

`0.70R → 2.50R` is **not** Ora's pricing model.

If retained, it is a **configurable `OfferBoundPolicy`**: a server-side anti-abuse clamp on how far passenger offers and driver counteroffers may deviate from the current recommended fare.

```
policy.offerMinRatio   // example default 0.70 — configurable
policy.offerMaxRatio   // example default 2.50 — configurable
allowedMinMinor = recommendedFareMinor × offerMinRatio
allowedMaxMinor = recommendedFareMinor × offerMaxRatio
```

Stored per city/category in `pricingRules` / `offerBoundPolicies`. Admins may change ratios without changing the P2P product.

Server rejects out-of-bound passenger offers and driver counteroffers with `422 FARE_OUT_OF_BOUNDS`.

---

## pricingSnapshot

Created at estimate time; referenced at ride create. Immutable after write.

```json
{
  "snapshotId": "ps_abc123",
  "pricingRulesVersion": "2026-08-18:v1.2",
  "inputs": {
    "distanceKm": 5.8,
    "durationMin": 14,
    "categoryId": "easy",
    "zoneId": "gulberg_III",
    "demandMult": 1.1,
    "nightAdj": 1.0,
    "tollsMinor": 0,
    "airportFeeMinor": 0
  },
  "recommendedFareMinor": 34000,
  "offerBoundMinMinor": 23800,
  "offerBoundMaxMinor": 85000,
  "currency": "PKR",
  "computedAt": "2026-08-18T07:30:00Z",
  "expiresAt": "2026-08-18T07:40:00Z"
}
```

`passengerOfferMinor` is stored on the **ride**, not used to overwrite this snapshot's recommended fare.

---

## After Assignment

`agreedFareMinor` is copied from the selected offer and never recalculated from `R`.

Payment, fees, and driver net are derived from:

- `agreedFareMinor`
- snapshotted `FeePolicy`
- payment method
- later adjustments/refunds via ledger

not from a fresh call to this engine.
