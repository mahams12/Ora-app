# Backend Troubleshooting Playbook

**Status:** CURRENT  
**Start from the symptom.** Then open the cited files.  
**Maps:** [`N_REQUEST_FLOWS.md`](../architecture/N_REQUEST_FLOWS.md), [`BACKEND_ERROR_INDEX.md`](BACKEND_ERROR_INDEX.md), [`ORA_CURRENT_STATE.md`](../ORA_CURRENT_STATE.md)

---

## Symptom: N3 / nearby empty or 503

N3 is **IMPLEMENTED**: `GET /v1/internal/drivers/nearby` + `X-Ora-Worker-Token`.

1. Confirm worker token / `ORA_INTERNAL_WORKER_TOKEN`
2. Confirm Redis configured; 503 `DEPENDENCY_ERROR` vs healthy `200 []`
3. Confirm N2C projects into **`geo:drivers`** (homeCity **not** required)
4. Do not confuse with `GET /v1/rides/open` (M0)
5. Closure: `docs/implementation/n-series/N3-nearby-planning.md`

## Symptom: N3 Redis outage

Expect **`503 DEPENDENCY_ERROR`**, not `200` with empty candidates.

## Symptom: ride never “dispatched” / no push to drivers

N4 is **NOT IMPLEMENTED**. Architecture **FROZEN** (coordinate-primary): `docs/implementation/n-series/N4-dispatch-planning.md`.

1. Drivers discover via **M0** pull today — expected
2. N4 MVP (when built) persists invite decisions only — **no FCM wake** in N4
3. Matching input will be **pickup lat/lng → N3 `geo:drivers`** — **not** `rides.city` / homeCity
4. Do not implement until an explicit N4 implementation prompt is issued
---

## Symptom: location update returns 403

Check in order:

1. `Authorization: Bearer` Firebase ID token valid → `middleware/auth.ts`
2. User doc exists → `users/{uid}` via `rides/eligibility.ts` `loadActor`
3. `role === 'driver'` and `driverStatus === 'approved'`
4. `drivers/{uid}.availabilityState === 'online'` (N1)

Relevant files:

- `backend/auth-service/src/location/location_update_service.ts` (`assertApprovedOnlineDriver`)
- `backend/auth-service/src/drivers/driver_availability_service.ts`
- `backend/auth-service/src/rides/eligibility.ts`

Codes: `DRIVER_NOT_APPROVED`, `FORBIDDEN`, `ACCOUNT_DISABLED`

Logs: `LOCATION_UPDATE` with `errorCode`

Proof: `npm run test:phase-n1-unit-proof`, `npm run test:phase-n2a-unit-proof`

---

## Symptom: location update returns 422

### `INVALID_LOCATION`

Check (`location/validation.ts`):

- Body is object
- Finite `lat`/`lng` in range
- `accuracy` in `[0, 50]`
- `speed` in `[0, 200]`
- Non-empty `locationStreamId`, `provider`
- Integer `locationSeq >= 0`

### `STALE_LOCATION`

- `timestamp` parseable
- Within **15s past** and **5s future** of server now

### `SEQUENCE_VIOLATION`

Check Firestore `locationStreams/{docId}`:

- `streamState !== CLOSED`
- Same stream: `locationSeq > lastAcceptedSeq`
- Packet stream id not in `previousStreamIds`

Idle doc id = `driverId`; trip = `{rideId}_{driverId}`.

Proof: `scripts/run_phase_n2a_unit_proof.ts`

---

## Symptom: location accepted (200) but not in Redis

1. Process started with `REDIS_URL`? Log `redis_geo_init` `configured: true` (`src/index.ts`)
2. Redis reachable (live proof / redis-cli)
3. `drivers/{uid}.homeCity` present and non-empty after normalize
4. Key `geo:drivers:{normalizedCity}` member = driver uid
5. Key `driver:online:{uid}` exists (TTL 30s — may expire quickly)
6. Logs: `REDIS_GEO_PROJECTED` vs `REDIS_GEO_SKIP` (`missing_home_city` | `redis_not_configured` | `stale_projection`) vs `REDIS_GEO_PROJECT_FAILED`

Files: `src/redis/geo_projection.ts`, `src/redis/types.ts`

