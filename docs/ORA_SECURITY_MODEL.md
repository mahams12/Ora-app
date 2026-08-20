# ORA — Security Model

**Version:** 0.1.0-architecture  
**Date:** 2026-08-18

---

## 1. Security Layers

```
Device
  └── App Check (DeviceCheck / Play Integrity)
        └── Firebase Auth (JWT token)
              └── Cloud Run API (server-side JWT validation)
                    └── Firestore (Security Rules)
                          └── Firestore (server-side Admin SDK)
```

Every request must pass ALL layers.

---

## 2. Operation Classification

### CLIENT SAFE (client may read/write with own auth)
- Read own user profile (users/{uid})
- Read own ride documents (rides/{rideId} where passengerId == uid)
- Read own wallet balance projection (`walletAccounts/{uid}`)
- Read own saved places
- Read own ride history
- Write own GPS location to RTDB (driverPresence/{uid})
- Write own profile fields (displayName, profilePhotoUrl)
- Read public service area and pricing rules (read-only collections)

### SERVER ONLY (must go through Cloud Run API, JWT validated)
- Create ride request
- Transition ride state (any state change)
- Atomically assign driver via Firestore conditional transaction
- Calculate and snapshot fare
- Process payment
- Create payment intents/attempts
- Credit/debit wallet ledger
- Issue refund
- Create durable idempotency records
- Sign document upload URLs
- Validate driver approval
- Validate vehicle approval
- Write to rideEvents (audit trail)
- Publish Pub/Sub events

### ADMIN ONLY (Firebase Admin SDK; Cloud Run with admin role)
- Force ride state transition
- Suspend/unsuspend driver account
- Approve/reject driver documents
- Override payment
- Read any user's data
- Read safety event logs
- Configure pricing rules
- Configure service areas
- Configure hot zones
- View all audit logs

---

## 3. Firebase Auth

- Phone OTP: Primary method (Pakistan market)
- Google Sign-In: Secondary
- Apple Sign-In: Required (iOS App Store policy)
- Token expiry: 1 hour access token; 30-day refresh
- Token validation: Every Cloud Run endpoint calls `admin.auth().verifyIdToken()`
- Custom claims: `{ role: "driver" | "passenger" | "admin", driverStatus: "approved" | "pending" | "suspended" }`
- Custom claims set server-side ONLY
- Client MUST NOT trust its own role claim without server confirmation

---

## 4. App Check

- iOS: DeviceCheck + App Attest
- Android: Play Integrity API
- Enforcement: Cloud Run validates `X-Firebase-AppCheck` header on all endpoints
- Fallback: Debug provider for development only; NEVER in production build
- Failure: 403 Forbidden; logged; rate-counted

---

## 5. Firestore Security Rules (Design — not yet implemented)

```
// Core principles:
// 1. Default DENY everything
// 2. Allow only what is explicitly needed
// 3. Server writes use Admin SDK (bypasses rules) — rules protect client writes

rules_version = '2';
service cloud.firestore {
  match /databases/{db}/documents {
    
    // DENY ALL by default
    match /{document=**} { allow read, write: if false; }
    
    // Users: read own, write own non-sensitive fields
    match /users/{uid} {
      allow read: if request.auth.uid == uid;
      allow write: if request.auth.uid == uid
        && !request.resource.data.keys().hasAny(['role','banned','adminNotes','createdAt']);
    }
    
    // Rides: passenger reads own; driver reads assigned
    match /rides/{rideId} {
      allow read: if request.auth.uid == resource.data.passengerId
        || request.auth.uid == resource.data.assignedDriverId;
      allow write: if false; // Server only
    }
    
    // Driver presence: driver writes own
    // (RTDB, not Firestore — separate rules)
    
    // Pricing rules: public read
    match /pricingRules/{doc} {
      allow read: if request.auth != null;
      allow write: if false;
    }
    
    // Wallet accounts: read own only
    match /walletAccounts/{uid} {
      allow read: if request.auth.uid == uid;
      allow write: if false;
    }
  }
}
```

---

## 6. Realtime Database Security Rules (Design)

```json
{
  "rules": {
    "driverPresence": {
      "$driverId": {
        ".read": "auth != null && auth.uid === $driverId",
        ".write": "auth != null && auth.uid === $driverId"
      }
    },
    "tripLocations": {
      "$rideId": {
        ".read": "auth != null && root.child('rideAccess').child($rideId).child(auth.uid).val() === true",
        ".write": "false"
      }
    },
    "rideSignals": {
      "$rideId": {
        ".read": "auth != null && root.child('rideAccess').child($rideId).child(auth.uid).val() === true",
        ".write": "false"
      }
    },
    "rideRequests": {
      "$driverId": {
        ".read": "auth != null && auth.uid === $driverId",
        ".write": "false"
      }
    }
  }
}
```

RTDB location for active trips is written by server (Admin SDK) only.

---

## 7. API Security

- All Cloud Run endpoints require `Authorization: Bearer {firebase_id_token}`
- All Cloud Run endpoints require `X-Firebase-AppCheck: {token}`
- Rate limiting: Cloud Armor — 60 req/min per IP; 20 ride-create/hour per user
- Idempotency keys required on: POST /rides, POST /rides/{id}/offers, POST /rides/{id}/offers/{offerId}/select, POST /payments
- Durable idempotency records required on all business-critical and financial mutations
- Request signing: HMAC-SHA256 on payment webhooks
- No API key in Flutter source code or assets
- All secrets in Secret Manager; mounted as env vars in Cloud Run

---

## 8. Threat Model

| Threat | Mitigation |
|---|---|
| Client fakes assignment | Drivers cannot select; Firestore select transaction; JWT |
| Client manipulates fare | Fare calculated server-side; pricingSnapshot immutable |
| Driver clones GPS location | Server validates location accuracy, speed plausibility, geofence; App Check is not treated as location proof |
| Passenger spoofs location | Same validation; anomaly detection |
| Replay attack on offer/select | Durable idempotency record + request hash + version number |
| Duplicate payment | Idempotency key on all payment calls |
| Stolen JWT token | Short TTL (1 hour); App Check on every request |
| Jailbroken/rooted device | App Check DeviceCheck/Play Integrity rejects |
| MITM | Certificate pinning (evaluate per platform) + HTTPS only |
| Account takeover | OTP re-verification for sensitive operations |
| Rate abuse (ride spam) | Rate limiter on POST /rides |
| Document forgery | Admin manually reviews; server stores hash of document |
| Driver impersonation | Licence plate verified at onboarding; photo match |

---

## 9. Financial Integrity

- Wallet balance stored server-side as a derived projection
- All credits/debits are immutable ledger transactions (append-only)
- Payment intents, attempts, callbacks, refunds, payouts, and reconciliation records are durable server-owned entities
- Client never sends wallet balance — only requests
- Payment confirmation arrives via server webhook; never client-reported
- Refunds processed server-side with audit trail
- No negative wallet balance without explicit overdraft policy

---

## 10. Location Privacy

- Passenger location is NEVER blindly trusted and is not retained as durable operational truth after ride completion
- Driver location in RTDB is auto-deleted after ride ends (server cleanup)
- Location history retained for 7 days in audit logs (server-only access)
- Passenger can request location data deletion (GDPR-style)
- Driver location masked to ~500m precision for non-active-trip passengers

---

## 11. Audit Log Requirements

Every server operation writes to `rideEvents` / `auditLogs`:
- `eventId`
- `rideId` / `userId`
- `operationType`
- `actorId`
- `actorRole`
- `timestamp`
- `ipAddress` (hashed)
- `requestId`
- `before` / `after` state snapshot
