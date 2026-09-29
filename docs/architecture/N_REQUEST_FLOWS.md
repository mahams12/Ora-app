# N-Series / Backend Request Flows

**Status:** CURRENT  
**Goal:** Trace HTTP → service → Firestore/Redis for diagnosis.  
**App entry:** `backend/auth-service/src/app.ts` → `src/index.ts`

---

## Location update

```text
HTTP POST /v1/location/update
→ createAuthMiddleware (Firebase token, optional App Check)
→ rate limit
→ location/routes.ts
→ LocationUpdateService.update
→ loadActor + approved driver + availabilityState==online
→ parseAndValidateLocationBody (N2A)
→ Firestore transaction on locationStreams/{idle|trip doc}
→ RedisGeoProjectionService.projectAcceptedLocation (N2C, best-effort)
→ 200 LocationUpdateSnapshot
```

| Concern | Detail |
| ------- | ------ |
| Route | `src/location/routes.ts` |
| Service | `src/location/location_update_service.ts` |
| Validation | `src/location/validation.ts` |
| Authoritative state | `locationStreams` cursor (not lat/lng) |
| Projection | Redis GEO + online marker |
| Logs | `LOCATION_UPDATE`, `location_soft_bbox_warn`, `REDIS_GEO_*` |
| Failure | 403/422 before write; Redis errors after accept do not change HTTP |
| Proof | `scripts/run_phase_n2a_unit_proof.ts`, `run_phase_n2c_unit_proof.ts`, root `test:location-update-firestore` |

**Symptom hook:** “200 but not nearby” → N2C keys / N3 filters / homeCity — see troubleshooting.

---

## Go online

```text
HTTP POST /v1/drivers/go-online
→ auth + rate limit
→ drivers/routes.ts
→ DriverAvailabilityService.goOnline
→ loadApprovedDriver (users role+driverStatus)
→ Firestore txn drivers/{uid}.availabilityState=online
→ 200 snapshot
```

| Concern | Detail |
| ------- | ------ |
| Authoritative | Firestore `availabilityState` |
| Redis | **Not** written on go-online (GEO waits for location update) |
| Logs | `DRIVER_GO_ONLINE` |
| Proof | `run_phase_n1_unit_proof.ts`, `driver_availability.test.ts`, `test:driver-availability-firestore` |

---

## Go offline

```text
HTTP POST /v1/drivers/go-offline
→ auth + rate limit
→ DriverAvailabilityService.goOffline
→ read homeCity
→ Firestore txn availabilityState=offline
→ RedisGeoProjectionService.removeDriverOnOffline (ZREM + DEL marker)
→ 200 snapshot
```

| Concern | Detail |
| ------- | ------ |
| Authoritative | Firestore offline |
| Projection cleanup | Best-effort Redis |
| Logs | `DRIVER_GO_OFFLINE`, `REDIS_GEO_OFFLINE_*` |
| Proof | N1 + N2C unit proofs |

---

## Open ride marketplace (M0 — not GEO)

```text
HTTP GET /v1/rides/open
→ auth + rate limit
→ rides/routes.ts
→ RideService.listOpenRides
→ assertDriverEligible
→ Firestore: assignedDriverId==null, state in SEARCHING|OFFERS_AVAILABLE
→ orderBy createdAt desc, rideId desc + cursor
→ publicOpenRide DTO
→ 200
```

| Concern | Detail |
| ------- | ------ |
| Source | `rides/open_discovery_query.ts`, `ride_service.listOpenRides` |
| Authoritative | Firestore `rides` |
| Redis | none |
| Logs | `RIDE_OPEN_DISCOVERY` |
| Proof | `open_discovery.test.ts`, `run_phase_m0_unit_proof.ts`, `test:ride-open-discovery-firestore-queries` |

---

## Ride offer create

```text
HTTP POST /v1/rides/:rideId/offers
→ auth + Idempotency-Key
→ RideService.createOffer
→ assertDriverEligible
→ txn: idempotency + ride state offerable + requestVersion + not already assigned
→ block if driver has another ride in DRIVER_ASSIGNED
→ pricing snapshot bounds
→ write rideOffers + maybe SEARCHING→OFFERS_AVAILABLE
→ outbox ride.offer.received (PENDING)
→ 201/200 replay
```

| Concern | Detail |
| ------- | ------ |
| Files | `rides/routes.ts`, `ride_service.ts`, `offer_lifecycle.ts`, `pricing_snapshot.ts` |
| Authoritative | `rides` + `rideOffers` + `idempotencyRecords` |
| Logs | `ride_offer_create_failed` on error |
| Proof | `rides.test.ts`, offer create concurrency scripts |

---

## Offer select / assignment

