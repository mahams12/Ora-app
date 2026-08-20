# ADR-013: Offline / Reconnect Strategy

## Status
Accepted / Locked.

## Decision
RTDB is projected, so the client must always be able to recover authoritative state from Firestore on reconnect.
RTDB/GPS stale events are discarded via monotonic version/sequence rules.

