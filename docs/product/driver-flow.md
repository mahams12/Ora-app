# ORA — Driver Flow

**Canonical UX:** `docs/product/ux-product-contract.md`

## Driver Onboarding Flow

```
1. Passenger taps "Switch to Driver Mode" / "Earn on Ora"
2. [If no driver account] → Driver Onboarding begins

STEP 1: Personal Details
  - Full name
  - CNIC number
  - Date of birth

STEP 2: Vehicle Information
  - Make, Model, Year, Color
  - Licence plate
  - Vehicle category (Zip/Trio/Easy/Breeze/Executive/Premium)
  - Seating capacity

STEP 3: Document Upload
  Required:
  - Driving licence (front + back) ✓
  - Vehicle registration certificate ✓
  - CNIC copy ✓
  - Vehicle photo ✓
  Optional:
  - Insurance certificate (blue badge)
  
STEP 4: Pending Review Screen
  - "Documents submitted for review"
  - Expected review time: 24–48 hours
  - Status polling via Firestore listener
  - Push notification on approval/rejection
```

## Document Status States (from prototype)

```
✓ (ok)      — Uploaded and approved
⏳ (pending) — Under review
✗ (miss)    — Required but not uploaded
ℹ (opt)     — Optional, not required
```

## Driver Home Screen

```
┌──────────────────────────────┐
│ [Map — full background]       │
│                               │
│ [Go Online / Offline toggle]  │
│                               │
│ Today's earnings: Rs 1,240   │
│ 4 rides · 4.9 ★              │
│                               │
│ [Hot zones overlay — optional]│
└──────────────────────────────┘
```

Earnings shown here are **projections** of the driver earnings ledger, not a client-owned balance.

## Incoming Ride Request (Dispatch, not assignment)

```
Full-screen or banner overlay:
┌──────────────────────────────┐
│ 🔔 NEW RIDE REQUEST          │
│                               │
│ Gulberg III → Liberty Market │
│ 5.8 km · Est. 14 min         │
│                               │
│ Passenger rating: ⭐ 4.8      │
│ Passenger offer: Rs 340       │
│ Recommended: Rs 320           │
│                               │
│ [15-second countdown ring]    │
│                               │
│ [DECLINE] [COUNTER] [ACCEPT] │
└──────────────────────────────┘
```

Timeout: 15 seconds → card auto-dismisses; driver marked "missed" for this request. Missed/declined is **not** an offer.

Dispatch membership is required before Accept or Counter. Ineligible drivers must not create offers.

## Driver Accept Flow (creates an offer)

```
1. Driver taps "Accept"
2. POST /v1/rides/{id}/offers
     type = PASSENGER_PRICE_ACCEPTED
     amountMinor = ride.passengerOfferMinor
3. Success 201:
   → RideOffer status = PENDING (selectable by passenger)
   → Ride may move SEARCHING → OFFERS_AVAILABLE
   → Driver UI: "Waiting for passenger to choose"
   → Driver is NOT assigned
4. If ride already assigned / expired / driver ineligible:
   → 409 STATE_CONFLICT / ALREADY_ASSIGNED / DRIVER_NOT_ELIGIBLE
   → Card dismissed
```

Accepting the passenger price is **not** `DRIVER_ASSIGNED`.

## Counter-Offer Flow (also creates an offer)

```
1. Driver taps "Counter"
2. Counter amount input shown (OfferBoundPolicy if configured)
3. POST /v1/rides/{id}/offers
     type = DRIVER_COUNTEROFFER
     amountMinor = driver proposed amount
4. Offer is PENDING until passenger selects, rejects, expires, or withdraws
5. Driver waits for passenger selection
```

## After Passenger Selection

```
If this driver's offer is SELECTED:
  → Firestore assignment transaction
  → state = DRIVER_ASSIGNED
  → agreedFareMinor copied from the offer (immutable)
  → Map switches to "Navigate to pickup"

If another offer is selected:
  → this offer SUPERSEDED
  → pending card removed
  → driver remains available
```

Drivers cannot select themselves. Drivers cannot write `assignedDriverId` or `agreedFareMinor`.

## Active Trip Flow

```
DRIVER_EN_ROUTE:
├── Map: navigate to pickup coordinates
├── Passenger info shown (name, profile photo)
├── Passenger can call or message
└── Tap "I've arrived" → server validates proximity (< 100m)

DRIVER_ARRIVED:
├── "Waiting for passenger"
├── 5-minute countdown
├── Passenger notified via FCM + RTDB
└── Passenger boards → driver taps "Start Ride"

RIDE_STARTED:
├── Map: navigate to destination
├── Trip timer running
├── Emergency SOS accessible
└── Tap "End Ride" → server validates proximity to destination

RIDE_COMPLETED:
├── Payment aggregate starts from agreedFare (separate from ride SM)
├── Cash: driver confirms CASH_COLLECTED
├── Digital: server waits for verified provider callback
├── Receipt shown from ledger snapshot
├── Rate passenger (1–5 stars)
└── Return to online state
```

## Driver Earnings Screen

```
Dashboard:
├── Today / week / month nets from earnings ledger
├── Completion rate, acceptance rate, rating

Earnings breakdown (per trip, from ledger — not fare − 10%):
├── agreedFare / grossFare
├── platformFee (FeePolicy snapshot)
├── paymentProviderFee (if any)
├── tolls / airportFee
├── adjustments / refunds
└── driverNetAmount

Payout:
├── Bank transfer (JazzCash / Easypaisa / bank)
├── Settlement per payout policy
└── Minimum payout threshold from policy
```

`driverNetAmount` is derived from the immutable financial ledger using the snapshotted `FeePolicy`. It is not a hardcoded percentage of fare.

## Bonus & Hot Zone System

```
Hot Zones:
├── Areas of high demand highlighted on driver map
├── Color coded by demand level (gold → red)
├── Driving to hot zone increases request probability
└── Visual: pulsing overlay on map

Bonuses:
├── Quest bonus: "Complete 8 rides today → earn Rs 500"
├── Peak hour bonus if a bonus policy is active
├── Streak / monthly target bonuses if configured
```

Bonuses are ledger adjustments, not client-invented amounts.

## Driver Documents & Vehicle Information (from prototype)

Documents required:
- Driving licence (Required)
- CNIC / National ID (Required)
- Vehicle registration (Required)
- Vehicle photo (Required)
- Insurance certificate (Optional)
- Fitness certificate (Optional)

Vehicle form fields:
- Make, Model, Year, Colour
- Licence plate number
- Registration city
- Fuel type
- Seating capacity
- Category eligibility
