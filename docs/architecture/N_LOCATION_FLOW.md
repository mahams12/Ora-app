# N-Series Location Flow

**Status:** CURRENT  
**Code authority:** `backend/auth-service/src/{location,drivers,redis}/**`  
**Snapshot:** [`docs/ORA_CURRENT_STATE.md`](../ORA_CURRENT_STATE.md)

---

## End-to-end pipeline

```text
Driver device GPS
  |  FUTURE — Flutter geolocator / publisher NOT IMPLEMENTED
  v
POST /v1/location/update
  |  IMPLEMENTED
  v
N2A — validation + Firestore locationStreams cursor
  |  IMPLEMENTED
  +------------------+
  |                  |
  v                  v
N2C Redis GEO      N2B RTDB tripLocations
  IMPLEMENTED        DEFERRED / NOT IMPLEMENTED
  (optional Redis)
  |
  v
N3 nearby candidates (GEORADIUS/GEOSEARCH + HTTP)
  NOT IMPLEMENTED
  |
  v
N4 dispatch / matching waves
  NOT IMPLEMENTED / PLANNED
```

---

## Split after N2A (actual vs deferred)

```text
N2A accept (Firestore cursor)     IMPLEMENTED
 |
 +---- N2C → geo:drivers (+ legacy city dual-write) + driver:online:{id}     IMPLEMENTED
 |
 +---- N2B → RTDB tripLocations / driverPresence         DEFERRED
```

Do **not** imply N2B exists in code. Comments in `location_update_service.ts` mention “N2B+” only as future cleanup context.

---

## Layer labels

| Layer | Label | Notes |
| ----- | ----- | ----- |
| Flutter GPS → API | **FUTURE / NOT IMPLEMENTED** | No geolocator dependency; no client call found |
| `POST /v1/location/update` | **IMPLEMENTED** | `location/routes.ts` |
| N2A validation + cursor | **IMPLEMENTED** | `validation.ts`, `location_update_service.ts` |
| N2C GEO projection | **IMPLEMENTED** | `geo:drivers` (+ legacy dual-write); homeCity **not** required |
| N2B RTDB | **DEFERRED / NOT IMPLEMENTED** | Docs/ADR target only |
| N3 nearby | **IMPLEMENTED** | `GET /v1/internal/drivers/nearby` — lat/lng; city not required — [`N3-nearby-planning.md`](../implementation/n-series/N3-nearby-planning.md) |
| N4 dispatch | **NOT IMPLEMENTED** — **FROZEN (coordinate-primary)** | [`N4-dispatch-planning.md`](../implementation/n-series/N4-dispatch-planning.md) |

---

## Parallel marketplace path (not GEO)

```text
GET /v1/rides/open     IMPLEMENTED (M0)
  → chronological Firestore open rides
  → NOT nearby drivers
```

---

## Availability gate (N1)

```text
approved driver
  → POST /v1/drivers/go-online     IMPLEMENTED
  → availabilityState=online
  → location updates allowed
  → POST /v1/drivers/go-offline    IMPLEMENTED
       → availabilityState=offline
       → N2C ZREM best-effort
```

---

## Failure mental model

| Observation | Owning layer |
| ----------- | ------------ |
| 403 not approved / offline | N1 + actor gate |
| 422 invalid/stale/seq | N2A |
| 200 but empty Redis | N2C config / homeCity / Redis down |
| Driver not in “nearby” UI | Flutter still on M0 open rides, or D7 `homeCity`/Redis empty, or worker not calling N3 |

---

## Related docs

- [`N_REQUEST_FLOWS.md`](N_REQUEST_FLOWS.md)
- [`implementation/n-series/N2A-location-acceptance.md`](../implementation/n-series/N2A-location-acceptance.md)
- [`implementation/n-series/N2C-redis-geo.md`](../implementation/n-series/N2C-redis-geo.md)
- [`diagnostics/BACKEND_TROUBLESHOOTING.md`](../diagnostics/BACKEND_TROUBLESHOOTING.md)
