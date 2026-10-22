# Driver Payout + Commission — Audit & Proposed Minimal Model

**Status:** IMPLEMENTED — launch policy (fee NONE) shipped & unit-tested;
no non-zero commission activated, not deployed (2026-10-19).

## 1. Existing money data flow (verified)

| Stage | What happens today | Where |
|---|---|---|
| Offer submit | `RideOfferDoc` created with `amountMinor`, `currency: 'PKR'` (hardcoded), bounds-checked against the pricing snapshot | `ride_service.ts` ~L1140–1175 |
| Offer select (one tx) | Ride doc stamped atomically: `agreedFareMinor = offer.amountMinor`, `agreedFareCurrency = offer.currency`, `agreedOfferId`, `assignedDriverId`, `assignedAt`, **plus an existing stub** `feePolicySnapshot = {platformFeeType:'NONE', currency:'PKR', capturedAt}` | `ride_service.ts` ~L1629–1643 |
| Progression → `RIDE_COMPLETED` | `progressRide` tx: version CAS, assignment-snapshot immutability guard (`agreedFareMinor`/`agreedOfferId`/`assignedDriverId` must be non-null), `completedAt` set once, outbox `ride.completed` emitted, idempotency record written — **early-return replay if `state == toState`** | `ride_service.ts` ~L2146–2249 |
| Client surface | `publicRide` exposes `agreedFareMinor`/`agreedOfferId`/`agreedFareCurrency` — **no payout/fee fields exist** | `ride_service.ts` ~L295–297 |
| Earnings UI | Sums `agreedFareMinor` for `RIDE_COMPLETED`/`RIDE_CLOSED`, labelled "Trip fares"; payout/commission shown as *not recorded* | Phase 3 mobile slice |

**Key finding:** the snapshot slot already exists. `feePolicySnapshot` is written
at *selection* (not completion) with a hardcoded `platformFeeType:'NONE'`
placeholder — the plumbing is there; only the policy source and derived fields
are missing.

## 2. Owner decisions required (none invented)

1. **Fee model shape:** percentage-of-fare, flat per-ride, tiered, or `NONE`
   at launch? (Rate values must NOT be coded without approval.)
2. **Policy scope:** mirror `pricingRules/{city}_{category}` (city×category
   docs), or a single global policy doc?
3. **Rounding rule** for percentage fees on integer minor units — recommend
   `floor(fareMinor × bps / 10000)` (favors driver, deterministic), but owner
   must confirm.
4. **Fee bearer:** confirm passenger pays gross `agreedFareMinor` and the
   platform fee is deducted from the driver's share (standard marketplace).
5. **Missing-policy behavior:** recommend *non-blocking* — selection succeeds
   with `resolution:'UNAVAILABLE'` so a config gap never blocks the
   marketplace; alternative is hard-fail selection (rejected — couples
   matching to config availability).
6. **Settlement semantics:** `driverPayoutMinor` means "amount owed to driver
   at completion" — cash rides settle offline; no provider integration in
   scope.
7. **Historical rides:** pre-schema docs have no payout fields — recommend
   leaving absent (client already treats missing fare honestly) rather than
   backfilling with a policy that didn't exist at the time.

## 3. Proposed schema (smallest safe change)

Derive **at offer selection**, inside the existing `selectOffer` transaction —
the same atomic write that already stamps `agreedFareMinor` and the fee stub.
Completion stays a pure state transition; no money math added to
`progressRide`.

```ts
// RideDoc — new optional fields, immutable once set (same immutability class
// as the existing assignment snapshot).
driverPayoutMinor: number | null;      // agreedFareMinor - platformFeeMinor
platformFeeMinor: number | null;       // integer minor units, >= 0
payoutCurrency: 'PKR' | null;          // must equal agreedFareCurrency

// feePolicySnapshot is UPGRADED from the existing stub (additive fields):
feePolicySnapshot: {
  policyId: string;                    // e.g. 'lahore_easy' | 'global'
  policyVersion: string;               // policy doc's version marker
  platformFeeType: 'PERCENT_BPS' | 'FLAT_MINOR' | 'NONE';
  percentBps?: number;                 // integer basis points, 0..10000
  flatMinor?: number;                  // integer minor units
  currency: string;                    // must equal offer.currency
  capturedAt: string;                  // ISO, selection time
  resolution: 'APPLIED' | 'UNAVAILABLE';
}
```

**New policy store:** `feePolicies/{city}_{category}` (+ optional
`feePolicies/_global` fallback), admin-SDK-only — same access pattern as
`pricingRules`. Shape: `{platformFeeType, percentBps|flatMinor, currency,
version, updatedAt}`.

**Invariants:**
- `platformFeeMinor = floor(agreedFareMinor × percentBps / 10000)` or
  `flatMinor` or `0`; clamped to `[0, agreedFareMinor]` (fee never exceeds fare).
