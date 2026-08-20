# ORA — Phase 0.7 Changelog

**Date:** 2026-08-18  
**Scope:** Documentation only. No Flutter, backend, Firebase, GCP, or payment implementation.

Phase 0.7 locks the Flutter MVVM architecture and corrects the product model to an inDrive-style P2P offered-fare marketplace (public product behavior only).

---

## New documents

| File | Purpose |
|---|---|
| `docs/architecture/flutter-mvvm-architecture.md` | Canonical Flutter MVVM + Riverpod + feature tree and layer rules |
| `docs/algorithms/offer-model.md` | RideOffer, types/statuses, stale-offer handling, select-to-assign |
| `docs/product/ux-product-contract.md` | Passenger and driver UX contract |
| `docs/architecture-review/phase-0.7-changelog.md` | This file |
| `docs/architecture-review/phase-0.7-approval.md` | Approval gate |

---

## Product model corrections

Removed the implication that Ora is a conventional fixed-price auto-dispatch service.

Canonical flow:

1. Route calculated  
2. **Recommended fare** (guidance)  
3. Passenger **offer price**  
4. Request published  
5. Eligible drivers dispatched  
6. Driver accept / counter / decline → **offers**  
7. Passenger compares offers  
8. Passenger selects one offer  
9. Firestore transaction assigns driver  
10. **Agreed fare** immutable  
11. Trip  
12. Payment obligation from agreed fare  

`0.70R → 2.50R` is documented only as a configurable **OfferBoundPolicy**, not as the pricing model.

Four distinct fare fields: `recommendedFare`, `passengerOffer`, `driverCounterOffer`, `agreedFare`.

---

## Dispatch vs assignment

| Before (incorrect as product) | After (locked) |
|---|---|
| Driver Accept = assignment | Driver Accept = pending offer `PASSENGER_PRICE_ACCEPTED` |
| First accept wins / Direct Mode | No Direct Mode |
| `isMarketplaceMode` flag | Single P2P model |
| `DRIVER_SELECTED` durable state | Select commits to `DRIVER_ASSIGNED` |
| 3-driver accept race = 1 winner | 3-driver accept race = 3 offers; select race = 1 assignment |

---

## Payment / earnings

- Configurable methods: `CASH`, `WALLET`, `ONLINE_PAYMENT` (JazzCash, Easypaisa, Card, later providers)
- `FeePolicy` replaces hardcoded 10%/12% commission
- Cash: passenger pays driver; `CASH_COLLECTED`; platform fee obligation; ledger; no PSP cash-through
- Digital: intent → attempt → provider → webhook → verified ledger
- Earnings derived from ledger: agreedFare, grossFare, platformFee, driverNetAmount, PSP fee, tolls, airport, adjustments, refunds
- Ride SM and payment SM remain separate

---

## Flutter

Canonical `lib/` tree:

- `app/` (app.dart, router, theme)
- `core/` (errors, network, storage, location, maps, utils)
- `features/{auth,passenger,driver,ride,maps,payments,safety}` with `presentation/{views,view_models,widgets}`, `domain/`, `data/`
- `main.dart`

Views render and send intents. ViewModels hold presentation state and call use cases. Repositories hide data sources. Riverpod wires DI/lifecycle. Freezed for immutable state. go_router is navigation only.

---

## Files updated (non-exhaustive)

- `docs/algorithms/fare-engine.md` — recommended-fare engine + offer bounds policy
- `docs/algorithms/matching-engine.md` — dispatch only
- `docs/algorithms/ride-assignment.md` — select-offer transaction
- `docs/algorithms/idempotency.md` — offer/select/cash-collected keys
- `docs/product/passenger-flow.md`, `driver-flow.md`, `ride-lifecycle.md`, `payment-flow.md`
- `docs/database/firestore-schema.md` — rideOffers, feePolicies, fare fields, no isMarketplaceMode
- `docs/database/realtime-schema.md`, `indexes.md`
- `docs/api/ride-api.md`, `api-contract.md`, `error-codes.md`
- `docs/architecture/realtime-architecture.md`, `system-overview.md`, `frontend-architecture.md`, `backend-architecture.md`
- `docs/architecture-review/system-invariants.md`, `event-contracts.md`, `consistency-model.md`, `idempotency-matrix.md`, `dispatch-wave-design.md`, `authorization-audit.md`, `payment-ledger-design.md`
- `docs/ORA_MASTER_PLAN.md`, `ORA_STATE_MACHINE.md`, `ORA_SECURITY_MODEL.md`, `ORA_LATENCY_SLO.md`
- `docs/security/authorization-matrix.md`, `threat-model.md`, `security-model.md`
- `docs/testing/race-condition-tests.md`, `test-strategy.md`
- `docs/implementation/phase-01`, `05`, `07`, `08`, `09`, `11`
- `docs/operations/observability.md`

Phase 0.5 `architecture-audit.md` is labeled **historical** and must not be implemented from.

---

## inDrive reference

Used only as **public product reference**: passenger proposes a price, drivers accept/counter/decline, passenger chooses, agreed price is the trip price.

No claim is made about undocumented inDrive infrastructure or private algorithms.

---

## Consistency audit

Searched the docs tree for fare, offer, assignment, dispatch, payment, commission, earnings, wallet, cash, MVVM, Riverpod, Firestore, RTDB, Redis contradictions.

Remaining mentions of Direct Mode, 10%/12% commission, first-accept-wins, `DRIVER_SELECTED`, and `wallets` are **negations or historical labels**, not competing designs.

Residual notes (not blockers):

- Offer enum includes `ACCEPTED` for product language; selectable status is `PENDING`
- `RIDE_CLOSED` remains the ride-aggregate terminal after `RIDE_COMPLETED` (Phase 0.6)
- `DRIVER_NOT_ELIGIBLE` may be 403 at offer-create and 422 at select
- Some older Dart snippets in stale-event examples still show notifier naming; MVVM ViewModel naming is canonical
