# Observability, Metrics, Traces, Alerts

Authoritative sources:
- `docs/operations/observability.md`
- `docs/ORA_LATENCY_SLO.md`
- `docs/architecture-review/outbox-design.md`

## Correlation & IDs

Every critical operation carries:
- `requestId` (client generates for API calls)
- `rideId`, `driverId`, `passengerId`
- `eventId` (durable event ID)
- `operationId` (server span/operation)
- `timestamp`

## Logging Requirements

- Use structured logs (JSON) in Cloud Run.
- Never log secrets/tokens/payment sensitive data.
- Include outcome and key metadata (e.g., lock acquired, firestore version, winner driverId).

## Metrics (Examples; tighten per implementation)

- `ride.request_latency_ms`
- `ride.assignment_latency_ms`
- `ride.assignment_conflicts_per_min`
- `ride.expired_per_hour`
- `location.stale_driver_count`
- `api.error_rate_5xx` and `api.error_rate_4xx`
- `fcm.delivery_failure_rate`
- `firestore.read_count_per_session`

## SLOs (P95 targets)

From `docs/ORA_LATENCY_SLO.md`:
- Cold start to first frame < 2.5s
- Ride request T0→T6 < 900ms P95 (foreground connected-listener path)
- select→UI < 500ms P95
- GPS-to-passenger-marker < 500ms P95

## Alerts

PagerDuty priorities (examples):
- P1: assignment failure or high API error rate
- P2: SLO violations (T0→T6) or GPS stale count thresholds

## Phase 1.6 Sampling Policy

Production logging/sampling policy is now frozen in:
`docs/architecture-final/24-phase-1.6-condition-closure.md` section 12.

Notably:
- GPS accepted packets are sampled at INFO (1 in 100)
- rejected GPS packets log at WARNING
- dispatch/offer/assignment command logs are retained at INFO
- notification payloads are never fully dumped with sensitive fields

