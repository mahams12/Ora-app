# ORA — Payment Flow

Ride state and payment state are **separate aggregates**. Completing a ride does not capture money by itself.

Payment obligation is always derived from **agreedFare**, never from `recommendedFare` or an unslected passenger offer.

## Payment Methods (configurable, not universal)

Ora does **not** assume one payment method for every city, category, or account.

| Method family | Examples | Notes |
|---|---|---|
| `CASH` | Passenger pays driver directly | Platform never processes the cash through a PSP |
| `WALLET` | Ora Wallet | Ledger-backed; balance is a projection |
| `ONLINE_PAYMENT` | JazzCash, Easypaisa, Card, later providers | Provider callback is server-authoritative |

Availability may vary by:

- country
- city
- ride category
- account status
- provider availability
- `FeePolicy` / `PaymentMethodPolicy`

Clients request a method. Server decides whether it is allowed and snapshots it onto the ride / payment intent.

Cash is the Phase 7 collection path. Wallet and online providers are Phase 11, but the **model** is locked now.

## Core Financial Model

- `PaymentIntent` — obligation created from `agreedFareMinor` (+ snapshotted extras)
- `PaymentAttempt` — one collection/capture attempt
- `PaymentProviderCallback` — inbound webhook stored and deduped
- `FeePolicy` snapshot — how platform fee was computed for this transaction
- `WalletLedgerEntry` / financial ledger — immutable truth
- `WalletAccount.balanceMinor` — projection
- `DriverEarningsEntry` / payout — settlement workflow, not ride state

Client claims of “payment successful” are never trusted.

---

## FeePolicy (not a hardcoded 10% / 12%)

Do **not** hard-code a universal platform commission.

```json
{
  "feePolicyId": "fp_lahore_easy_cash_v3",
  "platformFeeType": "PERCENT" | "FLAT" | "PERCENT_PLUS_FLAT" | "NONE",
  "platformFeeValue": { "bps": 1200, "flatMinor": 0 },
  "effectiveFrom": "2026-08-01T00:00:00Z",
  "effectiveTo": null,
  "city": "lahore",
  "category": "easy",
  "paymentMethod": "CASH",
  "currency": "PKR"
}
```

At assignment (or at latest at payment-intent creation) the server snapshots:

- `feePolicyId`
- `platformFeeType` / `platformFeeValue`
- computed `platformFeeMinor`
- `driverNetAmountMinor` formula inputs
- currency

Later policy edits do not rewrite historical rides.

`driverNet = agreedFare - 10%` is **forbidden as an assumed identity**. It is valid only if a snapshotted `FeePolicy` produces that arithmetic.

---

## Earnings Components

| Field | Meaning |
|---|---|
| `agreedFareMinor` | Immutable trip price from selected offer |
| `grossFareMinor` | agreedFare plus server-authorized extras (tolls, airport) if policy includes them |
| `platformFeeMinor` | From FeePolicy snapshot |
| `paymentProviderFeeMinor` | PSP fee if the method incurs one; 0 for cash |
| `tollsMinor` / `airportFeeMinor` | If charged and snapshotted |
| `adjustmentsMinor` | Bonuses, wait fees, corrections |
| `refundsMinor` | Posted refunds |
| `driverNetAmountMinor` | Residual owed to / retained by driver after policy |

Driver earnings are **derived from the immutable ledger**, not from the ride document as a writable field.

---

## Payment State Machine (independent of ride)

```
NOT_REQUIRED
PENDING
AUTHORIZED
CAPTURE_PENDING
CAPTURED
FAILED
REFUND_PENDING
REFUNDED
RECONCILIATION_REQUIRED
```

| Ride | Payment |
|---|---|
| `RIDE_COMPLETED` | may still be `PENDING` (cash not confirmed, digital waiting) |
| `RIDE_COMPLETED` | `CAPTURED` after verified collection |
| `CANCELLED` | `NOT_REQUIRED` or fee `PENDING` per cancellation policy |
| `RIDE_COMPLETED` | `FAILED` / `RECONCILIATION_REQUIRED` without reopening the ride |

Never store payment status only on the ride document.

---

## Cash Lifecycle

Cash does **not** pass through Ora's PSP. It must still be auditable.

```
Ride completed
      ↓
Agreed fare = Rs X (agreedFareMinor)
      ↓
Passenger pays driver directly
      ↓
Driver confirms collection → PaymentAttempt provider=CASH
      ↓
Payment record = CASH_COLLECTED (attempt CAPTURED)
      ↓
Platform fee obligation calculated from FeePolicy snapshot
      ↓
Ledger:
  - cash_in_driver (informational / receivable tracking)
  - platform_fee_receivable from driver (or wallet withhold)
      ↓
Driver / platform settlement according to policy
      ↓
Reconciliation
```

