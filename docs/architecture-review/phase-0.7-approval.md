# ORA — Phase 0.7 Approval

**Date:** 2026-08-18  
**Phase:** 0.7 — Product model + MVVM architecture lock  
**Implementation:** none. Documentation only.

---

## Decision

**APPROVED**

| Severity | Count |
|---|---|
| BLOCKER | 0 |
| HIGH | 0 |
| MEDIUM | 0 (open against the locked model) |
| LOW | residual notes only; see changelog |

Phase 0.6 correctness locks remain in force (Firestore assignment barrier, durable outbox, durable idempotency, ledger vs wallet projection, separate ride/payment SMs, RTDB `rideAccess`, wave dispatch, `amountMinor`).

Phase 0.7 additionally locks the **P2P product model** and **Flutter MVVM** architecture. Phase 1 may begin from these documents. Phase 1 is not started by this report.

---

## Lock statements

1. **MVVM architecture locked**  
   Flutter uses MVVM + Riverpod + feature-based layout. Canonical tree and layer rules: `docs/architecture/flutter-mvvm-architecture.md`. Views have no business logic and do not access repositories or data sources. ViewModels call use cases. go_router is navigation only.

2. **P2P fare model locked**  
   Ora is not a conventional fixed-price auto-dispatch service. Recommended fare is guidance. Passenger offer is the request price. Agreed fare is the selected offer amount and is immutable after assignment. `0.70R–2.50R` is OfferBoundPolicy, not the pricing model. inDrive is a public product reference only.

3. **Offer / counteroffer model locked**  
   `RideOffer` is a durable aggregate (`rideOffers`). Types: `PASSENGER_PRICE_ACCEPTED`, `DRIVER_COUNTEROFFER`. Selectable status: `PENDING`. Expired/stale/withdrawn/superseded offers cannot assign.

4. **Dispatch vs assignment separation locked**  
   Dispatch finds and presents eligible drivers. Driver Accept/Counter creates an offer. Passenger select is the assignment command. Firestore transaction is the correctness barrier.

5. **Payment architecture locked**  
   Methods are configurable: CASH, WALLET, ONLINE_PAYMENT (JazzCash, Easypaisa, Card, later providers). `FeePolicy` is snapshotted. No universal hardcoded commission.

6. **Cash flow locked**  
   Passenger pays driver directly. Record `CASH_COLLECTED`. Platform fee obligation + ledger/settlement. Cash does not pass through Ora’s PSP and remains auditable.

7. **Digital payment flow locked**  
   PaymentIntent → PaymentAttempt → provider → signed webhook → verified ledger. Client “payment successful” is never trusted. Duplicate/late/missing callbacks have defined reconciliation behavior.

8. **Driver earnings model locked**  
   Earnings are derived from the immutable ledger using the snapshotted FeePolicy. `driverNet = fare - 10%` is not an identity unless a policy produces it.

9. **Source-of-truth ownership locked**  
   Matrix in `docs/architecture-review/system-invariants.md` covers recommended fare, passenger offer, driver offer, agreed fare, assignment, payment intent/attempt/callback, wallet, ledger, and driver earnings.

10. **Security boundaries locked**  
    Passenger creates/selects offers only on own rides. Drivers create offers only when eligible/dispatched. Drivers cannot select themselves. Clients cannot write agreedFare, platformFee, driverNetAmount, ledger, payment status, or assignment.

---

## Ride vs payment state machines (locked, separate)

**Ride:** DRAFT, ROUTE_READY, REQUEST_CREATED, SEARCHING, OFFERS_AVAILABLE, DRIVER_ASSIGNED, DRIVER_EN_ROUTE, DRIVER_ARRIVED, RIDE_STARTED, RIDE_COMPLETED, CANCELLED, EXPIRED, NO_SHOW.  
(`RIDE_CLOSED` remains the post-completion ride-aggregate terminal.)

**Payment:** NOT_REQUIRED, PENDING, AUTHORIZED, CAPTURE_PENDING, CAPTURED, FAILED, REFUND_PENDING, REFUNDED, RECONCILIATION_REQUIRED.

---

## Preconditions for Phase 1

- Treat `flutter-mvvm-architecture.md` as the Flutter folder and layer contract
- Treat `offer-model.md` + `ride-assignment.md` as the assignment contract
- Treat `fare-engine.md` as recommended-fare + bound policy only
- Treat `payment-flow.md` as cash/digital/FeePolicy/earnings contract
- Do not implement from Phase 0.5 `architecture-audit.md`

---

## Sign-off

Phase 0.7 product model + MVVM architecture: **APPROVED**.  
Stop. Do not implement Flutter, Dart, packages, Firebase, GCP, payment SDKs, or databases in this phase.
