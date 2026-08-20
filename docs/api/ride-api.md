# ORA — Ride API

Amounts in API requests/responses use **integer minor units** (`amountMinor`, paisas) unless a documented display DTO formats rupees for UI-only fields.

## POST /v1/rides — Create Ride Request

**Auth:** Passenger  
**Idempotency-Key:** Required

Creates a P2P request with the passenger's offer. Does **not** assign a driver. Does **not** set `agreedFare`.

### Request Body

```json
{
  "pickup": {
    "lat": 31.5204,
    "lng": 74.3587,
    "address": "Gulberg III, Lahore",
    "placeId": "ChIJXXX"
  },
  "destination": {
    "lat": 31.5147,
    "lng": 74.3422,
    "address": "Liberty Market, Gulberg, Lahore",
    "placeId": "ChIJYYY"
  },
  "category": "easy",
  "passengerOfferMinor": 34000,
  "pricingSnapshotId": "ps_abc123",
  "paymentMethod": "CASH",
  "serviceType": "ride",
  "passengerCount": 1
}
```

There is no `isMarketplaceMode`. Marketplace (offer then passenger select) is the only model.

### Response 201 Created

```json
{
  "data": {
    "rideId": "ride_abc123",
    "state": "SEARCHING",
    "version": 1,
    "requestVersion": 1,
    "recommendedFareMinor": 34000,
    "passengerOfferMinor": 34000,
    "agreedFareMinor": null,
    "expiresAt": "2026-08-18T07:35:00Z"
  }
}
```

### Error Cases

- `422 FARE_OUT_OF_BOUNDS` — passenger offer outside `OfferBoundPolicy`
- `422 PRICING_SNAPSHOT_EXPIRED` — snapshot older than 10 minutes
- `422 SERVICE_AREA_VIOLATION` / `OUT_OF_SERVICE_AREA`
- `422 PAYMENT_METHOD_INVALID` — method not available for city/category/account
- `429 RATE_LIMITED`

---

## GET /v1/rides/:rideId — Get Ride

**Auth:** Passenger (own ride) or Driver (assigned ride, or currently eligible dispatched driver for limited fields)

### Response 200

```json
{
  "data": {
    "rideId": "ride_abc123",
    "state": "DRIVER_EN_ROUTE",
    "version": 4,
    "requestVersion": 1,
    "pickup": { "lat": 31.5204, "lng": 74.3587, "address": "..." },
    "destination": { "lat": 31.5147, "lng": 74.3422, "address": "..." },
    "category": "easy",
    "recommendedFareMinor": 34000,
    "passengerOfferMinor": 34000,
    "agreedFareMinor": 36000,
    "agreedOfferId": "offer_xyz",
    "assignedDriverId": "drv_456",
    "driver": {
      "displayName": "Moin Sultan",
      "rating": 4.88,
      "completedRides": 2140,
      "vehicle": { "make": "Suzuki", "model": "Alto", "color": "White", "plate": "LEA-2231" },
      "profilePhotoUrl": "https://..."
    },
    "estimatedArrivalMin": 4,
    "paymentMethod": "CASH",
    "createdAt": "2026-08-18T07:30:00Z"
  }
}
```

---

## GET /v1/rides/:rideId/offers — List Offers

**Auth:** Passenger (own ride)

Returns pending (and recently terminal) offers for comparison. Expired offers are not selectable.

---

## POST /v1/rides/:rideId/offers — Driver Create Offer

**Auth:** Driver (must be legitimately eligible / dispatched for this request)  
**Idempotency-Key:** Required

Replaces “accept assigns the ride”. This endpoint **only creates a RideOffer**.

### Request Body

```json
{
  "type": "PASSENGER_PRICE_ACCEPTED",
  "amountMinor": 34000,
  "expectedRequestVersion": 1,
  "message": null
}
```

or

```json
{
  "type": "DRIVER_COUNTEROFFER",
  "amountMinor": 38000,
  "expectedRequestVersion": 1,
  "message": "Traffic on MM Alam"
}
```

`PASSENGER_PRICE_ACCEPTED` requires `amountMinor == ride.passengerOfferMinor`.

### Response 201 Created

