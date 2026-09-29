# ADR-011: Location Architecture (Server Validation + Sequence Scoping)

## Status
Accepted / Locked.

> **Implementation note (2026-09-21):** Server validation + `locationStreamId`/`locationSeq` cursor is **N2A (IMPLEMENTED)**. Redis GEO projection is **N2C (IMPLEMENTED)**. RTDB `tripLocations` remains a **target — N2B NOT IMPLEMENTED**. See [`docs/architecture/N_LOCATION_FLOW.md`](../N_LOCATION_FLOW.md).

## Decision
Treat client GPS as untrusted input; server validates accuracy/staleness/plausibility and enforces monotonic `locationSeq` within a negotiated `locationStreamId`.
RTDB stores only server-validated `tripLocations`.

