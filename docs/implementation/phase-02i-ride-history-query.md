# Phase 2I — Ride History / Query Read Slice

**Status:** CLOSED  
**Date:** 2026-09-09  
**Architecture:** `docs/implementation/phase-02i-architecture-investigation.md`

---

## 1. Scope

Implemented authenticated **`GET /v1/rides`** against existing **`rides/{rideId}`** only:

- passenger ownership filter (`passengerId == uid`)
- driver ownership filter (`assignedDriverId == uid`)
- `limit` / opaque cursor / `status` / `serviceType`
- keyset pagination (`createdAt DESC`, `rideId DESC`)
- composite Firestore indexes
- `publicRide()` list items
- Flutter domain/data list support
- emulator query verification harness

No `rideHistory` collection. No UI. No payments/Maps/RTDB/Redis/FCM/ratings.

---

## 2. Architecture basis

Locked investigation: sole source of truth remains `rides/{rideId}`; backend Admin SDK is the only query authority; cursor keyset; no transactions on reads.

---

## 3. Files changed

| File | Change |
|------|--------|
| `backend/auth-service/src/rides/list_query.ts` | **New** — parse query, cursor encode/decode + owner binding |
| `backend/auth-service/src/rides/ride_service.ts` | `listRides` |
| `backend/auth-service/src/rides/routes.ts` | `GET /` before `GET /:rideId`; `RIDE_LIST` logs |
| `backend/auth-service/src/__tests__/helpers/memory_db.ts` | `in`, `orderBy`, `startAfter` for list tests |
| `backend/auth-service/src/__tests__/rides.test.ts` | Phase 2I matrix |
| `backend/auth-service/scripts/run_ride_list_firestore_queries.ts` | **New** live query harness |
| `backend/auth-service/package.json` | `test:ride-list-firestore-queries` (full esbuild bundle) |
| `package.json` | root emulator wrapper script |
| `firestore.indexes.json` | 8 ride list composites; keep `assignedDriverId+state` |
| `docs/database/indexes.md` | Note Phase 2I keyset indexes |
| `mobile/lib/features/ride/**` | `RideListPage`, `listRides`, `ListRidesUseCase` |
| `mobile/lib/app/di/providers.dart` | `listRidesUseCaseProvider` |
| `mobile/test/features/ride/ride_list_entity_test.dart` | **New** |

---

## 4. Endpoint contract

```
GET /v1/rides
Authorization: Bearer <token>
Query: limit?, cursor?, status?, serviceType?
```

Success envelope:

```json
{
  "data": {
    "rides": [ /* publicRide */ ],
    "nextCursor": "..." | null
  },
  "requestId": "...",
  "timestamp": "..."
}
```

Defaults: `limit=10`, `status=all`. Max `limit=50`. Min `limit=1`.

Unknown query keys (including `passengerId` / `driverId`) → `400 VALIDATION_ERROR`.

---

## 5. Passenger semantics

Server injects `passengerId == authenticated uid`. Includes SEARCHING / active / terminal rides owned by the passenger.

---

## 6. Driver semantics

Approved driver (`role=driver` && `driverStatus=approved`) queries `assignedDriverId == uid`. Unassigned SEARCHING never appears. Post-assign CANCELLED remains visible (assignee retained).

---

## 7. Role resolution

`loadActor` → if approved driver then driver path, else passenger path. Client role/view is not trusted.

---

## 8. Authorization / security

- Ownership filters always applied server-side from token + actor profile.
- Cursor includes `ob` owner-binding hash; cross-user cursor → `VALIDATION_ERROR`.
- `GET /v1/rides/:rideId` IDOR behavior unchanged.
- Clients still cannot query Firestore `rides` directly (rules deny).

---

## 9. State filter semantics

| `status` | Predicate |
|----------|-----------|
| `all` (default) | none |
| `completed` | `state in [RIDE_COMPLETED, RIDE_CLOSED]` |
| `cancelled` | `state == CANCELLED` |

`EXPIRED` appears only under `all`.

---

## 10. ServiceType filtering

Optional equality on `ride|courier|intercity|move`. Invalid → `VALIDATION_ERROR`.

---

## 11. Pagination / cursor design

Opaque base64url JSON:

```json
{ "createdAt": "<ISO>", "rideId": "<id>", "v": 1, "ob": "<ownerBinding>" }
```

`startAfter(createdAt, rideId)` when cursor present. `nextCursor` only when page is full (`length == limit`).

---

## 12. Ordering

`createdAt DESC`, then `rideId DESC` (mandatory tie-break). Proven with identical timestamps.

---

## 13. Firestore queries

Equality on ownership field (+ optional `serviceType` / `state` / `in`), then composite order + limit. No collection group, no offset, no transactions, no full scans.

---

## 14. Indexes

