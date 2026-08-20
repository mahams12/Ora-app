# ADR-011: Location Architecture (Server Validation + Sequence Scoping)

## Status
Accepted / Locked.

## Decision
Treat client GPS as untrusted input; server validates accuracy/staleness/plausibility and enforces monotonic `locationSeq` within a negotiated `locationStreamId`.
RTDB stores only server-validated `tripLocations`.

