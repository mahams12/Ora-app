# ORA — Consistency Model

## 1. Authoritative Sources

| Category | Authoritative Store | Projection / Cache | Recovery Path |
|---|---|---|---|
| Identity | Firebase Auth | Client secure storage token cache | Refresh token / re-auth |
| User profile | Firestore | Hive/local cache | Re-read Firestore |
| Driver approval | Firestore + Auth custom claims | Client auth state | Re-read `/auth/me` |
| Driver availability | RTDB `driverPresence` | Redis `driver:online:*`, Firestore mirror | Reattach RTDB, refresh from presence |
| Driver location | RTDB live projection + Redis GEO | Client map state | Reattach RTDB; request latest server-known location |
| Ride aggregate | Firestore `rides` | RTDB signal, client in-memory state | Re-read ride document |
| Ride assignment | Firestore transaction | RTDB signal / FCM | Re-read ride document |
| Fare recommendation | Pricing service → `pricingSnapshots` | Client estimate UI | Re-request estimate |
| Passenger offer | Firestore `rides.passengerOfferMinor` | Offer inbox | Re-read ride |
| Driver offer | Firestore `rideOffers` | Passenger offer list | Re-query offers |
| Agreed fare | Firestore `rides.agreedFareMinor` | Receipts | Re-read ride; immutable after assignment |
| Ride assignment | Firestore select transaction | RTDB signal / FCM | Re-read ride document |
| Payment intent / attempt / callback | `paymentIntents`, `paymentAttempts`, `paymentProviderCallbacks` | Ride summary | Re-read payment aggregate |
| Wallet balance cache | Firestore `walletAccounts` | Client cache | Recompute from ledger if mismatch |
| Driver earnings | Ledger | Driver dashboard | Rebuild from ledger |
| Fee policy | `feePolicies` live; snapshot on ride | Receipts | Historical snapshot never rewritten |
| Safety incident | Firestore `safetyEvents` | Support UI cache | Re-read Firestore |
| Dispatch candidate set | Redis | None | Recompute from availability + geo index |
| Realtime invalidation | RTDB | FCM copy | Re-read Firestore |
| Durable event | Outbox | Pub/Sub delivery copies | Replay unpublished outbox records |

## 2. Consistency Guarantees

### Firestore
- Strong enough for authoritative ride aggregate updates via transaction.
- Used for durable business truth only.

### RTDB
- Eventually consistent signal/projection layer.
- Must never be the only place where correctness depends on message delivery.

### Redis
- Best-effort ephemeral coordination and spatial index.
- Correctness must survive total Redis loss.

### Pub/Sub
- At-least-once asynchronous delivery.
- Consumer idempotency is mandatory.

### FCM
- Best-effort notification only.
- Never correctness-critical.

## 3. Required Read-Repair Paths

### Passenger reconnect
1. Re-read active ride from Firestore.
2. If ride is active, attach RTDB listeners for live location and signals.
3. Ignore any RTDB signal with aggregate version lower than current Firestore version.

### Driver reconnect
1. Re-register presence in RTDB.
2. Re-sync active assignment from Firestore.
3. If a pending request card is present locally, validate against Firestore before creating an offer. Offer is not assignment.

### Suspected inconsistency
If any of the following happen:
- impossible state transition in UI
- request card remains after assignment
- ride signal version gap
- app restart during active ride

Then client must:
1. suspend local optimistic UI assumptions
2. fetch authoritative Firestore ride
3. rebuild view from that snapshot

## 4. Partial-Failure Matrix

| Durable Change | Side Effect Fails | Required Behavior |
|---|---|---|
| Firestore ride assignment | RTDB cleanup fails | Outbox retry; clients can still recover via Firestore |
| Firestore ride assignment | Pub/Sub publish fails | Outbox retry publishes later |
| Firestore ride assignment | FCM fails | No correctness loss; foreground listeners still recover |
| Firestore cancellation | RTDB delete pending requests fails | Outbox retry; accept path still rejects by Firestore state |
| Payment capture recorded | Wallet projection update fails | Replay ledger-to-wallet projection |
| Wallet cache updated | notification fails | No correctness loss |

## 5. Correctness Rule

Whenever durable state and realtime projection disagree, **durable Firestore or durable financial records win**.
