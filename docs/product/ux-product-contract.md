# ORA — UX Product Contract

**Status:** CANONICAL product behavior  
**Reference:** publicly observable inDrive-style P2P fare negotiation. Ora does not copy undocumented inDrive internals.

Ora is **not** a conventional fixed-price dispatcher. The passenger proposes a price. Drivers respond with offers. The passenger chooses a driver. The selected offer becomes the immutable trip price.

---

## Passenger

```
Enter pickup
      ↓
Enter destination
      ↓
See recommended fare   ← guidance only
      ↓
Enter own price        ← passengerOffer
      ↓
Request ride           ← SEARCHING / dispatch starts
      ↓
See driver offers
      ↓
Compare:
  - driver price
  - rating
  - vehicle
  - ETA
  - completed rides
      ↓
Choose driver          ← assignment + agreedFare
      ↓
Ride confirmed
```

Passenger never “gets the first driver who taps Accept” as the canonical product. Accept only creates an offer.

---

## Driver

```
Go online
      ↓
See eligible requests   ← dispatch, not assignment
      ↓
Review:
  - pickup
  - destination / allowed destination information
  - passenger rating
  - passenger offered fare
  - ETA / distance
      ↓
Accept  OR  counteroffer  OR  decline
      ↓
Wait for passenger selection
      ↓
If selected:
  ride assigned
      ↓
Navigate to pickup
```

If another driver is selected, this driver's offer becomes `SUPERSEDED` and the request card disappears.

---

## Screen Mapping

| UX step | Feature | ViewModel concern |
|---|---|---|
| Pickup / destination | passenger + maps | route-ready local state |
| Recommended fare + own price | passenger / ride | estimate + offer input |
| Finding / offer inbox | ride | offer list stream |
| Choose driver | ride | `SelectRideOffer` |
| Live trip | ride + maps | assigned ride stream |
| Incoming request card | driver | pending dispatch stream |
| Accept / counter / decline | driver | create offer / miss |
| Wait for selection | driver | offer pending, not assigned |
| Navigate to pickup | driver | only after `DRIVER_ASSIGNED` |
