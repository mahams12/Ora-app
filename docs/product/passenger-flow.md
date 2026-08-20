# ORA — Passenger Flow

**Canonical UX:** `docs/product/ux-product-contract.md`  
**Architecture:** MVVM Views/ViewModels — `docs/architecture/flutter-mvvm-architecture.md`

Presentation is **Views**, not controller-screens. Routes below remain navigation identifiers.

## Views (from prototype analysis)

| View ID | Purpose | Route |
|---|---|---|
| Splash | Brand intro; auto-navigate after 2s | `/splash` |
| Sign Up | Name, phone, password; social auth | `/auth/signup` |
| Sign In | Phone + password; social auth | `/auth/signin` |
| OTP | 4-digit verification; resend | `/auth/otp` |
| Home | Map + services grid + ride categories + saved places | `/home/passenger` |
| My Rides | Trip history with tabs (All, Rides, Courier, Move) | `/rides` |
| Saved Places | Home, Work, custom favourites | `/saved` |
| Wallet | Balance, add money, payment methods, recent | `/wallet` |
| Payment Methods | Cash, Wallet, JazzCash, Easypaisa, Card | `/payments` |
| Refer & Earn | Referral code, stats | `/refer` |
| Safety Centre | Share trip, emergency contacts, SOS, verify driver | `/safety` |
| Help Centre | Search, topics, chat | `/help` |
| Profile | Stats, quick actions | `/profile` |
| Settings | Account, preferences, safety, support | `/settings` |
| Intercity | City-to-city booking with date/vehicle | `/intercity` |
| Courier | Package delivery booking | `/courier` |
| Courier Confirm | Price offer + confirm | `/courier/confirm` |
| Move & Load | House move booking | `/move` |
| Move Confirm | Price offer + confirm | `/move/confirm` |
| Destination | Map + pickup/destination fields | `/home/passenger/destination` |
| Vehicle Selection | Category + recommended fare + passenger offer | `/home/passenger/vehicle` |
| Finding | Searching; then offer inbox | `/home/passenger/finding` |
| Offer Inbox | Compare driver offers | `/home/passenger/offers` |
| Live Trip | Map + driver info + ETA | `/home/passenger/live` |
| Rate | Receipt + star rating | `/home/passenger/rate` |

## Passenger Ride Booking Flow

```
1. HOME
   │ User taps "Where are you headed?" search bar
   │ OR taps a service card (City Rides, Intercity, Courier, Move)
   │ OR taps a saved ride category card
   ▼

2. DESTINATION
   │ Pickup auto-detected from GPS
   │ User types destination → Places autocomplete
   │ Saved places shown for quick selection
   │ Recent places shown
   │ User confirms destination
   ▼

3. VEHICLE SELECTION
   │ Map shows pickup → destination route (polyline)
   │ ETA and distance shown
   │ Vehicle categories listed:
   │   Zip (bike) | Trio (rickshaw) | Easy | Breeze | Executive | Premium
   │ Each card shows: icon, name, description, RECOMMENDED fare
   │ User selects category
   │ Payment method shown (availability from FeePolicy + city/account; Cash often default)
   ▼

4. PASSENGER OFFER (inline on vehicle selection)
   │ System shows recommendedFare (guidance only — not the trip price)
   │ Passenger enters passengerOffer
   │ Server may enforce configurable OfferBoundPolicy (anti-abuse)
   │ Passenger does NOT set agreedFare
   │ "Confirm Easy · Rs 340" CTA submits the offer price
   ▼

5. FINDING (SEARCHING)
   │ Radar animation shown
   │ "Matching nearby drivers — they can accept your price or counter"
   │ Cancel button available
   │ Timeout: 5 minutes with no selectable offers → EXPIRED
   │ First pending driver offer → OFFERS_AVAILABLE
   ▼

6. OFFER INBOX (OFFERS_AVAILABLE)
   │ Card per pending RideOffer:
   │   Photo, name, rating, completed rides, vehicle, plate, ETA, offered amount
   │   Type: PASSENGER_PRICE_ACCEPTED or DRIVER_COUNTEROFFER
   │ Passenger compares and selects one offer
   │ Server assignment transaction commits DRIVER_ASSIGNED + immutable agreedFare
   │ Driver Accept never auto-assigns
   ▼

7. LIVE TRIP (DRIVER_EN_ROUTE and later)
   │ Full-screen map
   │ Driver marker moves in real time (RTDB)
   │ ETA countdown
   │ Driver info card: name, rating, plate, phone, message
   │ "Share trip" button
   │ Trip: EN_ROUTE → ARRIVED → STARTED → RIDE_COMPLETED
   ▼

8. TRIP COMPLETION
   │ Receipt from agreedFare + fee snapshot + payment method
   │ Star rating for driver (1–5)
   │ Optional tip (Phase 11+)
   │ "Done" → home
```

There is **no Direct Mode**. There is **no first-accept-wins assignment**.

## Drawer Navigation (Passenger)

```
≡ Menu
├── Profile section (avatar, name, rating)
├── Home
├── My Rides
├── Wallet
├── Saved Places
├── Refer a Friend
├── Safety Centre
├── Help Centre
├── Settings
└── Switch to Driver Mode
```

## Service Cards (Home)

- **City Rides** — point-to-point; categories: Zip, Trio, Easy, Breeze, Executive, Premium
- **Intercity** — city-to-city; Sedan, SUV, Van, Premium; date/time scheduler
- **Courier** — package delivery; Docs, Food, Clothes, Gift, Electronics; Bike or Car courier
- **Move** — house/office move; truck + loaders; disassembly options

## Fare Display Convention (from prototype)

```
Rs 120   — Zip (bike)
Rs 180   — Trio (rickshaw)
Rs 340   — Easy (compact)
Rs 420   — Breeze (AC comfort)
Rs 690   — Executive (van, trunk)
Rs 990   — Premium (luxury)
```

These numbers are **recommended fares**. The trip price is the later **agreedFare** from the selected offer.
