# ORA — Firestore Schema

## Security Notation
- **[C]** = Client can read/write
- **[S]** = Server (Admin SDK) only
- **[R]** = Client can read; server writes
- **[A]** = Admin only

---

## Collection: `users`

Document ID: `{uid}` (Firebase Auth UID)

| Field | Type | Access | Notes |
|---|---|---|---|
| uid | string | [R] | Immutable; matches Auth UID |
| displayName | string | [C] | |
| phoneNumber | string | [R] | Set on auth; not client-writable post-onboard |
| email | string | [C] | |
| profilePhotoUrl | string | [C] | GCS URL (signed by server) |
| role | string | [S] | "passenger" \| "driver" \| "admin" |
| driverStatus | string | [S] | "none" \| "pending" \| "approved" \| "suspended" |
| rating | number | [R] | Running average; server-computed |
| totalTrips | number | [R] | Server-computed |
| isActive | boolean | [S] | Account active flag |
| banned | boolean | [S] | Soft ban |
| bannedReason | string | [A] | Admin-only |
| referralCode | string | [R] | Assigned on registration |
| referredBy | string | [S] | UID of referrer |
| createdAt | timestamp | [S] | Immutable |
| updatedAt | timestamp | [S] | Server-managed |
| preferredLanguage | string | [C] | "en" \| "ur" |
| notificationsEnabled | boolean | [C] | |
| emergencyContactsCount | number | [R] | Count only; contacts encrypted separately |

**Indexes:**
- `phoneNumber` (unique lookup)
- `referralCode` (unique lookup)

---

## Collection: `drivers`

Document ID: `{driverId}` (same as uid)

| Field | Type | Access | Notes |
|---|---|---|---|
| driverId | string | [R] | Immutable |
| userId | string | [R] | Reference to users/{uid} |
| fullName | string | [S] | From CNIC verification |
| cnicNumber | string | [S] | Masked in reads: "42101-****-1" |
| dateOfBirth | date | [S] | |
| driverStatus | string | [S] | "pending" \| "approved" \| "suspended" \| "rejected" |
| approvedAt | timestamp | [S] | |
| approvedBy | string | [A] | Admin UID |
| rejectionReason | string | [S] | Shown to driver |
| rating | number | [R] | Server-computed |
| ratingCount | number | [R] | Total ratings received |
| totalRides | number | [R] | |
| completedRides | number | [R] | |
| cancelledRides | number | [R] | |
| noShowCount | number | [R] | |
| acceptanceRate | number | [R] | 0.0–1.0 |
| completionRate | number | [R] | 0.0–1.0 |
| activeVehicleId | string | [R] | Reference to vehicles/{id} |
| activeRideId | string | [R] | Null if available |
| availabilityState | string | [S] | Durable business availability: "offline" \| "online" \| "busy" \| "suspended" |
| lastOnlineAt | timestamp | [R] | |
| homeCity | string | [C] | Preferred operating city |
| preferredCategories | string[] | [C] | Driver's preferred category list |
| createdAt | timestamp | [S] | Immutable |
| updatedAt | timestamp | [S] | |
| earningsTotal | number | [R] | Lifetime; server-only writes |
| earningsPendingPayout | number | [R] | Awaiting settlement |
| suspensionReason | string | [A] | Admin-only |
| suspendedUntil | timestamp | [A] | |

**Indexes:**
- `driverStatus` + `homeCity` (matching query)
- `activeRideId` (check availability)

---

## Collection: `vehicles`

Document ID: auto-generated

| Field | Type | Access | Notes |
|---|---|---|---|
| vehicleId | string | [R] | Immutable |
| driverId | string | [R] | Owner |
| make | string | [C] | "Toyota" |
| model | string | [C] | "Corolla" |
| year | number | [C] | |
| color | string | [C] | |
| licensePlate | string | [C] | Uppercase |
| registrationCity | string | [C] | |
| fuelType | string | [C] | "petrol" \| "diesel" \| "cng" \| "electric" |
| seatingCapacity | number | [C] | |
| vehicleStatus | string | [S] | "pending" \| "approved" \| "rejected" |
| approvedCategories | string[] | [S] | ["easy", "breeze"] |
| vehiclePhotoUrl | string | [R] | GCS URL |
| approvedAt | timestamp | [S] | |
| approvedBy | string | [A] | |
| createdAt | timestamp | [S] | Immutable |

