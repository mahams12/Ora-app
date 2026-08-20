# ORA — Security Model Summary

See also: `ORA_SECURITY_MODEL.md` (root), `authorization-matrix.md`, `threat-model.md`

## Core Rules

1. **No client owns ride state.** All transitions via Cloud Run server.
2. **No client calculates or writes agreedFare / platformFee / driverNet / ledger.** Recommended fare is server guidance only.
3. **No client writes financial data.** Wallet, transactions, earnings: server Admin SDK only.
4. **App Check on every API call.** No request without attested app binary.
5. **JWT on every API call.** No anonymous access to business endpoints.
6. **Default DENY in Firestore.** Every client read/write explicitly allowed.
7. **No secrets in Flutter.** API keys restricted; no server-privileged keys in app.
8. **Audit log on every state change.** `rideEvents` collection; immutable.

## Layers

```
Layer 1: App Check         — Is this a real Ora app on a real device?
Layer 2: Firebase Auth     — Is this a real authenticated user?
Layer 3: Cloud Armor       — Is this within rate limits? Any WAF triggers?
Layer 4: Cloud Run auth    — Does this user have permission for this operation?
Layer 5: Firestore Rules   — Does this read/write conform to ownership rules?
Layer 6: Business Logic    — Valid transition? Offer selectable? OfferBoundPolicy?
Layer 7: Assignment txn    — Passenger select Firestore transaction (Accept is not assignment)
```

A breach of any one layer is caught by the next.

## Key Security Properties

| Property | Mechanism | Verification |
|---|---|---|
| Exactly-one assignment | Passenger select Firestore transaction (+ optional Redis contention lock) | Concurrent-select race × 100 |
| Agreed fare immutability | Copied from selected offer; server-only write | Integration test |
| Recommended fare vs offer | pricingSnapshot is guidance; passengerOffer is request price | Integration test |
| Location privacy | RTDB cleared post-trip; no permanent GPS storage | Code review |
| Financial integrity | Immutable ledger; payment intents/attempts/callbacks; server writes only | Integration test |
| Auth token safety | 1-hour TTL; secure storage; App Check | Unit test |
| No privilege escalation | Custom claims set server-only | Firestore rules test |
| Rate abuse prevention | Cloud Armor + Redis rate counters | Load test |