Example postings (illustrative, not a fixed rate):

- Driver collected cash = agreedFare
- Platform is owed `platformFeeMinor`
- Driver net retained in cash = agreedFare − platformFee − other snapshotted items
- Ora later collects the fee via wallet withhold, next digital trip, or payout deduction

If the driver never confirms cash:

- payment stays `PENDING` then may move to `RECONCILIATION_REQUIRED`
- ride remains `RIDE_COMPLETED`
- support/ops tools resolve; client cannot mark captured

---

## Digital Payment Flow

```
Ride completed
      ↓
PaymentIntent (amount from agreedFare + extras)
      ↓
PaymentAttempt
      ↓
Provider (JazzCash / Easypaisa / Card / later)
      ↓
Callback / webhook (HMAC-signed)
      ↓
Verified payment (server)
      ↓
Ledger entries
      ↓
Driver / platform settlement
```

### Outcomes

| Outcome | Behavior |
|---|---|
| Success | Attempt captured; ledger posted once; payment `CAPTURED` |
| Failure | Attempt `FAILED`; intent may retry a new attempt or stay `FAILED` |
| Timeout | Do **not** infer failure; move toward `CAPTURE_PENDING` / `RECONCILIATION_REQUIRED` |
| Duplicate callback | Dedupe `{provider}:{providerEventId}`; ACK; no second ledger post |
| Late callback | Apply idempotently against latest attempt |
| Missing callback | Reconciliation job; never trust client success |
| Refund / partial refund | New compensating ledger entries; payment `REFUND_PENDING` → `REFUNDED` |
| Wallet | Debit passenger ledger; credit platform/driver per snapshot |

Webhook handler is server-authoritative. Flutter “success” screens are projections.

---

## Wallet Top-Up

```
1. Passenger selects amount and provider
2. PaymentIntent (type TOP_UP) + PaymentAttempt
3. Provider redirect / deeplink
4. Signed webhook
5. Ledger credit
6. WalletAccount.balanceMinor projection updated
```

Wallet spend on a ride is a ledger debit of `agreedFareMinor` (or policy amount), not a client-side subtract.

---

## Ledger Design

All money movements are immutable ledger entries. Typical accounts:

- `wallet:passenger:{uid}`
- `wallet:driver:{uid}`
- `platform:fees`
- `platform:psp_fees`
- `cash:driver:{uid}` (cash collected, not PSP cash)

```json
{
  "ledgerEntryId": "led_abc123",
  "accountId": "wallet:passenger:uid_xyz",
  "userId": "uid_xyz",
  "type": "DEBIT",
  "amountMinor": 34000,
  "currency": "PKR",
  "rideId": "ride_abc",
  "description": "Trip to Liberty Market",
  "paymentIntentId": "pi_abc123",
  "paymentAttemptId": "pa_abc123",
  "feePolicySnapshotId": "fps_abc",
  "createdAt": "2026-08-18T07:30:00Z",
  "status": "POSTED",
  "paymentMethod": "WALLET",
  "idempotencyKey": "txn:ride_abc:debit:uid_xyz"
}
```

Wallet balance = sum of posted credits − debits ± holds. Cached on `walletAccounts/{uid}.balanceMinor`. Collection name `wallets` is **not** canonical.

---

## Driver Payout

```
1. Earnings accumulate as posted ledger rows
2. Driver requests payout or schedule fires
3. Server validates policy threshold
4. DriverPayout + provider transfer
5. Ledger deducted when provider confirms
```

Payout is independent of a single ride's payment SM.

---

## Cancellation Fees

Amounts come from cancellation `FeePolicy`, not hardcoded product copy. Typical **policy examples** (configurable):

| Scenario | Example policy |
|---|---|
| Cancel before assignment | Free |
| Cancel after assignment, before en route (< 2 min) | Free |
| Cancel after driver en route | Flat fee if policy enabled |
| Cancel after arrived | Higher fee if policy enabled |
| Driver cancels after assigned | Driver penalty metric / fee if policy enabled |

---

## Double-Charge / Callback Safety

- Idempotency-Key on initiate / capture / cash-collected / refund / payout
- Durable `idempotencyRecords`
- Provider `{provider}:{providerEventId}`
- Ledger unique constraint on financial idempotency key
- Missing/late callbacks → `RECONCILIATION_REQUIRED`, not ride rollback