- `driverPayoutMinor = agreedFareMinor - platformFeeMinor` (never negative).
- If policy doc missing or `payoutCurrency != agreedFareCurrency` →
  `resolution:'UNAVAILABLE'`, `platformFeeType:'NONE'`, `platformFeeMinor:0`,
  `driverPayoutMinor = agreedFareMinor` — explicitly recorded, never silent.
- Null `agreedFareMinor` → all payout fields null (missing-fare rides honest).

## 4. Idempotency & concurrency

- **Selection retry:** existing idempotency record replays the same response;
  the tx CAS (`requestVersion`, offer `PENDING` status) prevents double-select.
  Payout derived in that tx is write-once — identical on replay.
- **Completion retry:** `progressRide` early-returns on `state == toState`;
  payout fields are untouched by progression — completion cannot alter or
  duplicate them.
- **Offer supersede/withdraw:** losing offers write nothing; `SUPERSEDED`
  marks only. Payout fields exist only after the winning select.
- **Cancellation pre/post completion:** fields stay immutable; earnings
  aggregation already filters `RIDE_COMPLETED`/`RIDE_CLOSED` only.

## 5. Client/API surface (post-approval)

- `publicRide` adds `driverPayoutMinor`, `platformFeeMinor`,
  `payoutCurrency`, `feePolicySnapshot.resolution` (passenger-visible fields
  unchanged; payout fields are driver-relevant but harmless — review whether
  to gate by role).
- Earnings VM: when `driverPayoutMinor != null` → label "Driver payout";
  else keep "Trip fare" + existing honest fallback. Migration = additive
  field read, no breaking change.

## 6. Backfill implications

None recommended. Historical rides lack the fields → aggregation treats them
as fare-only (current behavior). A backfill would require knowing which
policy *would have* applied at that ride's selection time — not recoverable;
inventing it violates the honest-money rule.

## 7. Focused test plan (to implement on approval)

| Case | Assert |
|---|---|
| Percent fee derivation | `driverPayoutMinor = fare - floor(fare×bps/10000)` |
| Flat fee / NONE policy | correct fields; NONE → payout == fare |
| Rounding | odd minor amounts floor deterministically |
| Currency mismatch | `resolution:'UNAVAILABLE'`, payout = fare, selection still succeeds |
| Missing policy doc | same UNAVAILABLE path; no thrown error |
| Select retry | identical `responseSnapshot`; payout fields unchanged |
| Completion retry | payout fields byte-identical before/after |
| Fee clamp | `percentBps > 10000` or `flatMinor > fare` rejected at policy write |
| `publicRide` | new fields present; absent on historical docs |
| Earnings aggregation | payout-aware totals; fare-only fallback |

## 8. Explicit non-goals

- No payment provider, wallet, cash-out, transfer, or settlement ledger.
- No pricing/matching/state-machine changes.
- No commission rate values committed without owner sign-off.

## Implementation record (2026-10-19, launch policy)

Owner-approved launch rules: fee NONE → `platformFeeMinor=0`,
`driverPayoutMinor=agreedFareMinor`, only when fare/currency valid; no
non-zero policy activated; no backfill; no settlement scope.

- `src/pricing/fee_policy.ts` (new) — `computePlatformFeeMinor`
  (floor(fare×bps/10000), clamped [0,fare]), `derivePayoutSnapshot`,
  `parseFeePolicyDoc`, `FEE_POLICIES_COLLECTION='feePolicies'`,
  `_global` fallback doc id. Resolution: `APPLIED` (policy doc found),
  `LAUNCH_DEFAULT` (no doc → NONE by launch rule), `UNAVAILABLE`
  (invalid fare/currency → null payout fields).
- `ride_service.ts` `selectOffer` — policy doc read inside the select tx
  (`{city}_{category}` → `_global` fallback), snapshot + payout fields
  written atomically with assignment; replay returns recorded values;
  completion (`progressAssignedRide`) never touches them.
- `RideDoc` — `driverPayoutMinor`/`platformFeeMinor`/`payoutCurrency`
  (null on pre-model rides); `feePolicySnapshot` now carries
  `policyId`/`policyVersion`/`resolution`.
- `publicRide` — exposes the three fields + `feePolicyResolution`.
- Client — `Ride` entity + remote parser gained the four fields;
  `driver_earnings_summary.dart` tracks payout-backed vs fare-only bases
  separately (`payoutRideCount`/`payoutMinor`/`fareOnlyMinor` per period);
  earnings hero shows "Driver payout" only when payout-backed rides exist.
- Tests — `fee_policy.test.ts` (11: pure derivation incl. floor rounding,
  clamp, currency mismatch, invalid data, malformed policy; integration:
  atomic select, replay, explicit NONE policy, completion never
  recomputes) + 3 new aggregator tests (payout basis, mixed bases,
  payout-without-fare). Backend suite 468/468; driver suite 131 pass;
  `tsc --noEmit` + `flutter analyze lib/` clean.
