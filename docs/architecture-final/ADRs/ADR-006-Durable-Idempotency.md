# ADR-006: Durable Idempotency Records

## Status
Accepted / Locked.

## Decision
All business-critical and financial mutations must be protected by durable idempotency records keyed by `Idempotency-Key` and request hash.
If duplicate arrives:
- same key + same payload → replay stored logical result
- same key + different payload → reject (`409 IDEMPOTENCY_KEY_REUSED`)

## Consequences
- Safe retries over unstable mobile networks.
- Deterministic observable outcomes for correctness-critical actions.

