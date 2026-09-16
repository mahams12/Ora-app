# Phase 2I — Architecture / Invariant Investigation

**Date:** 2026-09-09  
**Status:** INVESTIGATION ONLY — no production code modified  
**Verdict:** see §29

---

## 1. Executive summary

Phases 2C–2H closed the ride aggregate through **`RIDE_CLOSED`**. There is still **no** `GET /v1/rides` list endpoint, no Flutter list API, and no `rideHistory` collection.

The locked history contract (`docs/api/ride-api.md`) specifies:

`GET /v1/rides?limit&cursor&status=completed|cancelled|all&serviceType=…`

**Recommended Phase 2I:** implement that read/query slice **directly against `rides/{rideId}`** as the sole source of truth, with backend-enforced ownership filters, cursor pagination, and the composite indexes already documented in `docs/database/indexes.md` (not fully present in live `firestore.indexes.json` today).

**Duplicate `rideHistory/{rideId}` is NOT required** for this phase.

---

## 2. Current verified ride architecture

### Inspected

| Area | Finding |
|------|---------|
| `RideService` / routes | Create, get-by-id, offers, progression, cancel, close — **no list** |
| `publicRide()` | Public DTO already suitable for history items |
| `getRide` auth | `passengerId == uid \|\| assignedDriverId == uid` |
| Firestore rules | `rides` deny all client read/write — API/Admin only |
| Indexes (deployed) | Only `assignedDriverId + state` on rides |
| Indexes (docs) | Also `passengerId + createdAt DESC` (missing from deploy file) |
| Flutter | No list/history use case |
| 2G/2H docs | History explicitly deferred to **Phase 2I** |
| Pagination precedent | `listOffers` uses `limit` only — **no cursor pattern yet** |

### Lifecycle (closed)

```
SEARCHING → … → RIDE_CLOSED | CANCELLED | EXPIRED
```

`assignedDriverId`: `null` until select; **retained** after post-assign cancel (2G/2H).

---

## 3. Existing history contract

From `docs/api/ride-api.md`:

| Item | Contract |
|------|----------|
| Endpoint | `GET /v1/rides` |
| Auth | Passenger (own) or Driver (own) |
| Params | `limit`, `cursor`, `status=completed\|cancelled\|all`, `serviceType=ride\|courier\|intercity\|move` |
| Fare note | Expose `agreedFareMinor` (or null if never assigned); never client `finalFare` |
| Response envelope | **Not fully specified** (gap) |

`04-api-contracts.md`: auth + no side effects only.

`02-feature-inventory.md`: Ride history = **MVP**; Search/history broadly = POST-MVP.

Product: passenger “My Rides” with service-type tabs (`passenger-flow.md`).  
Performance budget: paginate 10/page; never load full history at once.

---

## 4. Proposed Phase 2I boundary

### In scope

1. `GET /v1/rides` on auth-service  
2. Actor-scoped Firestore queries on `rides`  
3. Contract query params only (`limit`, `cursor`, `status`, `serviceType`)  
4. Cursor/keyset pagination  
5. Required composite indexes  
6. Response: `{ data: { rides: publicRide[], nextCursor: string \| null } }` (minimal envelope fill for unspecified response — see open questions)  
7. Flutter domain/data list method + cursor model  
8. Emulator query verification + auth isolation tests  

### Out of scope

Duplicate history collection; payments; ratings; Maps/GPS; RTDB; Redis; FCM; active-ride “current trip” product UI; Admin; Cargo/Delivery; mutating closed-phase behavior.

---

## 5. Endpoint contract

```
GET /v1/rides
Authorization: Bearer <token>
Query:
  limit?: number          // default 10, max 50
  cursor?: string         // opaque keyset cursor
  status?: completed|cancelled|all   // default all
  serviceType?: ride|courier|intercity|move  // optional narrow
```

No client-supplied `passengerId` / `driverId`.

Errors (existing taxonomy): `UNAUTHENTICATED`, `VALIDATION_ERROR`, `FORBIDDEN` (if role cannot list), `INTERNAL`.

Idempotency-Key: **not required** (pure GET).

---

## 6. Passenger query semantics

**Authorization filter (mandatory):**

`passengerId == authenticated uid`

Returns rides the caller requested (including SEARCHING / active / terminal).

**Unassigned rides:** yes, for passenger (they own the request).

**Driver identity on items:** `assignedDriverId` may be null or set; exposed via existing `publicRide` (same as `getRide`).

---

## 7. Driver query semantics

**Authorization filter (mandatory):**

`assignedDriverId == authenticated uid`

**SEARCHING / never-assigned:** do **not** appear (field is null; query cannot match).

