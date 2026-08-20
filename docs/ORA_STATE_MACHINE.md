# ORA — Formal Ride State Machine

**Version:** 0.7.0  
**Date:** 2026-08-18  
**Product:** P2P offered-fare; dispatch ≠ assignment

---

## 1. States

| State | Code | Description |
|---|---|---|
| DRAFT | `DRAFT` | Passenger building request; not yet submitted |
| ROUTE_READY | `ROUTE_READY` | Route + fare calculated; awaiting passenger confirmation |
| REQUEST_CREATED | `REQUEST_CREATED` | Server created record; pending dispatch |
| SEARCHING | `SEARCHING` | Dispatch engine broadcasting to eligible drivers |
| OFFERS_AVAILABLE | `OFFERS_AVAILABLE` | ≥1 pending driver offer; passenger compares and selects |
| DRIVER_ASSIGNED | `DRIVER_ASSIGNED` | Passenger-selected offer committed; exactly one assigned driver; agreedFare immutable |
| DRIVER_EN_ROUTE | `DRIVER_EN_ROUTE` | Driver moving toward pickup |
| DRIVER_ARRIVED | `DRIVER_ARRIVED` | Driver at pickup location |
| RIDE_STARTED | `RIDE_STARTED` | Passenger confirmed; meter running |
| RIDE_COMPLETED | `RIDE_COMPLETED` | Driver marked destination reached; operational ride is over |
| RIDE_CLOSED | `RIDE_CLOSED` | Post-ride closure work complete; ride aggregate terminal |
| CANCELLED | `CANCELLED` | Terminal cancelled state (actor annotated) |
| EXPIRED | `EXPIRED` | No driver found within TTL |
| NO_SHOW | `NO_SHOW` | Passenger did not board within wait time |
| DRIVER_CANCELLED | `DRIVER_CANCELLED` | Driver cancelled post-assignment |
| PASSENGER_CANCELLED | `PASSENGER_CANCELLED` | Passenger cancelled post-assignment |

---

## 2. Allowed Transitions

```
DRAFT                → ROUTE_READY           (passenger; client)
ROUTE_READY          → REQUEST_CREATED       (passenger; server)
REQUEST_CREATED      → SEARCHING             (server; auto)
SEARCHING            → OFFERS_AVAILABLE      (server; on first pending offer)
OFFERS_AVAILABLE     → DRIVER_ASSIGNED       (passenger selects offer; server transaction)
SEARCHING            → DRIVER_ASSIGNED       (only if passenger selects an offer while still SEARCHING; never via driver Accept)
DRIVER_ASSIGNED      → DRIVER_EN_ROUTE       (driver; confirms navigation start)
DRIVER_EN_ROUTE      → DRIVER_ARRIVED        (server; geofence trigger OR driver tap)
DRIVER_ARRIVED       → RIDE_STARTED          (driver tap; server validates)
RIDE_STARTED         → RIDE_COMPLETED        (driver tap; server validates location)
RIDE_COMPLETED       → RIDE_CLOSED           (server; post-ride closure complete)

-- Cancellation paths --
SEARCHING            → CANCELLED             (passenger or server timeout)
OFFERS_AVAILABLE     → CANCELLED             (passenger or EXPIRED)
SEARCHING            → EXPIRED               (server; TTL exceeded)
OFFERS_AVAILABLE     → EXPIRED               (server; TTL exceeded)
DRIVER_ASSIGNED      → DRIVER_CANCELLED      (driver; within cancellation policy)
DRIVER_ASSIGNED      → PASSENGER_CANCELLED   (passenger; within cancellation policy)
DRIVER_EN_ROUTE      → DRIVER_CANCELLED      (driver; penalty may apply)
DRIVER_EN_ROUTE      → PASSENGER_CANCELLED   (passenger; cancellation fee may apply)
DRIVER_ARRIVED       → NO_SHOW               (server; wait timer exceeded)
DRIVER_ARRIVED       → PASSENGER_CANCELLED   (passenger explicit cancel)
```

## 3. Forbidden Transitions

```
RIDE_CLOSED    → ANY              (terminal; immutable)
CANCELLED      → ANY              (terminal; immutable)
EXPIRED        → ANY              (terminal; immutable)
NO_SHOW        → ANY              (terminal; except admin correction)
RIDE_STARTED   → DRIVER_ASSIGNED  (cannot go backward)
DRAFT          → DRIVER_ASSIGNED  (must go through REQUEST_CREATED)
Any Client     → DRIVER_ASSIGNED  (server ONLY)
Any Client     → RIDE_CLOSED      (server ONLY)
```

---

## 4. Transition Authority

