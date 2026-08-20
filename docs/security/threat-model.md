# ORA — Threat Model

## Threat Actors

| Actor | Motivation | Capability |
|---|---|---|
| Malicious passenger | Free rides; fare manipulation | Modified app; API access |
| Malicious driver | Earn without working; fake GPS | Modified app; GPS spoofing tools |
| Competitor | Disrupt service; scrape data | Automated API calls |
| External attacker | Financial theft; data breach | API access; network interception |
| Insider threat | Data theft; financial fraud | Admin access; database access |
| Automated bot | Account creation spam; referral abuse | Scripted API calls |

## Threat Scenarios

### T1: Client Claims Ride Already Assigned to Them

**Attack:** Modified Flutter app sends `state = DRIVER_ASSIGNED` to Firestore directly.

**Mitigation:**
- Firestore rules: `rides` collection — no client writes
- Only Cloud Run Admin SDK can write ride state
- App Check + JWT required to reach Cloud Run
- Firestore rules: `.write: false` for rides collection

**Residual risk:** NONE (defense-in-depth)

---

### T2: Driver Spoofs GPS to Be Near Pickup

**Attack:** Driver uses GPS spoofing app to appear at pickup without physically being there.

**Mitigation:**
- App Check: Play Integrity / DeviceCheck detects mock GPS on most devices
- Server validates speed plausibility (can't teleport at 500 km/h)
- Server requires driver within 100m (geofence) before ARRIVED transition
- Historical location pattern analysis (Phase 14+)
- Passenger photos driver on arrival (verify feature)

**Residual risk:** LOW (partial; GPS spoofing still possible on rooted devices not caught by App Check)

---

### T3: Duplicate Ride Acceptance (Race Condition)

**Attack:** Two drivers simultaneously tap Accept; both get assigned.

**Mitigation:**
- Firestore transaction: asserts `assignedDriverId == null`, valid state, and expected version before write
- Redis SETNX lock: optional contention reduction only
- Version number assertion: prevents stale overwrites
- Result: deterministically exactly one authoritative assignment can commit

**Residual risk:** LOW (correctness is strong if transaction predicates are implemented exactly; Redis outage increases contention, not correctness risk)

---

### T4: Fare Manipulation

**Attack:** Passenger submits ride with `passengerOfferMinor: 1` (unreasonably low).

**Mitigation:**
- Server validates passenger offer (and driver counteroffers) against configurable `OfferBoundPolicy` derived from the recommended-fare snapshot
- Bounds are anti-abuse policy, not the pricing model
- `pricingSnapshot` computed server-side; client cannot fake it
- `pricingSnapshotId` must be < 10 minutes old
- Client cannot write `agreedFareMinor`

**Residual risk:** NONE

---

### T5: Wallet Balance Inflation

**Attack:** Client sends `walletAccounts/{uid}.balanceMinor = 999999999`.

**Mitigation:**
- Firestore rules: `walletAccounts` collection — no client writes
- All balance changes via server-only ledger transactions
- Ledger is append-only; balance recomputable from transactions

**Residual risk:** NONE

---

### T6: Token Theft / JWT Replay

**Attack:** Attacker intercepts JWT and makes API calls on victim's behalf.

**Mitigation:**
- JWT TTL: 1 hour
- App Check: attacker's device/app won't pass App Check
- Rate limiting: unusual activity flagged
- Sensitive operations require OTP re-verification

**Residual risk:** LOW (short-lived tokens + App Check makes this very difficult)

---

### T7: Driver Creates Fake Completed Trip

**Attack:** Driver and accomplice passenger create a fake completed trip to earn payout without driving.

**Mitigation:**
- Route validation: GPS trajectory vs expected route
- Distance validation: actual GPS distance ≥ 80% of route distance
- Speed validation: average speed consistent with trip
- Destination geofence required for RIDE_COMPLETED
- Trip duration floor: minimum time for the distance

**Residual risk:** MEDIUM (collusion is hard to detect without ML; Phase 14 anomaly detection)

---

### T8: API Key Leakage from Flutter App

**Attack:** Attacker decompiles APK; extracts Google Maps API key; uses for free Maps billing.

**Mitigation:**
- Maps SDK key restricted to `com.ora.app` package ID + SHA fingerprints + Maps SDK only
- Even if extracted, cannot be used from other apps
- Geocoding / Routes keys not in client (server-side only)
- Monitor key usage in Google Cloud Console; alert on anomaly

**Residual risk:** LOW

---

### T9: Referral Abuse (Self-Referral)

**Attack:** User creates 100 fake accounts using their own referral code.

**Mitigation:**
- Phone number verification required for each account (OTP)
- One referral credit per new phone number
- Same device fingerprint check (App Check device ID)
- IP-based rate limiting on account creation

**Residual risk:** LOW (phone numbers are scarce; cost > reward)

---

### T10: API Scraping / Enumeration

**Attack:** Competitor scrapes driver locations, pricing data, service areas.

**Mitigation:**
- Rate limiting: 60 req/min per IP; 20 req/hour per user for sensitive endpoints
- Cloud Armor WAF: detect scanning patterns
- Driver location: only visible during active trip with matching rideId
- Pricing rules: auth required

**Residual risk:** LOW-MEDIUM (public APIs are always somewhat scrapeable)

## Data Breach Impact Analysis

| Data | Sensitivity | Mitigation |
|---|---|---|
| User phone numbers | HIGH | Stored in Firebase Auth; not in Firestore directly |
| CNIC numbers | VERY HIGH | Server-side only; masked in reads |
| Location history | HIGH | Not stored post-trip; 7-day audit log server-only |
| Payment card info | VERY HIGH | Never stored by Ora (PSP-tokenized) |
| Driver documents | HIGH | GCS with signed URLs; access logged |
| Wallet balances | MEDIUM | Firestore; client reads own; server writes |
| Ride history | MEDIUM | Firestore; client reads own; paginated |
| Emergency contacts | HIGH | Encrypted subcollection; server access only |
