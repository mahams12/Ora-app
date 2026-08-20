# ORA — System Invariants

## Global Invariants

1. A ride has at most one authoritative assigned driver.
2. A terminal ride cannot transition again except through audited admin correction tooling.
3. The authoritative ride state is stored in Firestore, not in RTDB, Redis, or client memory.
4. RTDB is a projection/signal layer only; missed RTDB signals must be recoverable from Firestore.
5. Redis is never the authoritative source of ride state, payment state, or assignment truth.
6. Recommended fare is guidance; it is not the trip price.
7. `passengerOffer`, driver offers, and `agreedFare` are distinct fields.
8. `agreedFare` is immutable after assignment; no client may write it.
9. Dispatch is not assignment. Driver Accept creates a pending offer; passenger select assigns.
10. An expired, stale, withdrawn, rejected, or superseded offer must never become an assignment.
11. A passenger can create/select offers only for their own ride. A driver cannot select themselves.
12. A driver can create offers only for requests they are legitimately eligible to receive.
13. A fare / pricing snapshot cannot mutate after ride creation.
14. Platform fee and driver net come from a snapshotted `FeePolicy`, not a hardcoded commission.
15. Older ride-state observations cannot overwrite newer ride state.
16. Older accepted GPS packets cannot overwrite newer accepted GPS packets for the same ride-stream.
17. A user cannot access another user's protected ride, wallet, or safety data without explicit authorization.
18. Wallet balance is a cache; the immutable ledger is the financial source of truth.
19. A payment capture cannot be applied twice to the ledger.
20. Cash collection is auditable even though cash does not pass through Ora's PSP.
21. Client-side “payment successful” claims are never trusted.
22. Every critical mutation must be idempotent.
23. Every authoritative state transition must be auditable.
24. Every durable business event must have a stable event ID and aggregate version.
25. If downstream realtime/push delivery fails, authoritative recovery must still be possible.
26. Client-provided location is untrusted input.
27. Kalman smoothing may improve UX but cannot be used as a fraud-prevention guarantee.
28. No client can mark a payment as captured, a wallet as credited, or rewrite ledger entries.
29. Ride and payment state machines must not be merged.
30. Flutter Views contain no business logic and must not access repositories or data sources.

## Source-Of-Truth Invariants By Data Category

| Data Category | Authoritative Store | Write Authority | Projection | Consistency |
|---|---|---|---|---|
| Identity | Firebase Auth | Auth service | Client token cache | Strong |
| User profile | Firestore `users` | Client (non-sensitive) + server | Hive | Eventual to client |
| Driver approval | Firestore `drivers` + Auth claims | Server | Client auth state | Strong on claims |
| Driver availability | Firestore `availabilityState` durable; RTDB presence ephemeral | Driver presence; server durable | Redis cache | Durable strong; presence ephemeral |
| Driver location (live) | RTDB current-trip projection + Redis GEO | Server (validated GPS) | Client map | Best-effort |
| Recommended fare | Pricing service → `pricingSnapshots` | Server | Client estimate UI | Snapshot immutable after write |
| Passenger offer | Firestore `rides.passengerOfferMinor` | Passenger via API only | Offer inbox | Immutable per `requestVersion` |
| Driver offer | Firestore `rideOffers` | Driver via API (eligible only) | Passenger offer list | Immutable amount; status server-managed |
| Agreed fare | Firestore `rides.agreedFareMinor` | Server at select transaction | Receipts | Immutable after assignment |
| Ride assignment | Firestore `rides.assignedDriverId` | Server select transaction | RTDB signal / FCM | Strong transactional |
| Ride state | Firestore `rides` | Server | RTDB `rideSignals` | Strong |
| Payment intent | Firestore `paymentIntents` | Server | Ride summary field | Strong |
| Payment attempt | Firestore `paymentAttempts` | Server | Intent.latestAttemptId | Strong |
| Payment callback | Firestore `paymentProviderCallbacks` | Server webhook | None | Exactly-once effect via dedupe |
| Wallet | Ledger + `walletAccounts` projection | Server | Client wallet UI | Ledger authoritative |
| Ledger | Append-only ledger entries | Server | Wallet / earnings caches | Strong append-only |
| Driver earnings | Ledger + earnings projections | Server | Driver dashboard | Derived from ledger |
| Fee policy | `feePolicies` live; snapshot on ride/intent | Admin live; server snapshot | Receipts | Snapshot immutable |
| Safety incident | Firestore `safetyEvents` | Server | Support UI | Strong |
| Realtime signal | RTDB | Server | FCM | Best-effort |
| Dispatch candidate set | Redis | Server | None | Ephemeral |
| Durable event | Outbox | Server | Pub/Sub | At-least-once publish |
| Audit record | Firestore `rideEvents` | Server | None | Immutable |

## Ordering Invariants

### Ride aggregate version
- Generated by server only.
- Monotonic per ride aggregate.
- Advances only on authoritative ride-state transitions.

### GPS location sequence
- Scoped per `rideId + driverId + locationStreamId`.
- Must be monotonic within the stream.
- Reset only when a new stream ID is created and server recognizes it.

### Durable event ordering
- Event carries aggregate version.
- Consumers must reject older aggregate versions for stateful projections.

## Recovery Invariants

1. Any client reconnecting after missed signals must be able to recover the authoritative current ride from Firestore.
2. If Firestore state changes and RTDB push fails, recovery must come from durable retry/outbox and Firestore read repair.
3. If Redis disappears, correctness remains intact; only latency or availability may degrade.
4. If FCM is delayed or dropped, correctness remains intact; only background delivery quality degrades.