| Transition | Actor | Mechanism |
|---|---|---|
| DRAFT → ROUTE_READY | Client | Local state; no server call |
| ROUTE_READY → REQUEST_CREATED | Passenger → Server | POST /rides API call |
| REQUEST_CREATED → SEARCHING | Server (auto) | Immediate upon creation |
| SEARCHING / OFFERS_AVAILABLE → DRIVER_ASSIGNED | Passenger select-offer → Server | Firestore transaction on selected offer |
| DRIVER_ASSIGNED → DRIVER_EN_ROUTE | Driver client | POST /rides/{id}/en-route or status route |
| DRIVER_EN_ROUTE → DRIVER_ARRIVED | Server (geofence) or Driver | Geofence OR driver tap |
| DRIVER_ARRIVED → RIDE_STARTED | Driver client | PATCH; server validates proximity |
| RIDE_STARTED → RIDE_COMPLETED | Driver client | PATCH; server validates location |
| RIDE_COMPLETED → RIDE_CLOSED | Server | Closure workflow completes; payment lifecycle tracked separately |
| Any → EXPIRED | Server (Cloud Scheduler) | Scheduled sweeper |
| Any → NO_SHOW | Server (Cloud Scheduler) | Timer after DRIVER_ARRIVED |

---

## 5. Ride Document Version Field

Every ride document carries:

```json
{
  "rideId": "string",
  "version": 42,
  "state": "DRIVER_EN_ROUTE",
  "stateHistory": [
    {
      "state": "DRIVER_EN_ROUTE",
      "timestamp": "2026-08-18T07:30:00Z",
      "actor": "driver:uid123",
      "eventId": "evt_abc123",
      "transitionIndex": 5
    }
  ],
  "updatedAt": "2026-08-18T07:30:00Z"
}
```

- `version` increments monotonically on every ride-state change.
- Clients receiving an event with `version ≤ localVersion` MUST discard it as stale.
- Transitions include `expectedVersion` for optimistic concurrency (Firestore transaction reads current, compares, writes only if version matches).

---

## 6. Separate Payment Lifecycle

Ride state is **not** the payment state machine.

Payment is a separate aggregate linked by `rideId`.

### Payment states

```text
NOT_REQUIRED
PENDING
AUTHORIZED
CAPTURE_PENDING
CAPTURED
FAILED
REFUND_PENDING
REFUNDED
RECONCILIATION_REQUIRED
```

### Relationship

- `RIDE_COMPLETED` creates or updates the payment obligation from **agreedFare**, never from recommended fare.
- Cash rides may move payment from `PENDING` to `CAPTURED` after driver confirmation and reconciliation checks.
- Digital rides may remain in `PENDING` / `CAPTURE_PENDING` after the ride is already `RIDE_COMPLETED`.
- Provider callback success does not mutate ride history backward; it advances the payment aggregate only.

---

## 7. Idempotency

- Every state-change API call carries `idempotencyKey` = `{rideId}:{fromState}:{toState}:{clientNonce}`.
- Server returns `200 OK` with current state if the transition already completed (idempotent success).
- Server returns `409 Conflict` if a different transition won.
- Retry-safe: driver can safely re-submit accept if network dropped.

---

## 8. Timeout Definitions

| State | Timeout | Server Action |
|---|---|---|
| SEARCHING | 5 minutes | → EXPIRED; notify passenger |
| OFFERS_AVAILABLE | 3 minutes | → EXPIRED if passenger does not select |
| DRIVER_ASSIGNED (driver no movement) | 2 minutes | Alert; 5 min → DRIVER_CANCELLED |
| DRIVER_ARRIVED (waiting for passenger) | 5 minutes | → NO_SHOW |
---

## 9. Reconnect / Offline Recovery

| Scenario | Behavior |
|---|---|
| Driver disconnects during SEARCHING | RTDB presence clears; driver marked temporarily offline; request not cancelled unless TTL expires |
| Driver reconnects | RTDB presence restored; driver re-enters eligible pool; if ride still SEARCHING and driver eligible, they may receive it again |
| Passenger disconnects during DRIVER_EN_ROUTE | Ride continues; passenger sees current state on reconnect via Firestore snapshot |
| Both offline, server timeout | Server transitions per TTL rules; Firestore is source of truth; both read correct state on reconnect |
| Duplicate driver offer after reconnect | Idempotent offer create; does not assign |
| Duplicate passenger select after reconnect | Same offer replays assignment; other offer is conflict |

---

## 10. Rollback / Recovery

- Terminal states (`RIDE_CLOSED`, `CANCELLED`, `EXPIRED`, `NO_SHOW`, `DRIVER_CANCELLED`, `PASSENGER_CANCELLED`) are IMMUTABLE. No rollback.
- Pre-terminal states: admin-only `force_transition` API with audit log entry.
- Payment failures are handled on the payment aggregate, not by re-opening the ride lifecycle.
- If server crashes mid-transaction: Firestore atomic transaction guarantees either committed or not; no partial write.
- Redis lock TTL ensures lock is released even if Cloud Run instance dies (30-second lock TTL).
