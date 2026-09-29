# N2A — Location Acceptance + Durable Stream Cursor

## Purpose

Accept untrusted client GPS packets for **approved online drivers**, validate them, and advance a durable monotonic stream cursor in Firestore — without storing GPS history and without requiring Redis/RTDB for acceptance.

## Scope

- `POST /v1/location/update`
- Validation: coordinates, accuracy (≤50m), speed (≤200 km/h), timestamp freshness (±15s past / +5s future), required fields
- Firestore `locationStreams/{docId}` cursor upsert in a transaction
- Soft Pakistan bbox **warn only** (`location_soft_bbox_warn`)
- After accept: optional N2C Redis projection hook (non-authoritative; must not fail accept)

## Preconditions

- N1: `drivers/{uid}.availabilityState == online`
- `users/{uid}` role driver + `driverStatus=approved`
- Auth middleware

## Architecture Decision

- Client GPS is untrusted input (ADR-011 alignment)
- Durable acceptance = cursor in `locationStreams` (seq + stream id), **not** lat/lng persistence
- Idle doc id = `{driverId}`; trip doc id = `{rideId}_{driverId}`
- Redis/RTDB/nearby/dispatch are **out of N2A correctness**

## API Contract

### `POST /v1/location/update`

- Auth: Bearer Firebase ID token
- Body (required fields enforced in `validation.ts`):
  - `locationSeq` (non-negative integer)
  - `locationStreamId` (non-empty string)
  - `lat`, `lng`, `accuracy`, `heading`, `speed`, `provider`, `timestamp`
  - optional `rideId`, `altitude`
- Success: `200` `{ data: { driverId, mode, rideId, locationStreamId, locationSeq, acceptedAt }, ... }`
- `mode`: `idle` if no rideId, else `trip`

### Errors (location domain)

| Code | HTTP | Typical cause |
| ---- | ---: | ------------- |
| `DRIVER_NOT_APPROVED` | 403 | Not approved driver |
| `FORBIDDEN` | 403 | Not online |
| `INVALID_LOCATION` | 422 | Bad coords/accuracy/speed/fields |
| `STALE_LOCATION` | 422 | Timestamp outside window |
| `SEQUENCE_VIOLATION` | 422 | Seq/stream/closed stream rules |

## Data Model

`locationStreams/{docId}` (cursor — no lat/lng fields written by service):

- `driverId`, `activeStreamId`, `lastAcceptedSeq`, `streamState` (`ACTIVE`/`CLOSED`)
- `previousStreamIds` (bounded)
- `createdAt`, `updatedAt`, `expiresAt`
- trip mode may set `rideId`

Expires: idle ~24h sliding; trip ~7d (comment notes N2B+ cleanup later).

## State / Invariants

- Same `locationStreamId`: `locationSeq` must be **>** `lastAcceptedSeq`
- New stream replaces active; previous id recorded; late packets from previous streams rejected
- Closed stream rejects updates
- Identity = caller uid only (body cannot spoof driver)

## Implementation Files

- `backend/auth-service/src/location/routes.ts`
- `backend/auth-service/src/location/location_update_service.ts`
- `backend/auth-service/src/location/validation.ts`
- `backend/auth-service/src/location/types.ts`
- `backend/auth-service/src/location/http.ts`

## Test Files

- `backend/auth-service/scripts/run_phase_n2a_unit_proof.ts` (MemoryDb)
- Rules contract mentions `locationStreams` deny: `src/__tests__/firestore_rules_contract.test.ts`

## Proof Commands

```bash
cd backend/auth-service
npm run test:phase-n2a-unit-proof
```

## Live Proof

| Proof | Command | Result |
| ----- | ------- | ------ |
| Firestore emulator | root `npm run test:location-update-firestore` | **SCRIPT EXISTS / NOT RUN** in this documentation session |

Script explicitly asserts no Redis/RTDB env required for N2A accept.

## Security

- Rules deny client read/write on `locationStreams`
- Online + approved gates before accept

## Failure Behavior

- Validation/seq failures → 422; nothing projected
- Redis projection failure after accept → logged; HTTP still 200

## Observability / Logs

- `LOCATION_UPDATE` (routes)
- `location_soft_bbox_warn` (validation)
- After hook: `REDIS_GEO_*` (N2C)

## Known Limitations

- No Flutter GPS publisher wired
- No hard teleport/plausibility beyond soft bbox warn
- Trip mode does not verify ride assignment in N2A service (cursor only)

## Explicit Non-Goals

- RTDB `tripLocations` (N2B)
- Nearby query (N3)
- Dispatch (N4)
- Persisting GPS breadcrumbs in Firestore

## Dependencies

- N1 availability
- Optional N2C `RedisGeoProjectionService`

## Next Slice

**N2C** (projection) already implemented; product next is **N3** after freeze. **N2B** remains deferred.

## Closure Status

**IMPLEMENTED** with unit + emulator proof scripts. Live result this session: **NOT RUN**.

## Failure Entry Points

```text
HTTP 403 FORBIDDEN (must be online)
→ location_update_service.assertApprovedOnlineDriver
→ drivers/{uid}.availabilityState
→ N1 proofs

HTTP 422 INVALID_LOCATION / STALE_LOCATION
→ location/validation.ts
→ run_phase_n2a_unit_proof.ts

HTTP 422 SEQUENCE_VIOLATION
→ locationStreams cursor fields
→ location_update_service.acceptInTransaction

HTTP 200 but Redis empty
→ not an N2A failure — see N2C troubleshooting
```