---

## Collection: `driverDocuments`

Document ID: `{driverId}` (one doc per driver; fields per document type)

| Field | Type | Access | Notes |
|---|---|---|---|
| driverId | string | [R] | Immutable |
| drivingLicence | DocumentRecord | [S] | See below |
| vehicleRegistration | DocumentRecord | [S] | |
| cnicCopy | DocumentRecord | [S] | |
| vehiclePhoto | DocumentRecord | [S] | |
| insuranceCertificate | DocumentRecord | [S] | Optional |
| fitnessCertificate | DocumentRecord | [S] | Optional |
| updatedAt | timestamp | [S] | |

**DocumentRecord type:**
```json
{
  "status": "missing" | "uploaded" | "approved" | "rejected",
  "gcsUrl": "gs://ora-documents/...",
  "uploadedAt": "timestamp",
  "reviewedAt": "timestamp | null",
  "reviewedBy": "adminUid | null",
  "rejectionReason": "string | null",
  "expiresAt": "date | null"
}
```

---

## Collection: `rides`

Document ID: auto-generated UUID

| Field | Type | Access | Notes |
|---|---|---|---|
| rideId | string | [R] | Immutable |
| passengerId | string | [R] | Immutable |
| assignedDriverId | string | [R] | Set on assignment; null before |
| state | string | [R] | Current state (see state machine) |
| version | number | [R] | Monotonic; increments on every transition |
| stateSummary | StateEvent[] | [R] | Short bounded transition summary only; full audit lives in `rideEvents` |
| category | string | [R] | "zip" \| "trio" \| "easy" etc. |
| pickup | GeoPoint | [R] | Immutable |
| pickupAddress | string | [R] | Human-readable |
| destination | GeoPoint | [R] | Immutable |
| destinationAddress | string | [R] | |
| routePolyline | string | [R] | Encoded polyline (Google) |
| distanceKm | number | [R] | From pricing service |
| estimatedDurationMin | number | [R] | From pricing service |
| pricingSnapshotId | string | [R] | Reference to pricingSnapshots |
| recommendedFareMinor | number | [R] | Server guidance snapshotted at create |
| passengerOfferMinor | number | [R] | Passenger offer; immutable for `requestVersion` |
| requestVersion | number | [R] | Increments if passenger republishes the request |
| agreedFareMinor | number | [S] | Copied from selected offer; **immutable after assignment**; client cannot write |
| agreedOfferId | string | [S] | Selected `rideOffers` id |
| feePolicySnapshot | map | [S] | FeePolicy snapshot at assignment/payment |
| paymentMethod | string | [R] | `CASH` \| `WALLET` \| `ONLINE_PAYMENT` (+ provider) |
| paymentIntentId | string | [S] | Reference to `paymentIntents/{id}` if payment required |
| serviceType | string | [R] | "ride" \| "courier" \| "intercity" \| "move" |
| passengerRating | number | [S] | Rating given to driver |
| driverRating | number | [S] | Rating given to passenger |
| cancellationReason | string | [S] | If cancelled |
| cancelledBy | string | [S] | "passenger" \| "driver" \| "server" |
| cancellationFeeMinor | number | [S] | From cancellation policy; may be 0 |
| assignedAt | timestamp | [S] | |
| startedAt | timestamp | [S] | |
| completedAt | timestamp | [S] | |
| closedAt | timestamp | [S] | |
| createdAt | timestamp | [S] | Immutable |
| updatedAt | timestamp | [S] | |
| expiresAt | timestamp | [S] | Server-set TTL for SEARCHING state |