**Post-assign CANCELLED:** appear (assignee retained) — consistent with audit retention.

**EXPIRED without assignment:** do not appear for drivers.

**Offers-only (never selected):** do not appear.

---

## 8. Authorization / security

| Rule | Detail |
|------|--------|
| Sole query authority | Cloud Run Admin SDK; clients cannot query Firestore `rides` (rules deny) |
| Ownership | Server injects `passengerId` or `assignedDriverId` from token + `loadActor` role |
| Forged filters | Ignore/reject any body or query attempting to set owner ids |
| Tampered cursor | Reject with `VALIDATION_ERROR` if decode fails or owner mismatch encoded |
| Cross-user | Impossible if ownership equality always applied |
| get-by-id | Unchanged; still IDOR-safe |

**Role selection:** use `users/{uid}.role` via existing `loadActor`:

- `role === 'driver'` (approved) → driver query path  
- otherwise → passenger query path  

**Open:** dual-role users (see §29). Do not trust a client `view=driver` without server role check.

---

## 9. State / filter semantics

Contract `status` values are **coarse**, not the full `RideState` enum.

| `status` | Mapped `RideState` set | Notes |
|----------|------------------------|-------|
| `all` (default) | No state predicate | Active + terminal for that actor |
| `completed` | `RIDE_COMPLETED`, `RIDE_CLOSED` | Success path; Firestore `in` |
| `cancelled` | `CANCELLED` | Exact match |
| (invalid) | — | `VALIDATION_ERROR` |

**`EXPIRED`:** included only when `status=all` (not listed in contract enums for completed/cancelled).

**Ambiguity documented:** contract does not define whether `completed` includes in-progress or only terminal success. **Smallest recommendation:** only `RIDE_COMPLETED` + `RIDE_CLOSED` (history “completed” language). Active rides remain visible under `all`.

---

## 10. Active vs historical rides

Contract title is “History” but params include `all` and product “My Rides” implies active too.

**Recommendation:** single endpoint; `status=all` includes active states; do **not** add a second “current ride” endpoint in 2I.

Active-ride discovery UX is out of scope beyond list rows.

---

## 11. DTO / data exposure

Reuse **`publicRide()`** as the history item DTO (already used by `getRide`).

**Include (already public):** identities, state, versions, category/serviceType, pickup/destination, fare fields, paymentMethod, lifecycle timestamps, cancel fields.

**Keep omitted:** `routePolyline`, `distanceKm`, `estimatedDurationMin`, `feePolicySnapshot`, `paymentIntentId`, `cancellationFeeMinor`, idempotency/outbox internals.

No role-based field stripping required beyond ownership isolation for 2I (same as getRide). Future privacy tightening is out of scope unless a contract requires it.

---

## 12. Pagination design

**Do not use offset.**

**Keyset cursor** over `(createdAt DESC, rideId DESC)`.

### Cursor payload (opaque, base64url JSON)

```json
{ "createdAt": "<iso>", "rideId": "<id>", "v": 1 }
```

Optionally bind `ownerKey` hash of uid+role to detect cross-user cursor reuse → `VALIDATION_ERROR`.

### Algorithm

1. Query with ownership (+ optional status/serviceType)  
2. `orderBy createdAt desc`, `orderBy rideId desc`  
3. If cursor: `startAfter(createdAt, rideId)`  
4. `limit(n)`  
5. `nextCursor` from last doc if page full; else null  

### Defaults

| Param | Value |
|-------|-------|
| Default `limit` | **10** (contract example + performance budget) |
| Max `limit` | **50** |
| Min `limit` | 1 |

Invalid limit/cursor → `VALIDATION_ERROR`.

---

## 13. Ordering design

Primary: `createdAt DESC`  
Tie-break: `rideId DESC` (UUID lexicographic stability)

Deterministic for identical timestamps.

**Paging during mutations:** eventual consistency — a ride may appear with older state on page 1 and newer on refresh; duplicates/skips across pages possible under concurrent creates (acceptable for history UX; no snapshot isolation required by contract).

---

## 14. Firestore query design

### Passenger `status=all`

```
rides
  .where('passengerId', '==', uid)
  [.where('serviceType', '==', st)]
  .orderBy('createdAt', 'desc')
  .orderBy('rideId', 'desc')
  .startAfter(...)
  .limit(n)
```

### Passenger `status=cancelled`

Add `.where('state', '==', 'CANCELLED')`.

### Passenger `status=completed`

Add `.where('state', 'in', ['RIDE_COMPLETED', 'RIDE_CLOSED'])`.

### Driver

Same with `assignedDriverId == uid`.

No transactions. No collection group queries.

---

