# ORA — Idempotency Matrix

## Design Rules

1. Idempotency key is client-supplied for client-originated mutations.
2. Provider callback idempotency uses provider reference + callback ID.
3. Ride creation and financial mutations require **durable** idempotency state.
4. Response replay must return the original logical outcome, not “best effort.”

## Matrix

| Operation | Key Shape | Durable Store | Retention | Duplicate Behavior | Response Replay |
|---|---|---|---|---|---|
| `POST /rides` | `ride_create:{passengerId}:{clientNonce}` | durable | 7 days | return original `rideId` | 201 with original body |
| `POST /rides/{id}/offers` | `ride_offer:{rideId}:{driverId}:{clientNonce}` | durable + Redis hint | 7 days | replay original offer | 201 original result |
| `POST /rides/{id}/offers/{offerId}/select` | `ride_select:{rideId}:{passengerId}:{clientNonce}` | durable + Redis hint | 7 days | replay assignment or original 409 | 200 or 409 original result |
| `POST /rides/{id}/cancel` | `ride_cancel:{rideId}:{actorId}:{clientNonce}` | durable | 7 days | if already terminal, return same terminal result | 200 original result |
| `POST /rides/{id}/status` start | `ride_start:{rideId}:{driverId}:{clientNonce}` | durable | 7 days | replay if already started | 200 original result |
| `POST /rides/{id}/status` complete | `ride_complete:{rideId}:{driverId}:{clientNonce}` | durable | 7 days | replay if already completed | 200 original result |
| `POST /payments/cash-collected` | `cash_collected:{rideId}:{driverId}:{clientNonce}` | durable | 30 days | replay CASH_COLLECTED | 200 original |
| `POST /payments/initiate` | `payment_initiate:{paymentIntentId}:{clientNonce}` | durable | 30 days | return original attempt reference | 200/201 original |
| `POST /wallet/topup` | `wallet_topup:{userId}:{clientNonce}` | durable | 30 days | return original payment intent | 200/201 original |
| `POST /payout` | `payout:{driverId}:{clientNonce}` | durable | 30 days | return original payout request state | 200/201 original |
| PSP callback | `{provider}:{providerEventId}` | durable | permanent/audit | ignore already-processed callback | 200 ACK |

## Pending State Behavior

For in-flight commands:
- create durable record with status `PENDING`
- if duplicate arrives while pending, return `202 Accepted` or block briefly and return final result

## Redis Role

Redis may cache recent idempotency outcomes for latency, but it must not be the only retained record for:
- ride creation
- assignment
- payments
- payouts
- refunds
