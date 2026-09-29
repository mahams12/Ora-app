# ADR-004: Redis GEO for Candidate Generation (Non-Authoritative)

## Status
Accepted / Locked.

> **Implementation note (2026-09-21):** GEO **write/projection** exists (N2C). Nearby **query** (N3) and dispatch (N4) do **not**. See [`docs/implementation/n-series/N2C-redis-geo.md`](../../implementation/n-series/N2C-redis-geo.md).

## Decision
Use Redis GEO index for nearby candidate generation and optional contention reduction.
Redis is never authoritative assignment/payment state.

## Consequences
- Lower dispatch latency via O(log n) spatial lookup.
- Correctness remains via Firestore transactional barriers.
- If Redis is unavailable, dispatch degrades; assignment correctness remains.