## 15. Required indexes

Add to `firestore.indexes.json` (align with `docs/database/indexes.md` + filter variants):

| Fields | Why |
|--------|-----|
| `passengerId` ASC + `createdAt` DESC + `rideId` DESC | List all / cursor |
| `passengerId` ASC + `state` ASC + `createdAt` DESC + `rideId` DESC | status cancelled / completed (`in` uses state) |
| `passengerId` ASC + `serviceType` ASC + `createdAt` DESC + `rideId` DESC | serviceType without state |
| `passengerId` ASC + `serviceType` ASC + `state` ASC + `createdAt` DESC + `rideId` DESC | both filters |
| `assignedDriverId` ASC + `createdAt` DESC + `rideId` DESC | Driver all |
| `assignedDriverId` ASC + `state` ASC + `createdAt` DESC + `rideId` DESC | Driver status |
| `assignedDriverId` ASC + `serviceType` ASC + `createdAt` DESC + `rideId` DESC | Driver serviceType |
| `assignedDriverId` ASC + `serviceType` ASC + `state` ASC + `createdAt` DESC + `rideId` DESC | Driver both |

**Existing keep:** `assignedDriverId + state` (active-assignment offer guard).

**Not required for 2I:** `state + expiresAt` (sweeper — later).

Emulator may auto-suggest missing indexes; production deploy must include them before release.

---

## 16. Consistency semantics

| Scenario | Behavior |
|----------|----------|
| COMPLETED→CLOSED mid-paging | Later pages/refreshes may show CLOSED; OK |
| Cancel mid-paging | May appear under `all` / `cancelled` after refresh |
| Strong snapshot across pages | **Not required** |
| Read your writes | Same backend instance typically sees committed docs; no special handling |

---

## 17. Performance / scaling

| Scale | Assessment |
|-------|------------|
| 10–100 rides | Trivial |
| 1,000 | Fine with page size ≤50 |
| 10,000+ | Still OK: keyset + indexes; cost ∝ page size, not history length |
| Full scan | Forbidden by pagination |

**Read model not justified** at this phase: ownership-equality queries are Firestore’s intended pattern; no analytics/join requirements.

Revisit only if product needs cross-user search, full-text, or multi-collection joins (inventory marks broad “Search/history” POST-MVP).

---

## 18. Concurrency / read-vs-mutation

Reads need **no** `runTransaction`.

Races with create/select/progress/cancel/complete/close: normal query visibility; no history-specific mutex.

Live “concurrency proof” in the 2E/2F sense is **not** applicable; **emulator query verification** is mandatory instead.

---

## 19. Failure / retry

| Case | Behavior |
|------|----------|
| Unauthenticated | 401 |
| Bad limit/cursor/status/serviceType | 400 `VALIDATION_ERROR` |
| Empty | 200 `{ rides: [], nextCursor: null }` |
| Retry GET | Safe; identical params may differ slightly if data changed |
| Firestore errors | Existing 500/`INTERNAL` path |
| Idempotency records | **Do not create** for GET |

---

## 20. Observability

Structured log (safe):

`operation=RIDE_LIST`, `requestId`, `actorId`, `actorRole`, `statusFilter`, `serviceType`, `limit`, `hasCursor`, `resultCount`, `hasNextPage`, `durationMs`, `error.code`

Never log: tokens, full pickup/destination payloads, raw cursor internals beyond presence.

---

## 21. Duplicate-source-of-truth decision

# YES — Phase 2I can and should use `rides/{rideId}` only

**Why:**

1. History fields already live on the aggregate (`publicRide`).  
2. Ownership fields (`passengerId`, `assignedDriverId`) support equality filters.  
3. Clients are already denied direct Firestore access — API mediation is the security boundary.  
4. Docs already prescribe `passengerId + createdAt` indexes for “My Rides”.  
5. No dual-write/projection exists today; inventing `rideHistory` would create sync races with 2E–2H mutations without benefit.  
6. Scale for per-user lists remains within Firestore page queries.

**A read model would be unjustified speculation** for Phase 2I.

---

## 22. Flutter impact

Minimum:

- `listRides({ limit, cursor, status, serviceType })` on datasource/repository  
- `ListRidesUseCase`  
- Parse `{ rides, nextCursor }`  
- Entity reuse `Ride`  

No UI, navigation, or screen work.

---

## 23. Complete test matrix

### Positive

Passenger/driver: empty; one; many; mixed states; each status filter; serviceType; pagination first/next/last.

### Authorization

Unauthenticated; own vs foreign isolation; forged owner query params ignored/rejected; driver cannot see unassigned passenger rides.

### Pagination

