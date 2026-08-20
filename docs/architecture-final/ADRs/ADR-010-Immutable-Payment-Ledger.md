# ADR-010: Immutable Payment Ledger is Financial Truth

## Status
Accepted / Locked.

## Decision
Financial correctness is provided by an append-only ledger (`walletLedgerEntries`).
Wallet balances are derived projections.
All ledger effects must be idempotent and guarded against duplicate webhooks.

