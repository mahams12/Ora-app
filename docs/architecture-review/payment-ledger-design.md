# ORA — Payment & Ledger Design Review

## Required Financial Aggregates

### Payment Intent
Represents what Ora is trying to collect or settle.

### Payment Attempt
Represents one interaction with a PSP for an intent.

### Provider Callback Record
Stores each inbound PSP callback exactly once for audit and dedupe.

### Ledger Entry
Immutable debit/credit journal row.

### Wallet Projection
Cached balance derived from the ledger.

### Payout
Represents driver settlement workflow.

### Refund / Adjustment
Explicit compensating financial actions.

## Financial Source Of Truth

| Concept | Authoritative Source |
|---|---|
| wallet balance cache | projection |
| ledger | financial truth |
| payment status | payment aggregate |
| ride state | ride aggregate |

Ride state must not be the only place where payment truth is inferred.

Cash is auditable (`CASH_COLLECTED`) even though cash does not pass through a PSP.

`driverNetAmount` is derived from the ledger using a snapshotted `FeePolicy`. It is not assumed to be fare − 10%.

## Minimum Ledger Entry Shape

```json
{
  "ledgerEntryId": "led_01J...",
  "accountId": "wallet:passenger:uid_123",
  "entryType": "DEBIT",
  "amountMinor": 34000,
  "currency": "PKR",
  "referenceType": "paymentAttempt",
  "referenceId": "payatt_01J...",
  "correlationId": "req_abc123",
  "createdAt": "2026-08-18T07:30:00Z"
}
```

## Duplicate Callback Handling

Use provider dedupe key:

`{provider}:{providerEventId}`

Process flow:
1. store callback record if unseen
2. if already seen, ACK without replaying financial effect
3. if unseen, map to payment attempt and apply financial transition once

## Required Supporting Records

- explicit payment schema
- payout schema
- refund schema
- reconciliation records
- callback dedupe records

Chargeback handling can remain a later operational enhancement, but the core payment aggregates above are required before Phase 1.
