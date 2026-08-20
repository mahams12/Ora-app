# ADR-015: Observability Model

## Status
Accepted / Locked.

## Decision
Every request/event carries correlation IDs (requestId, rideId, eventId, operationId).
Cloud Run uses structured JSON logs; Cloud Monitoring exposes SLO dashboards and PagerDuty alerts.

