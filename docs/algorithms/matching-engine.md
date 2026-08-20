# ORA — Matching Engine

## Overview

The matching engine runs server-side in the Ride Engine service. It is triggered immediately after a ride request is created.

**Dispatch is not assignment.** This engine only finds and notifies eligible drivers so they can create offers. Assignment happens later when the passenger selects an offer (`docs/algorithms/offer-model.md`, `docs/algorithms/ride-assignment.md`).

1. **Generate candidates** — find eligible nearby drivers
2. **Rank candidates** — order by suitability
3. **Dispatch in waves** — present the request to bounded candidate groups
4. **Stop dispatch** — on assignment, passenger cancel, or request TTL — not on the first driver Accept

## Step 1: Candidate Generation (Redis GEO)

```redis
GEORADIUS geo:drivers:{city} {pickupLng} {pickupLat} 10 km
  ASC           # closest first
  WITHCOORD     # include coordinates
  WITHDIST      # include distance
  COUNT 100     # fetch top 100 for filtering
```

Initial radius: Wave-configured. If fewer than the minimum candidate count are eligible, expand per wave.  
If still insufficient after final wave: notify all remaining eligible candidates in the final configured set and show passenger "Fewer drivers available in your area".

## Step 2: Filtering

Apply in sequence (early exit on each):

```
Filter 1: Is driver online?
  → Check RTDB driverPresence/{driverId}.online == true
  → Check Redis driver:online:{driverId} (TTL key, backup check)
  
Filter 2: Is driver account approved?
  → drivers/{driverId}.driverStatus == "approved"
  → NOT in suspended list

Filter 3: Is vehicle approved for this category?
  → vehicles/{vehicleId}.approvedCategories.contains(requestedCategory)
  → vehicles/{vehicleId}.vehicleStatus == "approved"

Filter 4: Is driver available (no active ride)?
  → drivers/{driverId}.activeRideId == null
  → OR rides/{activeRideId}.state is terminal

Filter 5: Is location fresh?
  → lastLocationTs > now - 15s
  → Checked from Redis driver:online:{driverId}.lastLocationTs

Filter 6: Is location accurate?
  → lastLocationAccuracy < 50m
  → Checked from Redis or recent RTDB value

Filter 7: Is driver within service area?
  → Pickup coordinates within serviceAreas/{city}.polygon (server-side point-in-polygon)

Filter 8: Driver preferences
  → Driver has not blocked this passenger (rare but must be checked)
  → Driver's vehicle capacity >= requested passengers (for intercity)
```

## Step 3: Ranking

For each filtered candidate, compute score:

```
eta_normalized = clamp(etaMinutes / 15.0, 0.0, 1.0)   // normalize to 0-15 min range
dist_normalized = clamp(distanceKm / 10.0, 0.0, 1.0)  // normalize to 0-10 km range
adjusted_rating = ((20 * globalMeanRating) + (driver.ratingCount * driver.rating))
                  / (20 + max(driver.ratingCount, 0))
rating_normalized = (adjusted_rating - 1.0) / 4.0      // prior-adjusted 1-5 star → 0.0-1.0
cancellation_rate = driver.cancelledRides / max(driver.totalRides, 1)
noshow_rate = driver.noShowCount / max(driver.totalRides, 1)
completed_bonus = clamp(driver.completedRides / 500, 0.0, 1.0)  // caps at 500 rides

score =  0.40 × (1.0 - eta_normalized)       // ETA weight (most important)
       + 0.20 × rating_normalized             // Rating
       + 0.15 × (1.0 - dist_normalized)       // Proximity
       + 0.10 × (1.0 - cancellation_rate)     // Reliability
       + 0.10 × (1.0 - noshow_rate)           // No-show reliability
       + 0.05 × completed_bonus               // Experience bonus

Sort descending: highest score notified first
```

ETA estimation:
- Primary: Google Distance Matrix API call for top 10 candidates (1 element each)
- Fallback (if Distance Matrix quota exceeded): Euclidean distance ÷ average speed estimate

Note: Distance Matrix API called server-side only (API key not in Flutter).

## Step 4: Notification

```
Dispatch proceeds in deterministic waves:

Wave 1:
  - top 5 candidates
  - radius: initialRadiusKm
  - wait window: 5 seconds

Wave 2:
  - next 10 candidates
  - radius: expandedRadiusKm
  - wait window: 5 seconds
  - only if ride still unresolved

Wave 3:
  - next 15 candidates
  - radius: finalRadiusKm
  - wait window: until ride TTL, passenger cancel, or assignment
  - only if ride still has no assigned driver (offers may already exist)

For each driver in the active wave:
  1. Write to RTDB: rideRequests/{driverId}/pending/{rideId} = {...}
  2. Send FCM data message fallback
  3. Record in Redis: dispatch:notified:{rideId} = [driverId...]
```

Wave expansion continues while the ride is `SEARCHING` or `OFFERS_AVAILABLE`. Existing offers do **not** stop later waves unless a configured “enough offers” threshold is met.

On **assignment** (passenger selected an offer), the server:

- cancels any scheduled later waves
- uses `dispatch:notified:{rideId}` to clean up RTDB pending cards
- does **not** treat driver Accept as the stop condition

## Step 5: TTL Management

- Request cards on driver screen expire at `expiresAt` (5 minutes)
- Server Cloud Scheduler sweeps expired SEARCHING rides every 30 seconds
- Expired rides transitioned to EXPIRED state; RTDB cleaned up

## Driver Score Metrics (maintained per driver)

```
drivers/{driverId}:
  rating: 4.88            // running weighted average
  totalRides: 1247
  completedRides: 1192
  cancelledRides: 42
  noShowCount: 13
  acceptanceRate: 0.78    // accepted / received
  completionRate: 0.956   // completed / accepted
```

Updated after each trip completion or cancellation (server Admin SDK).

## Future ML Expansion (Phase 14+)

The scoring function is explicitly designed to be replaceable by an ML model:

- All features are numerical and normalized
- Training data = completed ride outcomes (rating, passenger re-booking)
- Model input: same feature vector
- Model output: predicted success probability (replaces hand-tuned weights)
- A/B test deterministic vs ML in Phase 14