```json
{
  "data": {
    "offerId": "offer_xyz",
    "rideId": "ride_abc123",
    "driverId": "drv_456",
    "type": "PASSENGER_PRICE_ACCEPTED",
    "amountMinor": 34000,
    "currency": "PKR",
    "status": "PENDING",
    "requestVersion": 1,
    "expiresAt": "2026-08-18T07:33:12Z",
    "rideState": "OFFERS_AVAILABLE"
  }
}
```

Ride `state` is **not** `DRIVER_ASSIGNED`.

### Error Cases

- `403 DRIVER_NOT_ELIGIBLE` — not dispatched / not eligible
- `409 ALREADY_ASSIGNED` — ride already has a driver
- `409 STATE_CONFLICT` — ride not SEARCHING / OFFERS_AVAILABLE
- `409 OFFER_ALREADY_EXISTS` — driver already has a non-terminal offer for this requestVersion
- `422 FARE_OUT_OF_BOUNDS`
- `422 OFFER_AMOUNT_MISMATCH` — accept type but amount ≠ passengerOffer

Deprecated aliases (must not be used as assignment APIs):

- `POST /v1/rides/:rideId/accept` → same as create offer `PASSENGER_PRICE_ACCEPTED` if retained for compatibility
- `POST /v1/rides/:rideId/counter` → same as create offer `DRIVER_COUNTEROFFER`

Those aliases **must not** return `DRIVER_ASSIGNED`.

---

## POST /v1/rides/:rideId/offers/:offerId/select — Passenger Select Offer

**Auth:** Passenger who owns the ride  
**Idempotency-Key:** Required

This is the **assignment** command.

### Request Body

```json
{
  "expectedVersion": 2
}
```

### Response 200

```json
{
  "data": {
    "rideId": "ride_abc123",
    "state": "DRIVER_ASSIGNED",
    "version": 3,
    "assignedDriverId": "drv_456",
    "agreedFareMinor": 36000,
    "agreedOfferId": "offer_xyz",
    "currency": "PKR"
  }
}
```

### Error Cases

- `403 UNAUTHORIZED` — not the ride owner; drivers cannot select
- `409 ALREADY_ASSIGNED`
- `409 VERSION_CONFLICT`
- `422 OFFER_EXPIRED`
- `422 OFFER_STALE` — `requestVersion` mismatch
- `422 OFFER_NOT_SELECTABLE` — status not PENDING
- `422 DRIVER_NOT_ELIGIBLE` — driver no longer eligible at select time
- `404 OFFER_NOT_FOUND`

---

## POST /v1/rides/:rideId/offers/:offerId/withdraw — Driver Withdraw Offer

**Auth:** Offering driver  
Allowed only while `PENDING` and ride unassigned.

---

## POST /v1/rides/:rideId/arrive — Driver Arrive

**Auth:** Assigned driver  
**Idempotency-Key:** Required

---

## POST /v1/rides/:rideId/start — Start Ride

**Auth:** Assigned driver  
**Idempotency-Key:** Required

### Error Cases

- `422 PROXIMITY_VIOLATION`
- `422 INVALID_STATE_TRANSITION`
- `409 VERSION_CONFLICT`

---

## POST /v1/rides/:rideId/complete — Complete Ride

**Auth:** Assigned driver  
**Idempotency-Key:** Required

### Response 200

```json
{
  "data": {
    "rideId": "ride_abc123",
    "state": "RIDE_COMPLETED",
    "version": 5,
    "agreedFareMinor": 36000,
    "paymentIntentId": "pi_abc123"
  }
}
```

Ride completion updates the ride aggregate only. Payment continues on the payment aggregate from `agreedFareMinor`.

---

## POST /v1/rides/:rideId/cancel — Cancel Ride

**Auth:** Passenger or assigned driver (or requesting passenger before assignment)  
**Idempotency-Key:** Required

Pending offers become non-selectable.

---

## GET /v1/rides — List Rides (History)

**Auth:** Passenger (own) or Driver (own)

### Query Parameters

```
?limit=10
&cursor={nextCursor}
&status=completed|cancelled|all
&serviceType=ride|courier|intercity|move
```

History items expose `agreedFareMinor` (or null if never assigned), not a client-writable `finalFare`.
