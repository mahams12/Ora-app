# ORA — Location Trust Model

## Principle

Client-provided GPS is untrusted input. It is useful, but not authoritative by itself.

## Trust Layers

### Client-provided signals
- latitude / longitude
- accuracy
- speed
- heading
- timestamp
- sequence number

### Server-derived signals
- accepted/rejected packet
- last accepted location stream position
- route deviation classification
- stale-location classification
- arrival / completion proximity validation
- impossible travel detection

## Security Rules

1. Kalman filtering improves UX; it is not a fraud-control mechanism.
2. App Check improves app attestation; it is not a proof of honest GPS.
3. Arrival and completion transitions must require server-side proximity checks.
4. Replayed or stale packets must be rejected by timestamp and sequence validation.
5. Sequence scope must be per ride-stream, not a global per-device integer without restart handling.

## Required Server Checks

| Check | Purpose |
|---|---|
| `accuracy <= threshold` | reject low-confidence points |
| timestamp freshness | reject replay / delayed packets |
| monotonic stream sequence | reject out-of-order and duplicate packets |
| distance vs elapsed time plausibility | detect teleportation |
| route plausibility | detect impossible or highly suspicious travel |
| pickup/destination geofence | authorize arrival/completion |

## Recovery

If driver app restarts mid-trip:
- obtain current active ride from Firestore
- request latest accepted location cursor/stream state
- resume with a new stream identifier or negotiated next accepted sequence

Without this, simple monotonic sequence comparison is underspecified.
