# Backend Troubleshooting Playbook

**Status:** CURRENT  
**Start from the symptom.** Then open the cited files.  
**Maps:** [`N_REQUEST_FLOWS.md`](../architecture/N_REQUEST_FLOWS.md), [`BACKEND_ERROR_INDEX.md`](BACKEND_ERROR_INDEX.md), [`ORA_CURRENT_STATE.md`](../ORA_CURRENT_STATE.md)

---

## Symptom: staging API returns 503/500 on every request (app shows "Something went wrong")

**Diagnosed 2026-10-19:** Cloud Run 503 "service not available yet" / 500 on `GET /v1/health`; `gcloud run services describe` shows `Ready: True` but zero instances can start. Cause: **GCP billing disabled on the project** — Cloud Logging shows `The request failed because billing is disabled for this project.` All API traffic AND scheduled sweeps (expire/offer/dispatch/FCM/no-show) stop. Firestore direct access (admin SDK, `e2e_ride_snapshot.ts`) may still work — a stale "live" snapshot does not mean the API is up.

Check:

```bash
curl -s https://ora-auth-service-staging-2zmxvrrs7a-uc.a.run.app/v1/health
gcloud logging read "resource.type=cloud_run_revision \
  AND resource.labels.service_name=ora-auth-service-staging" \
  --limit=10 --freshness=30m
```

Resolution is a GCP Console billing action — not a code/config fix, do not redeploy blindly.

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

N4 is **IMPLEMENTED (MVP)** — invite ledger + internal dispatch sweep; FCM wake is delivered by **D1** (`src/delivery/`). Drivers can also discover via **M0** pull (`GET /v1/rides/open`).

1. Check `outboxEvents` in Firestore — pending invite events should be `PENDING`, not silently stuck
2. Run the sweep: `POST /v1/internal/outbox/dispatch-fcm-sweep` (worker token)
3. Confirm device tokens registered: `POST .../device-tokens`
4. Matching input is **pickup lat/lng → N3 `geo:drivers`** — **not** `rides.city` / homeCity
5. Planning: `docs/implementation/n-series/N4-dispatch-planning.md`, `D1-dispatch-delivery-planning.md`

## Symptom: outbox events pile up / new dispatch notifications starved (FIXED 2026-10-14)

**Root cause:** the FCM projector's default scan could be filled by terminal `DELIVERED`/`DEAD_LETTER` backlog, starving fresh `PENDING` events.

**Fix (in `src/delivery/dispatch_fcm_projector.ts`):** scan `PENDING` events first, then spend only the leftover sweep budget reclaiming expired-lease `CLAIMED` events.

**Diagnosis / verification:**

```bash
cd backend/auth-service
npx vitest run src/__tests__/delivery_d1.test.ts   # ordering tests S1–S8
```

Evidence: `mobile/.e2e_artifacts/FCM_ORDERING_FIX_PHYSICAL_VERIFY_REPORT.json` (staging physical verify). If notifications still stall, check `delivery` sweep logs and Firestore `outboxEvents` state distribution.

## Symptom: passenger/driver not nudged on ride-state changes (NOTIF-RS-PUSH, added 2026-10-19)

The ride-state projector is implemented but **requires a redeploy + scheduler run** (staging billing still disabled at implementation time).

1. Sweep: `POST /v1/internal/outbox/ride-state-fcm-sweep` (worker token) — expect `delivered`/`retryable`/`skipped` counts; check `RS_RIDE_FCM*` logs.
2. Non-allowlisted events (`ride.created`, `ride.rating.submitted`, `ride.dispatch.wave_completed`, anything else) are deliberately skipped — verify the event type is in `RS_EVENT_TYPES` (`ride_state_types.ts`).
3. Passengers need a token on the NEW route `POST /v1/device-tokens` (role-gated `passenger`); driver tokens still live at `/v1/drivers/device-tokens`. No registered token → `SKIPPED_NO_TOKEN` (terminal, by design — pushes are best-effort hints).
4. `outboxDeliveries/{eventId}_fcm_ride_state` holds per-uid/per-token results; `DEAD_LETTER` after 10 attempts; `invalid_token` deletes the stored token.
5. If a user has BOTH passenger and driver tokens, both are sent to (union), and invalid cleanup targets the collection the token came from.

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
