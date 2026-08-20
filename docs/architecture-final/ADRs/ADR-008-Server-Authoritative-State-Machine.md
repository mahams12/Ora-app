# ADR-008: Server-Authoritative State Machines (Ride + Payment Separation)

## Status
Accepted / Locked.

## Decision
Ride lifecycle state transitions are enforced by the server using the locked ride state machine (`docs/ORA_STATE_MACHINE.md`).
Payment lifecycle is a separate aggregate and must not be merged with ride lifecycle.

## Consequences
- No client-side “skipping states” can create impossible states.
- Payment correctness is ledger-driven and recoverable independently.

