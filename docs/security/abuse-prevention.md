# ORA — Abuse Prevention

## Ride Creation Abuse

```
Limit: 20 ride creates per user per hour
Limit: 5 active (non-terminal) rides per user
Mechanism: Redis rate counter + Firestore active ride count check
Response: 429 RIDE_CREATION_LIMIT
```

## Account Creation Spam

```
Limit: 3 accounts per phone number (OTP verification required)
Limit: 1 account per device (App Check device fingerprint)
Mechanism: Firebase Auth enforces phone uniqueness
           App Check DeviceCheck/Play Integrity limits per device
Response: Firebase Auth error → account creation fails
```

## Referral Abuse

```
Limit: 1 referral credit per verified phone number
Limit: Self-referral impossible (server checks referrerId != newUserId)
Mechanism: Referral redemption server-side; phone OTP required
Response: Silent failure (no credit) + log
```

## GPS Spoofing Detection

```
Speed check: if distance_from_last_point / time_elapsed > 200 km/h → flag
Accuracy check: if horizontal_accuracy > 50m → reject
Mock GPS: App Check Play Integrity detects on most devices
Pattern analysis (Phase 14): driver never moves in straight lines
Response: Rejected location update + safetyEvent log on repeated violation
```

## Duplicate Offer Spam (Driver)

```
Limit: 1 offer per driver per ride
Mechanism: Redis SETNX offer:dedup:{rideId}:{driverId} NX EX 300
Response: 409 DUPLICATE_OFFER
```

## API Scraping

```
Rate limit: 60 requests per minute per IP (Cloud Armor)
Rate limit: 10 pricing estimates per minute per user
Response: 429 RATE_LIMITED + Retry-After header
```

## Payment Fraud

```
Card fraud: PSP handles (3DS, fraud scoring)
Chargeback abuse: account flagged after 2 chargebacks; reviewed by admin
Wallet abuse: withdrawals > Rs 5,000 require OTP re-verification
```