Added to `firestore.indexes.json`:

- passenger: `(passengerId, createdAt DESC, rideId DESC)` and variants with `state` / `serviceType`
- driver: `(assignedDriverId, createdAt DESC, rideId DESC)` and variants with `state` / `serviceType`

Preserved: `(assignedDriverId, state)` for offer/assignment guard.

Live emulator executed all query variants successfully with these indexes loaded.

---

## 15. DTO / data exposure

Reused `publicRide()`. Audited: no `routePolyline`, `distanceKm`, `estimatedDurationMin`, `feePolicySnapshot`, `paymentIntentId`, `cancellationFeeMinor`, idempotency/outbox internals.

---

## 16. Flutter changes

- `RideListPage { rides, nextCursor }`
- datasource/repository `listRides`
- `ListRidesUseCase`
- provider wiring  
No UI / navigation.

---

## 17. Observability

`logSafe('RIDE_LIST', { operation, requestId, actorId, actorRole, statusFilter, serviceType, limit, hasCursor, resultCount, hasNextPage, durationMs, errorCode? })`.

No tokens, no full cursor payload, no location dumps.

---

## 18. Performance

Bounded by `limit ≤ 50`. Filtering in Firestore. No totalCount / full history load.

---

## 19. Test matrix

Vitest Phase 2I cover: empty/own/foreign, driver unassigned exclusion, all status mappings + EXPIRED, serviceType, keyset + identical timestamps, invalid limit/cursor/status, cross-user cursor, DTO leak check, create→cancel reflection, route vs get-by-id, limit 1/50/51+, unauthenticated.

---

## 20. Live Firestore query verification

Command (full-bundled harness under emulator):

```bash
npx firebase-tools@13 emulators:exec --only firestore --project ora-app-d8112 \
  "FIRESTORE_EMULATOR_HOST=127.0.0.1:8181 GCLOUD_PROJECT=ora-app-d8112 node /tmp/ride_list_full.cjs"
```

Also: `npm run test:ride-list-firestore-queries` (esbuild full bundle, no `--packages=external`).

**Result: 7 passed, 0 failed**

- passenger isolation  
- driver isolation + unassigned exclusion  
- status filters (completed/cancelled/EXPIRED)  
- serviceType  
- identical timestamp tie-break + cursor  
- cross-user cursor / empty / max limit  
- forged ownership query params  

---

## 21. Regression results

| Suite | Command / method | Result |
|-------|------------------|--------|
| Ride Vitest | `vitest run src/__tests__/rides.test.ts` (nospace copy) | **75/75 PASS** |
| Ride proof (2E) | `npm run test:ride-proof` | **17/17 PASS** |
| Phase 2I live queries | emulator + full bundle | **7/7 PASS** |
| Phase 2G progression | full-bundled under emulator | **8/8 PASS** |
| Phase 2H close | full-bundled under emulator | **7/7 PASS** |
| Phase 2F offer-create | full-bundled under emulator | **8/8 PASS** |
| Flutter analyze | `dart analyze lib/features/ride lib/app/di/providers.dart` | **No issues** |
| Flutter ride tests | `flutter test test/features/ride/` | **5/5 PASS** |

Note: `--packages=external` + workspace path with spaces can hang `require('firebase-admin')` in this environment; Phase 2I npm script uses a full esbuild bundle. 2F/2G/2H regressions above were re-run with the same full-bundle approach under a fresh emulator.

---

## 22. Bugs found/fixed

1. **Route ordering** — `GET /` registered before `GET /:rideId` to avoid capture.  
2. **memoryDb** — extended with `in` / `orderBy` / `startAfter` so Vitest list tests match keyset semantics.  
3. **Harness bundling** — list script avoids `--packages=external` so Admin SDK loads from the bundle (avoids space-path require hangs).  
4. **Forged owner query params** — rejected via allowlist, not silently ignored.

---

## 23. Known limitations

- No snapshot isolation across pages (architecture-approved).  
- Dual-role users follow server `role` only (no client `view=`).  
- Deploy indexes to production before enabling the endpoint in prod.

---

## 24. Explicit non-goals

`rideHistory` collection; payments; wallet; ratings; Maps/GPS; RTDB; Redis; FCM; dispatch; UI; Phase 2J+.

---

## 25. Definition of Done

- [x] Authenticated list works  
- [x] Passenger + driver isolation  
- [x] Status + serviceType filters  
- [x] Cursor pagination + deterministic ordering  
- [x] Indexes present and emulator-verified  
- [x] `publicRide` exposure audited  
- [x] Live Firestore query harness green  
- [x] Flutter domain/data tests + analyze green  
- [x] 2E/2F/2G/2H regressions green  
- [x] No duplicate history collection  

---

## 26. Final classification

# PASS — PHASE 2I CLOSED