Invalid/tampered cursor; limit bounds; identical `createdAt`; deterministic order; no duplicate rideIds within a stable snapshot when data unchanged.

### Filters

`completed` / `cancelled` / `all` / invalid; EXPIRED only under `all`.

### Read vs mutation

List before/after cancel, complete, close — states match Firestore docs.

### Persistence

Assert listed ids equal queried Admin SDK results for same filters.

---

## 24. Live Firestore verification plan

Script (implementation phase), e.g. `scripts/run_ride_list_firestore_queries.ts`:

- Seed passenger/driver rides across states  
- Run real Admin queries with indexes  
- Prove isolation, ordering, cursor continuity, status mapping  
- Confirm missing index fails clearly in emulator  

Not a mutation contention harness.

---

## 25. Risks

| Risk | Mitigation |
|------|------------|
| Response envelope unspecified | Define minimal `{ rides, nextCursor }` in 2I + document |
| `completed` mapping ambiguity | Document COMPLETED+CLOSED only |
| Dual-role users | Open question; default `loadActor.role` |
| Index deploy lag | Ship indexes with 2I; verify emulator |
| Cursor without rideId tie-break | Always composite order |
| Over-fetching active rides in “history” UX | Product uses `all`; clients can filter UI |

---

## 26. Non-goals

Payments, wallet, ratings, Maps, GPS, RTDB, Redis, FCM, dispatch, proximity, Cargo, Delivery, Admin, UI, `rideHistory` collection, changing 2E–2H mutation semantics.

---

## 27. Implementation plan (next prompt only)

1. Add composite indexes to `firestore.indexes.json`.  
2. Implement `listRides` in `RideService` (role → ownership query).  
3. Wire `GET /` **before** `GET /:rideId` in Express router.  
4. Cursor encode/decode helpers.  
5. Map status filters.  
6. Flutter list use case/repo/datasource.  
7. Vitest auth/filter/pagination tests (memoryDb may stub queries if adapter supports; prefer emulator for query truth).  
8. Live emulator query verification script.  
9. Closure doc.  

---

## 28. Definition of Done

1. `GET /v1/rides` returns only caller-owned rides.  
2. Contract params honored; invalid inputs rejected.  
3. Cursor pagination stable for unchanged data.  
4. Indexes documented and present.  
5. `publicRide` items; no internal leakage.  
6. Flutter domain/data list support.  
7. Emulator query verification green.  
8. No duplicate history collection.  
9. 2E–2H regression untouched.  

---

## 29. Open questions

| # | Question | Recommendation |
|---|----------|----------------|
| 1 | Exact JSON response envelope? | `{ data: { rides, nextCursor } }` |
| 2 | Default `status`? | `all` |
| 3 | Does `completed` include in-progress? | **No** — only COMPLETED+CLOSED |
| 4 | Dual passenger+driver accounts? | Use server `role`; optional later `view` param with authz |
| 5 | Include `EXPIRED` under `cancelled`? | **No** — only under `all` |
| 6 | Max limit 50 vs 100? | **50** (align offer list cap spirit) |

---

## Final verdict

# READY FOR PHASE 2I IMPLEMENTATION

### Exact implementation boundary for the next prompt

**Phase 2I — Ride History / Query Read Slice**

Implement **only** authenticated `GET /v1/rides` against existing **`rides/{rideId}`** (no `rideHistory` collection):

- Ownership: passenger → `passengerId == uid`; driver → `assignedDriverId == uid`  
- Params: `limit` (default 10, max 50), `cursor`, `status=completed|cancelled|all`, `serviceType`  
- Keyset pagination: `createdAt DESC, rideId DESC`  
- Items: existing `publicRide()`  
- Required composite indexes  
- Flutter domain/data list only  
- Emulator query verification  
- No payments/Maps/RTDB/Redis/FCM/ratings/UI  

---

### Hard stop

- Production code **not** modified  
- Phase 2I **not** implemented  
- Phase 2J+ **not** started  

### Return summary

1. **Inspected:** ride module, `publicRide`, auth, indexes/rules, Flutter, 2G–2H docs, ride-api history contract, feature inventory, index design docs.  
2. **Boundary:** `GET /v1/rides` read slice as above.  
3. **Duplicate read model:** **Not necessary** — use `rides` only.  
4. **Query/pagination:** ownership equality + status/serviceType; keyset on `createdAt`/`rideId`.  
5. **Security:** backend-only filters; client Firestore denied; no client owner ids.  
6. **Performance:** page queries scale with page size; 10k+ user history OK without read model.  
7. **Open questions:** §29.  
8. **Verdict:** **READY FOR PHASE 2I IMPLEMENTATION**.