```text
HTTP POST /v1/rides/:rideId/offers/:offerId/select
→ passenger auth + Idempotency-Key
→ RideService.selectOffer
→ txn assignment barrier (assignedDriverId + state)
→ supersede sibling offers (bounded)
→ outbox ride.offer.selected + ride.assigned
```

Authoritative winner: Firestore ride fields (ADR-003). Redis never assigns.

---

## Ratings (2N)

```text
HTTP POST /v1/rides/:rideId/ratings
→ participant auth + Idempotency-Key + { stars }
→ derive direction server-side
→ eligible RIDE_COMPLETED|RIDE_CLOSED
→ create ratings/{rideId}_{ratingType} immutable
→ outbox ride.rating.submitted
→ ride document unchanged
```

---

## Internal sweepers

Worker token: `ORA_INTERNAL_WORKER_TOKEN` via `middleware/internal_worker.ts`.

| Route | Purpose | Log |
| ----- | ------- | --- |
| `POST /v1/internal/rides/expire-sweep` | 2J ride TTL | `RIDE_EXPIRE_SWEEP` |
| `POST /v1/internal/rides/offer-expire-sweep` | 2K offer TTL | `RIDE_OFFER_EXPIRE_SWEEP` |
| `POST /v1/internal/rides/no-show-sweep` | 2M | `RIDE_NO_SHOW_SWEEP` |
| `GET /v1/internal/drivers/nearby` | N3 candidates | `N3_NEARBY` |

No dispatch/wave route yet — see N4 freeze.

---

## Ride create (city metadata)

```text
HTTP POST /v1/rides
→ body.city required (current API)
→ normalizeCitySlug(city)
→ store rides.city
→ publicRide includes city
```

Also requires passenger-confirmed **pickup/destination lat/lng** and a **server-issued** `pricingSnapshotId` (fixture seeds are tests only). Live estimate path is **not implemented** — freeze: [`phase-4-5-location-pricing-decision.md`](../implementation/phase-4-5-location-pricing-decision.md).

**Matching note:** N3/N4 use **pickup lat/lng → `geo:drivers`**. `rides.city` is not the spatial matching gate ([`N4-dispatch-planning.md`](../implementation/n-series/N4-dispatch-planning.md)).

Backend: [`RIDE-CITY-SCHEMA.md`](../implementation/n-series/RIDE-CITY-SCHEMA.md).  
Pakistan-wide city model: [`PAKISTAN-CITY-ARCHITECTURE.md`](../implementation/n-series/PAKISTAN-CITY-ARCHITECTURE.md) (catalog/API/selector not built).  
Flutter: no city source yet.

---

## Auth bootstrap

| Route | Service |
| ----- | ------- |
| `POST /v1/auth/register` | `services/users.ts` |
| `GET /v1/auth/me` | users |
| `PATCH /v1/auth/profile` | `services/profile.ts` / display_name |

---

## Reading order for “location 200 but not nearby”

1. Confirm N1 online + N2A 200 (`LOCATION_UPDATE`)
2. Confirm Redis configured (`redis_geo_init`)
3. Confirm projection into **`geo:drivers`** (`REDIS_GEO_PROJECTED` vs skip/fail) — homeCity **not** required
4. Confirm N3 returns candidates (`GET /v1/internal/drivers/nearby` with lat/lng) or explain filter drops
5. Confirm client is not expecting M0 open rides to mean GEO

---

## N3 nearby (IMPLEMENTED)

See [`docs/implementation/n-series/N3-nearby-planning.md`](../implementation/n-series/N3-nearby-planning.md).

```text
GET /v1/internal/drivers/nearby + X-Ora-Worker-Token
→ validate lat+lng+radiusKm+limit (city optional / ignored for matching)
→ NearbyDriversService.findNearby
→ GEORADIUS geo:drivers … COUNT 100
→ driver:online marker (≤15s, accuracy≤50)
→ Firestore users + drivers + busy rides
→ internal candidate DTO
```

Redis down → `503 DEPENDENCY_ERROR` (not empty 200).

---

## N4 dispatch waves (NOT IMPLEMENTED — FROZEN)

See [`docs/implementation/n-series/N4-dispatch-planning.md`](../implementation/n-series/N4-dispatch-planning.md).

```text
POST /v1/internal/rides/dispatch-sweep  (or .../:rideId/dispatch-tick)
→ ride dispatchable? (pickup lat/lng; not city-gated)
→ NearbyDriversService.findNearby({ lat, lng, radiusKm: 10 }) → geo:drivers
→ create-once rideDispatchWaves/{rideId}_w{n} (5|10|15); dedupe across waves
→ update ride dispatchWave / dispatchNextAt (+5s)
→ drivers still discover via M0; createOffer / selectOffer unchanged
```

Matching prerequisite: **pickup coordinates** + N3. Delivery wake-up: later slice.  
`rides.city` / `homeCity` / PBS: **not** matching prerequisites.