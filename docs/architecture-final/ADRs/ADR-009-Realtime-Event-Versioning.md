# ADR-009: Versioned Realtime Events & Monotonic Discard

## Status
Accepted / Locked.

## Decision
Realtime projections (RTDB signals and GPS) must be versioned and guarded by monotonic discard rules:
- ride `aggregateVersion` + signal `eventSequence`
- GPS `locationSeq` in a scoped stream

Clients treat RTDB as projections and perform read-repair from Firestore when versions diverge.