**Indexes:**
- `passengerId` + `createdAt` DESC (My Rides query)
- `assignedDriverId` + `state` (driver's active ride)
- `state` + `expiresAt` (expiry sweeper)

---

## Collection: `rideEvents`

Document ID: auto-generated

Append-only audit trail. Server writes only.

| Field | Type | Notes |
|---|---|---|
| eventId | string | Immutable |
| rideId | string | Reference |
| eventType | string | e.g., "STATE_TRANSITION", "OFFER_RECEIVED", "GPS_STALE" |
| fromState | string | |
| toState | string | |
| actorId | string | uid or "server" |
| actorRole | string | "passenger" \| "driver" \| "server" \| "admin" |
| metadata | map | Event-specific data |
| requestId | string | Correlation ID |
| timestamp | timestamp | Server timestamp |
| aggregateVersion | number | Ride aggregate version at time of event |

---

## Collection: `rideOffers`

Document ID: auto-generated `offerId`  
Server writes only. Clients read own-ride offers (passenger) or own offers (driver).

| Field | Type | Access | Notes |
|---|---|---|---|
| offerId | string | [R] | Immutable |
| rideId | string | [R] | |
| driverId | string | [R] | |
| amountMinor | number | [R] | Offer amount in paisas |
| currency | string | [R] | `PKR` |
| type | string | [R] | `PASSENGER_PRICE_ACCEPTED` \| `DRIVER_COUNTEROFFER` |
| status | string | [R] | `PENDING` \| `ACCEPTED` \| `REJECTED` \| `EXPIRED` \| `WITHDRAWN` \| `SELECTED` \| `SUPERSEDED` |
| requestVersion | number | [R] | Must match ride.requestVersion to be selectable |
| expiresAt | timestamp | [R] | Expired offers cannot assign |
| createdAt | timestamp | [S] | |
| driverSnapshot | map | [R] | rating, completedRides, vehicle, ETA at offer time |
| metadata | map | [S] | Optional message, waveId |
| selectedAt | timestamp | [S] | Set when SELECTED |

Canonical selectable status is `PENDING`. Type `PASSENGER_PRICE_ACCEPTED` means the driver accepted the passenger price, **not** that the ride is assigned.

**Indexes:**
- `rideId` + `status`
- `rideId` + `driverId` + `requestVersion`
- `expiresAt` (offer expiry sweeper)

---

## Collection: `feePolicies`

Document ID: auto-generated or `{city}_{category}_{paymentMethod}_{version}`  
Admin-managed. Not a hardcoded 10%/12% commission.

| Field | Type | Notes |
|---|---|---|
| feePolicyId | string | |
| platformFeeType | string | `PERCENT` \| `FLAT` \| `PERCENT_PLUS_FLAT` \| `NONE` |
| platformFeeValue | map | `{ bps, flatMinor }` |
| effectiveFrom | timestamp | |
| effectiveTo | timestamp? | |
| city | string | |
| category | string | |
| paymentMethod | string | `CASH` \| `WALLET` \| `ONLINE_PAYMENT` or provider-specific |
| currency | string | |
| version | string | |

Snapshot copied onto the ride / payment intent at assignment. Historical rides never re-read live policy.

---

## Collection: `pricingSnapshots`

Document ID: auto-generated

Immutable after creation. Server writes only.

| Field | Type | Notes |
|---|---|---|
| snapshotId | string | |
| rideId | string | |
| pricingRulesVersion | string | Version of rules used |
| inputs | map | All fare inputs (distance, duration, category, zone, demand, etc.) |
| recommendedFareMinor | number | Guidance only |
| offerBoundMinMinor | number | From OfferBoundPolicy at estimate time |
| offerBoundMaxMinor | number | |
| currency | string | "PKR" |
| computedAt | timestamp | |
| expiresAt | timestamp | 10 min TTL for unsubmitted estimates |

---

## Collection: `paymentIntents`

Document ID: auto-generated

| Field | Type | Notes |
|---|---|---|
| paymentIntentId | string | |
| rideId | string? | |
| ownerUserId | string | |
| paymentMethod | string | `CASH` \| `WALLET` \| `ONLINE_PAYMENT` (provider in attempt) |
| amountMinor | number | From agreedFare (+ extras); integer paisas |
| currency | string | PKR |
| state | string | NOT_REQUIRED \| PENDING \| AUTHORIZED \| CAPTURE_PENDING \| CAPTURED \| FAILED \| REFUND_PENDING \| REFUNDED \| RECONCILIATION_REQUIRED |
| feePolicySnapshotId | string | Immutable fee snapshot |
| agreedFareMinor | number | Copied from ride; not client-writable |
| latestAttemptId | string? | |
| createdAt | timestamp | |
| updatedAt | timestamp | |

---

## Collection: `paymentAttempts`

Document ID: auto-generated

| Field | Type | Notes |
|---|---|---|
| paymentAttemptId | string | |
| paymentIntentId | string | |
| provider | string | cash \| wallet \| jazzcash \| easypaisa |
| providerReferenceId | string? | |
| amountMinor | number | integer paisas |
| state | string | PENDING \| SENT \| AUTHORIZED \| CAPTURED \| FAILED \| TIMED_OUT |
| idempotencyKey | string | |
| createdAt | timestamp | |
| updatedAt | timestamp | |

---

## Collection: `paymentProviderCallbacks`

Document ID: `{provider}_{providerEventId}`

| Field | Type | Notes |
|---|---|---|
| callbackId | string | dedupe key |
| provider | string | |
| providerEventId | string | |
| paymentAttemptId | string? | |
| payload | map | raw callback summary |
| processed | boolean | |
| processedAt | timestamp? | |
| createdAt | timestamp | |

---

## Collection: `walletAccounts`

Document ID: `{uid}`

Server writes only. Never client-writable.

| Field | Type | Notes |
|---|---|---|
| userId | string | |
| balanceMinor | number | integer paisas; derived projection only |
| currency | string | "PKR" |
| updatedAt | timestamp | |

---

## Collection: `walletLedgerEntries`

Document ID: auto-generated. Append-only.

| Field | Type | Notes |
|---|---|---|
| ledgerEntryId | string | |
| accountId | string | |
| userId | string | |
| type | string | "DEBIT" \| "CREDIT" \| "HOLD" \| "RELEASE" \| "REFUND" \| "ADJUSTMENT" \| "PAYOUT" |
| amountMinor | number | integer paisas |
| rideId | string? | If ride-related |
| description | string | |
| paymentIntentId | string? | |
| paymentAttemptId | string? | |
| paymentMethod | string | |
| status | string | "POSTED" \| "VOIDED" |
| idempotencyKey | string | |
| createdAt | timestamp | |
| pspReferenceId | string? | External payment reference |

---

## Collection: `driverPayouts`

Document ID: auto-generated

| Field | Type | Notes |
|---|---|---|
| payoutId | string | |
| driverId | string | |
| amountMinor | number | integer paisas |
| state | string | PENDING \| PROCESSING \| COMPLETED \| FAILED \| RECONCILIATION_REQUIRED |
| provider | string | jazzcash \| easypaisa \| bank |
| providerReferenceId | string? | |
| createdAt | timestamp | |
| updatedAt | timestamp | |

---

## Collection: `refunds`

Document ID: auto-generated

| Field | Type | Notes |
|---|---|---|
| refundId | string | |
| paymentIntentId | string | |
| amountMinor | number | integer paisas |
| state | string | PENDING \| COMPLETED \| FAILED |
| reason | string | |
| createdAt | timestamp | |
| updatedAt | timestamp | |

---

## Collection: `reconciliationRecords`

Document ID: auto-generated

| Field | Type | Notes |
|---|---|---|
| reconciliationId | string | |
| referenceType | string | paymentIntent \| paymentAttempt \| payout |
| referenceId | string | |
| state | string | OPEN \| MATCHED \| MISMATCH \| RESOLVED |
| notes | string? | |
| createdAt | timestamp | |
| updatedAt | timestamp | |

---

## Collection: `ratings`

Document ID: `{rideId}_{ratingType}` (e.g., `ride_abc_passenger`)

| Field | Type | Notes |
|---|---|---|
| rideId | string | |
| raterId | string | Who gave the rating |
| ratedId | string | Who was rated |
| role | string | "passenger_rates_driver" \| "driver_rates_passenger" |
| stars | number | 1–5 |
| tags | string[] | ["polite", "clean_car", "on_time"] |
| comment | string? | Optional text |
| timestamp | timestamp | |

---

## Collection: `savedPlaces`

Document ID: auto-generated (one per place)

Parent: `users/{uid}/savedPlaces/{placeId}`

| Field | Type | Notes |
|---|---|---|
| placeId | string | |
| label | string | "Home" \| "Work" \| "Mom's house" \| custom |
| icon | string | "house" \| "briefcase" \| "heart" \| "star" |
| address | string | Human-readable |
| coordinates | GeoPoint | |
| createdAt | timestamp | |

---

## Collection: `pricingRules`

Document ID: `{city}_{category}` e.g., `lahore_easy`

Admin-managed. Client reads (cached).

| Field | Type | Notes |
|---|---|---|
| city | string | |
| category | string | |
| baseFare | number | |
| ratePerKm | number | |
| ratePerMin | number | |
| categoryMultiplier | number | |
| minFare | number | |
| maxFare | number | |
| nightAdjustment | number | Applied 11 PM – 5 AM |
| demandMultiplierMin | number | 1.0 |
| demandMultiplierMax | number | 1.8 |
| offerMinRatio | number | Configurable OfferBoundPolicy; example 0.70 — **not** the pricing model |
| offerMaxRatio | number | Configurable OfferBoundPolicy; example 2.50 — **not** the pricing model |
| airportFee | number | Recommendation input |
| version | string | e.g., "2026-08-18:v1" |
| updatedAt | timestamp | |
| updatedBy | string | Admin UID |

---

## Collection: `serviceAreas`

Document ID: `{city}` e.g., `lahore`

| Field | Type | Notes |
|---|---|---|
| city | string | |
| displayName | string | "Lahore" |
| polygon | GeoPoint[] | City boundary |
| active | boolean | |
| zones | Zone[] | Sub-zones for demand calculation |
| launchDate | date | |

---

## Collection: `safetyEvents`

Document ID: auto-generated

| Field | Type | Notes |
|---|---|---|
| eventId | string | |
| type | string | "SOS" \| "ROUTE_DEVIATION" \| "DRIVER_MISMATCH" \| "REPORT" |
| severity | string | "LOW" \| "MEDIUM" \| "HIGH" \| "CRITICAL" |
| rideId | string | |
| passengerId | string | |
| driverId | string? | |
| location | GeoPoint | At time of event |
| description | string? | |
| resolved | boolean | |
| resolvedAt | timestamp? | |
| resolvedBy | string? | Admin UID |
| timestamp | timestamp | |

---

## Collection: `hotZones`

Document ID: auto-generated

| Field | Type | Notes |
|---|---|---|
| zoneId | string | |
| city | string | |
| displayName | string | "Airport Zone", "Gulberg" |
| polygon | GeoPoint[] | |
| demandLevel | string | "normal" \| "busy" \| "very_busy" |
| activeBonusId | string? | Reference to bonus |
| updatedAt | timestamp | |

---

## Collection: `referrals`

Document ID: `{referralCode}`

| Field | Type | Notes |
|---|---|---|
| code | string | |
| ownerId | string | UID of referrer |
| usedBy | string[] | UIDs who used this code |
| totalEarned | number | PKR credited to owner |
| maxUses | number | Default unlimited |
| expiresAt | timestamp? | |
| createdAt | timestamp | |
