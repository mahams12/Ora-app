# ADR-004: Redis GEO for Candidate Generation (Non-Authoritative)

## Status
Accepted / Locked.

## Decision
Use Redis GEO index for nearby candidate generation and optional contention reduction.
Redis is never authoritative assignment/payment state.

## Consequences
- Lower dispatch latency via O(log n) spatial lookup.
- Correctness remains via Firestore transactional barriers.
- If Redis is unavailable, dispatch degrades; assignment correctness remains.

