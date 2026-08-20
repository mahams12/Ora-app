# Phase 11 — Payments

**Status:** NOT STARTED  
**Dependencies:** Phase 10

## Objectives

Wallet, JazzCash, Easypaisa, receipts, driver payouts.

## Key Implementation Points

- Cash payment already functional from Phase 7 (driver taps "Cash received")
- Phase 11 adds: wallet top-up, JazzCash SDK, Easypaisa SDK, card-on-file
- Server-only payment processing; PSP webhooks signed and validated
- Ledger: append-only transactions collection
- Wallet balance: computed from ledger; cached in `walletAccounts/{uid}.balanceMinor`
- Idempotency keys on all payment operations
- Double-charge prevention via PSP idempotency keys
- Driver payout: batch settled daily via PSP API
- Cancellation fees implemented
- Refund flow: admin-initiated; server updates ledger

## Acceptance Criteria

- [ ] Wallet top-up via JazzCash works (sandbox)
- [ ] Wallet top-up via Easypaisa works (sandbox)
- [ ] Wallet deducted on trip completion (correct amount)
- [ ] Double-charge test: POST payment × 2 with same key → exactly 1 charge
- [ ] Receipt shows agreedFare, platformFee (FeePolicy snapshot), driverNet — not a hardcoded commission
- [ ] Driver earnings updated correctly after each trip
- [ ] Payout API tested in sandbox
- [ ] Cancellation fee applied in correct scenarios
- [ ] Refund flow works (admin-initiated)
- [ ] No client can write wallet balance directly
