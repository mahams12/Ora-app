# Payment Architecture (Separate Aggregate + Immutable Ledger)

Authoritative sources:
- `docs/product/payment-flow.md`
- `docs/architecture-review/payment-ledger-design.md`
- `docs/database/firestore-schema.md` (payment collections)
- `docs/architecture-review/idempotency-matrix.md`
- `docs/ORA_SECURITY_MODEL.md`

## Separation of Concerns

- Ride lifecycle ends at `RIDE_COMPLETED` / `RIDE_CLOSED` (ride aggregate).
- Payment lifecycle is a separate aggregate starting from `agreedFareMinor`.
- Never infer payment truth from ride state alone.

## Aggregates & Ownership

- `paymentIntents` — intent/state machine (server-only writes)
- `paymentAttempts` — one provider interaction per attempt
- `paymentProviderCallbacks` — inbound webhook dedupe + audit
- `walletLedgerEntries` — immutable append-only ledger (financial truth)
- `walletAccounts.balanceMinor` — projection derived from ledger
- `refunds`, `driverPayouts`, `reconciliationRecords` — server workflows

## State Machine

Payment states:
`NOT_REQUIRED → PENDING → AUTHORIZED → CAPTURE_PENDING → CAPTURED`
`→ FAILED`
`→ REFUND_PENDING → REFUNDED`
`→ RECONCILIATION_REQUIRED`

## Webhook Safety

- Provider callback dedupe key: `{provider}:{providerEventId}`
- Duplicate callbacks ACK without applying ledger effects again
- Missing/late callbacks lead to `RECONCILIATION_REQUIRED` and scheduled recovery jobs (Gap: exact reconciliation job contract is not fully enumerated in the docs set).

## Idempotency

- Idempotency required on payment mutations (`initiate`, `cash-collected`, `refund`, `wallet/topup` etc. per matrix)
- Ledger posting uses a financial idempotency key; prevents double-charge/capture.

