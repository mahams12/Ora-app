# ORA — Cost Model Review

## Likely Major Cost Drivers

1. Google Places autocomplete
2. Google Routes / Distance Matrix
3. RTDB bandwidth for live trips
4. Firestore reads from poorly scoped listeners or duplicated projections
5. Cloud Logging volume if GPS or request fan-out is over-logged
6. FCM fan-out amplified by simultaneous top-30 dispatch

## Obvious Cost Risks In Current Design

### Top-30 simultaneous dispatch
Multiplies RTDB writes, FCM sends, and stale-card cleanup operations even when one of the first few drivers accepts quickly.

### Distance Matrix on too many candidates
If precise ETA is computed before enough filtering, matching cost rises rapidly.

### Duplicated state mirrors
`drivers.isOnline`, RTDB presence, and Redis online records create extra writes and reconciliation work.

### Unbounded history on hot ride documents
Larger Firestore documents cost more to read and write.

## Recommended Cost Controls

- session tokens for Places
- precise ETA only for narrowed candidates
- wave dispatch
- bounded document size
- logging sampling for per-packet telemetry
