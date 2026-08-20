# ORA — Scalability Model

## Modeling Assumptions

- idle/searching drivers publish presence/location every 5s
- active-trip drivers publish every 1s
- RTDB carries live trip projection
- Redis carries geo index

## Approximate Steady-State Driver Location Load

| Active Drivers | Approx GPS writes/sec at 5s cadence | Notes |
|---|---|---|
| 100 | 20/sec | manageable |
| 1,000 | 200/sec | still comfortable |
| 10,000 | 2,000/sec | requires disciplined fan-out |
| 100,000 | 20,000/sec | architecture and cost pressure become material |

## Major Bottlenecks

1. Simultaneous fan-out of 30 request cards per ride.
2. Google ETA calls during ranking if used too early on too many drivers.
3. Firestore projections duplicated on hot paths.
4. Logging volume if every GPS packet is fully logged.

## Scaling Guidance

- keep Firestore off live GPS path
- compute precise ETA only for narrowed candidate set
- use wave dispatch
- cap or sample verbose GPS logs
- keep wallet/ledger writes out of ride hot path except required finalization

## MVP Judgment

The proposed architecture is justified for correctness-sensitive ride dispatch, but only if:
- Firestore remains the ride truth
- RTDB remains projection only
- Redis remains ephemeral
- Pub/Sub and outbox are formalized
