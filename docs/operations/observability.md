# ORA — Observability Design

## Correlation IDs

Every request carries and propagates:

| ID | Source | Propagated To |
|---|---|---|
| `requestId` | Client generates UUID | Cloud Run logs, Firestore events |
| `rideId` | Server generates on ride create | All ride-related logs |
| `passengerId` | Firebase Auth UID | All passenger actions |
| `driverId` | Firebase Auth UID | All driver actions |
| `eventId` | Server generates per event | rideEvents collection |
| `operationId` | Server generates per operation | Spans |

## Latency Timeline (T0–T11)

Every ride request logs these timestamps with correlation IDs:

| Marker | Event | Logged By |
|---|---|---|
| T0 | Passenger taps "Confirm" | Flutter: `Analytics.logEvent('ride_confirm_tap', {requestId})` |
| T1 | App sends POST /rides | Flutter: outbound request timestamp |
| T2 | Server receives request | Cloud Run: request received |
| T3 | Ride document created in Firestore | Server: Firestore write ack |
| T4 | Driver candidate list from Redis | Server: Redis GEORADIUS response |
| T5 | RTDB + FCM dispatched | Server: dispatch complete |
| T6 | Driver receives request | Driver app: RTDB listener fire |
| T7 | Driver sends POST /rides/{id}/offers | Driver app: outbound request |
| T7b | Passenger sends POST /rides/{id}/offers/{offerId}/select | Passenger app: outbound request |
| T8 | Server receives select | Cloud Run: request received |
| T9 | Atomic assignment complete | Server: Firestore txn committed |
| T10 | Assignment signal in RTDB | Server: RTDB write ack |
| T11 | Passenger UI updated | Passenger app: RTDB listener fire + widget rebuild |

Derived metrics:
- `T6 - T0` = total request delivery latency (target < 900ms)
- select→UI = assignment propagation (target < 500ms)
- T0→T11 is not an assignment SLO; passengers may compare offers for minutes

## Structured Log Format

All Cloud Run logs use JSON with this schema:

```json
{
  "severity": "INFO",
  "timestamp": "2026-08-18T07:30:00.000Z",
  "requestId": "req_abc123",
  "rideId": "ride_abc",
  "driverId": "drv_456",
  "passengerId": "uid_xyz",
  "service": "ride-engine",
  "operation": "accept_ride",
  "duration_ms": 142,
  "outcome": "SUCCESS",
  "meta": {
    "lockAcquired": true,
    "firestoreVersion": 6,
    "candidatesGenerated": 28,
    "winnerDriverId": "drv_456"
  }
}
```

No `debugPrint` in production code. All logging via structured logger.

## Key Metrics (Cloud Monitoring)

| Metric | Alert Threshold | Dashboard |
|---|---|---|
| `ride.request_latency_ms` | P95 > 2000 | Ops Dashboard |
| `ride.assignment_latency_ms` | P95 > 1000 | Ops Dashboard |
| `ride.assignment_conflicts_per_min` | > 50 (indicates contention) | Race Condition Dashboard |
| `ride.expired_per_hour` | > 20% of creations | Dispatch Health |
| `location.stale_driver_count` | > 10% of online drivers | GPS Health |
| `api.error_rate_5xx` | > 1% | API Health |
| `api.error_rate_4xx` | > 10% | API Health |
| `redis.lock_timeout_count` | > 5/min | Redis Health |
| `fcm.delivery_failure_rate` | > 5% | Notification Health |
| `firestore.read_count_per_session` | P95 > 50 | Cost Dashboard |

## Alerting (PagerDuty Integration)

| Priority | Condition | Response |
|---|---|---|
| P1 (immediate) | Assignment failure rate > 5%; API error rate > 5% | On-call engineer |
| P2 (urgent) | T0→T6 > 2s P95; GPS stale > 15% | Within 30 min |
| P3 (normal) | Cold start > 5s P95; Firestore reads trending up | Next business day |
| P4 (informational) | New error code seen in logs | Auto-ticket |

## Dashboards

### Ops Dashboard
- Request volume (rides/min)
- Assignment success rate
- Active trips count
- Online driver count per city
- Error rate breakdown by code

### Latency Dashboard
- T0→T6 heatmap
- T6→T11 heatmap
- API P50/P95/P99 per endpoint
- Redis operation latency

### Financial Dashboard
- Revenue per hour (city)
- Average fare
- Cancellation rate
- Payout pending amount

### GPS Health Dashboard
- Stale driver % per city
- GPS accuracy distribution
- Location rejection rate
- Out-of-order packet rate
