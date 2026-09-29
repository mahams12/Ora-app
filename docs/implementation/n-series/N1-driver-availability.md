# N1 — Driver Availability (go-online / go-offline)

## Purpose

Persist durable driver marketplace availability so location updates and future nearby candidacy have an authoritative online/offline gate.

## Scope

- `POST /v1/drivers/go-online`
- `POST /v1/drivers/go-offline`
- Firestore `drivers/{driverId}.availabilityState` ∈ `{ offline, online }`
- Approval gate via `users/{uid}` (`role=driver`, `driverStatus=approved`)
- On go-offline: best-effort N2C Redis GEO cleanup (if geo projection injected)

## Preconditions

- Auth middleware (Firebase ID token)
- Firestore Admin access
- User profile exists (`POST /v1/auth/register`)

## Architecture Decision

- **Authoritative availability:** Firestore `drivers.availabilityState` (see ADR-aligned SoT docs / [`DATA_OWNERSHIP.md`](../../architecture/DATA_OWNERSHIP.md))
- Redis / RTDB are **not** required for N1 correctness
- RTDB presence is **not** written (N2B deferred)

## API Contract

### `POST /v1/drivers/go-online`

- Auth: Bearer Firebase ID token (+ optional App Check)
- Body: `{}` (no client-supplied driverId)
- Success: `200` `{ data: { driverId, availabilityState: "online" }, requestId, timestamp }`
- Errors: `401 UNAUTHENTICATED`, `403 DRIVER_NOT_APPROVED` / `FORBIDDEN` / `ACCOUNT_DISABLED`, `429 RATE_LIMITED`

### `POST /v1/drivers/go-offline`

- Same auth
- Success: `200` with `availabilityState: "offline"`
- After durable transition: `RedisGeoProjectionService.removeDriverOnOffline` (best-effort)

## Data Model

`drivers/{driverId}` fields touched:

- `availabilityState`
- `updatedAt`
- `lastOnlineAt` (on transition to online)
- create path may set `driverId`, `userId`, `createdAt` if doc missing

`homeCity` is **read** on offline for GEO cleanup; N1 does not define a writer for `homeCity`.

## State / Invariants

- Missing driver doc treated as offline until go-online creates/updates it
- Idempotent: already at target → no-op success
- Identity always `req.caller.uid` — never body `driverId`

## Implementation Files

- `backend/auth-service/src/drivers/routes.ts`
- `backend/auth-service/src/drivers/driver_availability_service.ts`
- `backend/auth-service/src/drivers/types.ts`
- `backend/auth-service/src/drivers/http.ts`
- Wired in `backend/auth-service/src/app.ts` under `/v1/drivers`

## Test Files

- `backend/auth-service/src/__tests__/driver_availability.test.ts`
- `backend/auth-service/scripts/run_phase_n1_unit_proof.ts`

## Proof Commands

```bash
cd backend/auth-service
npm run test:phase-n1-unit-proof
npm test -- src/__tests__/driver_availability.test.ts
```

## Live Proof

| Proof | Command | Result |
| ----- | ------- | ------ |
| Firestore emulator | From repo root: `npm run test:driver-availability-firestore` | **SCRIPT EXISTS / NOT RUN** in this documentation session |

## Security

- Firestore rules: `match /drivers/{id}` deny all client access — Admin SDK only
- Approved-driver gate before mutation

## Failure Behavior

- Actor load / approval failures → 403 domain errors
- Redis offline cleanup failures are swallowed by N2C (availability still offline in Firestore)

## Observability / Logs

- `DRIVER_GO_ONLINE` / `DRIVER_GO_OFFLINE` (`logSafe` in routes)
- Redis: `REDIS_GEO_OFFLINE_*` on cleanup path

## Known Limitations

- No Flutter client wiring for go-online/offline found under `mobile/lib`
- No busy/assigned availability substates
- `homeCity` may be absent → GEO cleanup may only delete marker / known cities

## Explicit Non-Goals

- Location updates (N2A)
- Redis GEOADD (N2C on location path)
- RTDB presence (N2B)
- Nearby query (N3)
- Dispatch (N4)

## Dependencies

- Auth + users profile
- Optional: Redis projection service injected at process boot

## Next Slice

**N2A** — `POST /v1/location/update` (requires online + approved)

## Closure Status

**IMPLEMENTED** in code with unit + emulator proof scripts. Live emulator result for this doc session: **NOT RUN**.

## Failure Entry Points

```text
HTTP 403 DRIVER_NOT_APPROVED
→ driver_availability_service.loadApprovedDriver
→ users/{uid}.role / driverStatus
→ test: driver_availability.test.ts / run_phase_n1_unit_proof.ts

HTTP 200 but still "offline" in product UI
→ confirm API response availabilityState
→ Flutter may not call this endpoint yet
```
