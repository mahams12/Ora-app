# ORA — Dispatch Wave Design

## Recommendation

Do not notify the top 30 drivers simultaneously for MVP.

## Proposed Deterministic Strategy

### Wave 1
- top 5 drivers
- wait 4–6 seconds
- stop if assigned (passenger selected an offer)
- stop expanding once enough meaningful pending offers exist (configurable threshold)

Do not stop a wave solely because one driver tapped Accept.

### Wave 2
- next 10 drivers
- only if still unassigned or insufficient offers

### Wave 3
- next 15 drivers
- only if still unresolved

## Why

| Concern | Simultaneous Top-30 | Wave Dispatch |
|---|---|---|
| notification spam | high | lower |
| accept contention | high if Accept assigned | N/A — Accept is not assignment; select contention is passenger-side |
| RTDB write burst | high | staged |
| FCM burst | high | staged |
| passenger wait | sometimes lower | usually acceptable if tuned |
| driver UX | noisy | cleaner |

## Operational Rule

Assignment ends all later waves immediately.  
Wave progression should be scheduled server-side and canceled by assignment/cancel/expiry.

## Metrics To Watch

- request-to-first-offer latency
- request-to-assignment latency
- offers per ride
- stale-card cleanup count
- accept conflict rate
