# ORA — Backend Architecture

## Services

### 1. Ride Engine (Cloud Run)
Primary service. Handles all ride lifecycle operations.

**Endpoints:**
- `POST /v1/rides` — create ride request (passenger offer; dispatch starts)
- `GET /v1/rides/:id` — get ride state
- `POST /v1/rides/:id/offers` — driver accept or counter (creates pending offer; does **not** assign)
- `POST /v1/rides/:id/offers/:offerId/select` — passenger selects offer (assignment)
- `PATCH /v1/rides/:id/status` — assigned-driver status update
- `POST /v1/rides/:id/cancel` — cancel ride

**Internal logic:**
- Validates Firebase JWT + App Check on every request
- All ride state transitions go through this service
- May call Redis for contention reduction
- Calls Firestore via Admin SDK for authoritative conditional transactions
- Writes durable outbox records in the same transaction as important state changes
- Publishes events to Pub/Sub asynchronously from the outbox publisher
- Calls Location Service for pickup proximity validation

### 2. Pricing Service (Cloud Run)
Handles fare estimation and pricing rule management.

**Endpoints:**
- `POST /v1/pricing/estimate` — calculate fare for route
- `GET /v1/pricing/rules` — fetch current rules (cached)
- `GET /v1/pricing/snapshot/:rideId` — get fare snapshot

**Internal logic:**
- Calls Google Routes API for distance + duration
- Applies zone/category/demand multipliers
- Writes pricingSnapshot to Firestore (immutable)
- Does NOT accept fare recalculation after ride creation

### 3. Location Service (Cloud Run)
Handles driver GPS updates and proximity validation.

**Endpoints:**
- `POST /v1/location/update` — driver GPS update
- `GET /v1/location/nearby` — get nearby drivers (internal use)

**Internal logic:**
- Validates accuracy + speed plausibility
- Applies sequence number check (reject out-of-order)
- Updates Redis GEO index (`GEOADD`)
- Writes to RTDB `tripLocations/{rideId}` (active trips only)
- Rejects if accuracy > 50m or age > 15s

### 4. Notification Dispatcher (Cloud Run / Pub/Sub Consumer)
Receives Pub/Sub events and sends FCM messages.

**Consumed topics:**
- `ride.created` → notify nearby drivers
- `ride.assigned` → notify passenger + losing drivers
- `ride.cancelled` → notify affected parties
- `ride.completed` → send receipt
- `driver.arrived` → notify passenger

## Request Authentication Flow

```
Client request
  → TLS termination at Cloud Load Balancer
  → Cloud Armor (rate limit, WAF)
  → Cloud Run
      → verify App Check header (firebase-admin)
      → verify Firebase ID token (firebase-admin)
      → extract uid + role from token
      → authorize: is uid allowed to perform this operation on this resource?
      → proceed to business logic
```

## Error Response Format

```json
{
  "error": {
    "code": "ALREADY_ASSIGNED",
    "message": "This ride already has an assigned driver.",
    "requestId": "req_abc123",
    "timestamp": "2026-08-18T07:30:00Z"
  }
}
```

Standard HTTP status codes:
- `200` — success
- `201` — created
- `400` — bad request (validation failure)
- `401` — unauthenticated
- `403` — unauthorized (authenticated but not permitted)
- `404` — not found
- `409` — conflict (already assigned, version, or state)
- `422` — unprocessable (business rule violation)
- `429` — rate limited
- `500` — server error

## Idempotency Key Handling

```
POST /v1/rides/:id/offers
Header: Idempotency-Key: {rideId}:offer:{driverId}:{nonce}

Passenger select:
POST /v1/rides/:id/offers/:offerId/select
Header: Idempotency-Key: {rideId}:select:{passengerId}:{nonce}

Server behavior:
1. Check durable idempotency record keyed by actor + operation + resource + idempotency key
2. If same key + same requestHash + completed result exists: replay stored response
3. If same key + different requestHash: reject with 409 IDEMPOTENCY_KEY_REUSED
4. If pending: return 202 or block briefly then replay final result
5. If not present: create PENDING record, process, then persist responseSnapshot
```

## Cloud Run Configuration

```yaml
# ride-engine service
minInstances: 2          # prevent cold starts
maxInstances: 100
memory: 512Mi
cpu: 1
concurrency: 80
timeoutSeconds: 30
```

## Redis Usage Patterns

```
# GEO index for driver proximity
GEOADD geo:drivers:lahore {lng} {lat} {driverId}
GEORADIUS geo:drivers:lahore {pickupLng} {pickupLat} 10 km ASC COUNT 30

# Assignment contention lock (optional, 30-second TTL)
SET lock:ride:{rideId} {driverId} NX EX 30

# Idempotency cache hint
SET idempotency:{key} {result_json} EX 86400

# Offer deduplication (prevent driver sending multiple offers)
SET offer:dedup:{rideId}:{driverId} 1 NX EX 300

# Driver online status (backup to RTDB)
SET driver:online:{driverId} {timestamp} EX 30
```

## Pub/Sub Topics

| Topic | Producer | Consumer | Purpose |
|---|---|---|---|
| `ride.created` | Ride Engine | Notification Dispatcher | Notify nearby drivers |
| `ride.assigned` | Ride Engine | Notification Dispatcher | Notify passenger + losers |
| `ride.state_changed` | Ride Engine | Analytics Sink | Analytics pipeline |
| `ride.completed` | Ride Engine | Notification Dispatcher, Payment Service | Receipt + payment trigger |
| `driver.location_updated` | Location Service | Analytics Sink | Location analytics |
| `payment.completed` | Payment Service | Notification Dispatcher | Payment confirmation |
| `payment.failed` | Payment Service | Ride Engine | Trigger fallback |

## Durable Outbox

Important state changes are not treated as atomic with Pub/Sub or RTDB.

Required flow:

1. Firestore transaction updates business aggregate.
2. Same transaction writes `outboxEvents/{eventId}`.
3. Outbox publisher retries Pub/Sub publication with backoff.
4. RTDB projectors and FCM dispatchers consume idempotently.
