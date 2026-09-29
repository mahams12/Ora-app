# N2C — Redis GEO Projection

**Status:** **IMPLEMENTED** — coordinate-primary cutover (2026-09-21)  
**Authority:** Code + [`CITY-PARTITION-STRATEGY-DECISION.md`](CITY-PARTITION-STRATEGY-DECISION.md)

## Purpose

Project **accepted** N2A location updates into Redis GEO for nearby-driver candidate generation, and remove membership on durable go-offline — without making Redis authoritative.

## Scope (coordinate-primary)

- After N2A accept: `GEOADD geo:drivers` + `SET driver:online:{driverId}` EX 30
- **homeCity is NOT required** for primary GEO membership
- Dual-write (migration/rollback): also `GEOADD geo:drivers:{city}` when `normalizeCitySlug(homeCity)` is present
- Marker may retain `city` as optional metadata
- Stale projection guard via marker `locationSeq` / `lastLocationTs` (unchanged)
- Legacy city change → `ZREM` previous `geo:drivers:{city}` (primary key unchanged)
- Go-offline → `ZREM geo:drivers` + `ZREM` known legacy city keys + `DEL` marker
- Redis failures → log + swallow (never fail HTTP accept / offline durability)

### Keys

| Key | Role |
| --- | ---- |
| `geo:drivers` | **Matching index** (coordinate-primary) |
| `geo:drivers:{city}` | Legacy dual-write only — **not** used by N3 reads |
| `driver:online:{driverId}` | TTL marker (freshness / accuracy / seq) |

## Preconditions

- N2A acceptance path (or go-offline durable transition)
- Optional `REDIS_URL` at process start (`createRedisGeoClientFromEnv`)
- `ioredis` dependency in `backend/auth-service/package.json`

## Architecture Decision

- ADR-004: Redis GEO is non-authoritative candidate optimization
- Firestore remains SoT for availability and ride state
- Partition strategy: [`CITY-PARTITION-STRATEGY-DECISION.md`](CITY-PARTITION-STRATEGY-DECISION.md) → `MOVE_TO_COORDINATE_PRIMARY`
- **No RTDB writes**

## API Contract

N2C adds **no new HTTP routes**. It is a side effect of:

- `POST /v1/location/update` → `projectAcceptedLocation`
- `POST /v1/drivers/go-offline` → `removeDriverOnOffline`

## Data Model

| Key | Type | TTL | Writer |
| --- | ---- | --- | ------ |
| `geo:drivers` | GEO / ZSET | none (membership managed) | `geoadd` / `zrem` |
| `geo:drivers:{city}` | GEO / ZSET (legacy dual-write) | none | `geoadd` / `zrem` when homeCity present |
| `driver:online:{driverId}` | String JSON marker | **30 seconds** | `set` / `del` |

Marker fields (JSON): `driverId`, `lastLocationTs`, `accuracy`, `city` (optional metadata), `locationStreamId`, `locationSeq`, `acceptedAt`.

## State / Invariants

- Projection never overrides N2A accept success
- Older seq/ts must not overwrite newer marker projection
- Offline removal is idempotent best-effort
- Missing homeCity must still project to `geo:drivers`

## Implementation Files

- `backend/auth-service/src/redis/types.ts` (`GEO_DRIVERS_KEY`)
- `backend/auth-service/src/redis/client.ts`
- `backend/auth-service/src/redis/geo_projection.ts`
- `backend/auth-service/src/redis/memory_redis.ts` (unit proofs)
- Hooks: `location_update_service.ts`, `driver_availability_service.ts`
- Boot: `src/index.ts` (`redis_geo_init`)

## Test Files

- `backend/auth-service/src/__tests__/geo_projection.test.ts`
- `backend/auth-service/scripts/run_phase_n2c_unit_proof.ts` (MemoryDb + MemoryRedis)
- `backend/auth-service/scripts/run_redis_geo_proof.ts` (live Redis)

## Proof Commands

```bash
cd backend/auth-service
npm run test:phase-n2c-unit-proof
# Live Redis (requires running Redis):
REDIS_URL=redis://127.0.0.1:6379 npm run test:redis-geo-proof
```

## Rollback

1. N3 currently reads only `geo:drivers` — re-point reader to city keys only if rolling back both N2C+N3 together.
2. Dual-write keeps legacy `geo:drivers:{city}` populated when homeCity exists until a later cleanup slice.
3. Do **not** flush Redis blindly.

## Out of scope

N4, Maps, GPS packages, Flutter, PBS import, ride create API, deleting `homeCity` / `rides.city` fields.