Proof: `npm run test:phase-n2c-unit-proof`; live `REDIS_URL=... npm run test:redis-geo-proof`

**Note:** HTTP 200 is correct even when Redis is skipped — N2A SoT is Firestore cursor.

---

## Symptom: driver appears in GEO but should not be “nearby”

N3 filtering **does not exist** yet. Freeze defines future gates in `N3-nearby-planning.md` §8–§9.

If something queries Redis directly today:

1. Confirm GEO membership vs intended city shard
2. Marker freshness (`driver:online` TTL 30s)
3. Firestore still `availabilityState=online` + approved
4. Busy states not filtered by any HTTP nearby API (none registered)
5. Do not confuse with M0 open rides

---

## Symptom: Redis down and a future N3 call

Per N3 freeze: **fail closed (503 class)** — must **not** return empty candidates that look like “no drivers.” No Firestore geo fallback.
---

## Symptom: driver is online but no location

| Condition | Owner |
| --------- | ----- |
| `availabilityState=online` | N1 Firestore |
| No `locationStreams` cursor / no Redis member | Client never called `/v1/location/update` **or** N2A rejected **or** N2C skipped |
| Flutter GPS | **Not implemented** |

Online ≠ projected location.

---

## Symptom: go-offline succeeds but driver remains in GEO

Trace:

```text
go-offline
→ Firestore availability offline (authoritative)
→ removeDriverOnOffline
→ ZREM geo:drivers:{city} (+ city from marker)
→ DEL driver:online:{id}
```

If Redis down: Firestore still offline; GEO stale until TTL/manual cleanup. Logs: `REDIS_GEO_OFFLINE_FAILED`.

Files: `driver_availability_service.ts`, `geo_projection.ts`

---

## Symptom: ride lifecycle regression

Check:

- States: `rides/types.ts` `RIDE_STATES`
- Gates: `rides/state_machine.ts`
- Mutations: `rides/ride_service.ts`
- Routes: `rides/routes.ts`

Proofs:

- `npm test` (rides.test.ts)
- `npm run test:ride-proof`
- Root emulator scripts `test:ride-*-firestore-*`
- Phase unit proofs `test:phase-2j` … `2n`

---

## Symptom: offer incorrectly rejected

| Check | Where |
| ----- | ----- |
| Driver approved | `eligibility.assertDriverEligible` |
| Ride offerable state | `assertOfferable` — SEARCHING / OFFERS_AVAILABLE |
| `requestVersion` match | `OFFER_STALE` |
| Ride already assigned | `ALREADY_ASSIGNED` |
| Ride search window expired | `STATE_CONFLICT` on `expiresAt` |
| Duplicate live offer | `OFFER_ALREADY_EXISTS` |
| Amount / pricing | `OFFER_AMOUNT_MISMATCH`, `FARE_OUT_OF_BOUNDS`, `PRICING_SNAPSHOT_EXPIRED` |
| Driver already `DRIVER_ASSIGNED` elsewhere | `DRIVER_NOT_ELIGIBLE` 422 |
| Idempotency key reuse different hash | `IDEMPOTENCY_KEY_REUSED` |
| Offer expired / not PENDING | `OFFER_EXPIRED`, `OFFER_NOT_SELECTABLE` |

Files: `ride_service.ts`, `offer_lifecycle.ts`, `pricing_snapshot.ts`

---

## Symptom: rating rejected

- State must be `RIDE_COMPLETED` or `RIDE_CLOSED`
- Participant only; direction server-derived
- Duplicate → `ALREADY_RATED`
- GET missing → `RATING_NOT_FOUND`

Proof: `test:phase-2n-unit-proof`, `test:ride-rating-firestore-concurrency`

---

## Symptom: internal sweeper 403/503

- Header/token `ORA_INTERNAL_WORKER_TOKEN` → `middleware/internal_worker.ts`
- Codes: `FORBIDDEN`, `INTERNAL` (misconfig)

---

## Symptom: App Check / rate limit

- `APP_CHECK_REQUIRED` / `APP_CHECK_INVALID` when `REQUIRE_APP_CHECK=true`
- `RATE_LIMITED` 429 — in-memory limiter per uid+ip

Tests: `security_phase2b.test.ts`
