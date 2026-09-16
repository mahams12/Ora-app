# Phase 2N — Ratings / Reviews Architecture Investigation

**Status:** INVESTIGATION ONLY — NOT IMPLEMENTED  
**Date:** 2026-09-15  
**Prerequisite:** Phase 2M CLOSED (`docs/implementation/phase-02m-no-show.md`)  
**Constraint:** No production code, Flutter UI, indexes, APIs, or migrations in this phase.

---

## 1. Current architecture findings

### Ride aggregate (source of truth: code)

| Artifact | Path | Finding |
|----------|------|---------|
| States | `backend/auth-service/src/rides/types.ts` | `SEARCHING` … `RIDE_CLOSED`, plus `CANCELLED`, `EXPIRED`, `NO_SHOW` |
| Gates | `backend/auth-service/src/rides/state_machine.ts` | Aggregate `TERMINAL` = `CANCELLED`, `EXPIRED`, `RIDE_CLOSED`, `NO_SHOW`. `RIDE_COMPLETED` is **not** aggregate-terminal (close still allowed). |
| Close | `RideService.closeRide` | `RIDE_COMPLETED → RIDE_CLOSED`; passenger **or** assigned driver; `closedAt`; `ride.closed` outbox; Idempotency-Key |
| Complete | `completeRide` / `progressAssignedRide` | Assigned driver only; `RIDE_STARTED → RIDE_COMPLETED`; `completedAt`; `ride.completed` |
| NO_SHOW | `markNoShow` / sweep | `DRIVER_ARRIVED → NO_SHOW`; worker-only; **no** rating/fee/`noShowCount` |
| History | `listRides` + `list_query.ts` | `GET /v1/rides`; filters `all` / `completed` / `cancelled`; `rides/{rideId}` SoT |
| Auth | Firebase JWT on `/v1/rides`; worker token on `/v1/internal/*` | Participant checks: `passengerId` / `assignedDriverId` vs `caller.uid` |
| Idempotency | `idempotencyRecords/{key}` | Actor + requestHash bound; 7-day TTL; user mutations |
| Outbox | `outboxEvents/{eventId}` | Written in same Firestore txn as state mutations |

### Payment / close coupling (locked architecture)

Ride SM and payment SM are **separate** (`docs/product/payment-flow.md`, ADR / phase-0.7 approval, Phase 2H closure). Close may precede payment. Completing a ride does **not** capture money.

**Implication for ratings:** Rating must **not** be wired into a chain such as `COMPLETED → rating → payment → closure`. Rating should hang off the ride aggregate independently of payment settlement.

### Phase hang-off readiness

| Prerequisite | Status |
|--------------|--------|
| Success path through `RIDE_COMPLETED` | Implemented |
| Aggregate close `RIDE_CLOSED` | Implemented (2H) |
| History list | Implemented (2I) |
| Participant auth patterns | Proven on get/close/cancel |
| Idempotency + outbox patterns | Proven |
| Ratings HTTP API / write path | **Absent** |
| Rating outbox event in contracts | **Absent** |

---

## 2. Existing schema findings

### Documented (not implemented in `RideDoc` / runtime)

**`docs/database/firestore-schema.md`:**

| Location | Fields |
|----------|--------|
| `users` | `rating` (running average, server-computed), `totalTrips` |
| `drivers` | `rating`, `ratingCount`, `noShowCount`, trip counters |
| `rides` | `passengerRating`, `driverRating` (server-only denorm) |
| `ratings` collection | Doc ID `{rideId}_{ratingType}`; `raterId`, `ratedId`, `role` (`passenger_rates_driver` \| `driver_rates_passenger`), `stars` 1–5, `tags[]`, `comment?`, `timestamp` |

### Runtime code (`RideDoc`)

**No** `passengerRating`, `driverRating`, or any rating fields.  
**No** backend writes to `users.rating`, `drivers.rating`, or `ratings/*`.

### Rules / indexes

| Artifact | Finding |
|----------|---------|
| `firestore.rules` | `match /ratings/{id} { allow read, write: if false; }` — backend Admin SDK only if implemented |
| `firestore.indexes.json` (deployed) | **No** `ratings` indexes |
| `docs/database/indexes.md` | Documents intended `ratedId ASC + timestamp DESC` (and a `userId`+`timestamp` stub) — **not** in deployed JSON |

### Source of truth (`docs/architecture-final/07-source-of-truth.md`)

- Authoritative: **Firestore `ratings`**
- Derived: `drivers.rating` / metrics (not authoritative alone)

---

## 3. Existing rating-related code findings

| Area | Result |
|------|--------|
| `backend/auth-service/src/**` | **Zero** rating/review/stars symbols (except unrelated comments) |
| Flutter `mobile/lib/**` | **Zero** rating/review/stars |
| Routes | No `/rating`, `/ratings`, `/rate` |
| Event contracts | No `rating.*` / `ride.rating.*` |
| Phase 2N docs | This investigation is the first |
| Product docs | Strong intent (see §4) |
| `docs/api/ride-api.md` | Example nested `driver.rating` on ride get — **aspirational**; not in `publicRide` |

**Conclusion:** Ratings is a **greenfield aggregate + API**. Schema and product intent exist; runtime is empty.

---

## 4. Product contract

### Who can rate whom?

| Source | Implication |
|--------|-------------|
| `docs/product/ride-lifecycle.md` §9 | “**Both parties rate.**” |
| `docs/product/passenger-flow.md` | Passenger rates driver 1–5 after trip |
| `docs/product/driver-flow.md` | Driver rates passenger 1–5 after `RIDE_COMPLETED` |
| Schema `ratings.role` | Explicit two role strings |
| Feature inventory #49 / #50 | Ratings = MVP; deeper “Reviews” = POST-MVP |

**Recommended product model (subject to freeze):** **C — both directions**

- Passenger → assigned driver (`passenger_rates_driver`)
- Assigned driver → passenger (`driver_rates_passenger`)

Not self-rating. Not third-party. Not rating a different ride’s participants.

### What counts as “a trip eligible for rating”?

Product places rating after successful trip completion (receipt / post-`RIDE_COMPLETED`), **not** after cancel / expire / no-show.

---

## 5. State / lifecycle rules

### Candidates

| State | Rate allowed? | Rationale |
|-------|---------------|-----------|
| Before `RIDE_COMPLETED` | **No** | Trip not operationally finished |
| `RIDE_COMPLETED` | **Proposed Yes** | Product post-trip; payment/close independent |
| `RIDE_CLOSED` | **Proposed Yes** | Same success path; late close / offline must not block rating |
| `NO_SHOW` | **No** | Terminal failure path; no completed trip |
| `CANCELLED` | **No** | Cancelled; not a completed trip |
| `EXPIRED` | **No** | Never assigned/completed |

### Precise proposed rule (recommendation — **not frozen**)

```text
A rating may be submitted iff:
  ride.state ∈ { RIDE_COMPLETED, RIDE_CLOSED }
  AND caller is exactly passengerId OR assignedDriverId
  AND rated party is the counterpart (not self)
  AND no existing ratings doc for that (rideId, direction)
```

**Independence:**

- Rating does **not** require prior `RIDE_CLOSED`
- Close does **not** require prior rating
- Rating does **not** require payment settlement
- Rating does **not** mutate ride `state` / does **not** bump ride `version` unless a deliberate denorm write is approved (prefer **not** bumping ride version for rating — see §6)

### Offline when ride ended

If the app was offline at completion: once online, as long as the ride remains `RIDE_COMPLETED` or `RIDE_CLOSED`, rating remains available. No time-limited “must rate within N minutes of complete” in MVP unless product freezes one (not required by current ride code).

### One-time?

**Proposed:** one rating per direction per ride (immutable after accept). See §9–§10.

---

## 6. Storage decision

### Options vs Ora architecture

| Option | Description | Fit |
|--------|-------------|-----|
| **A** | Fields only on `rides/{rideId}` | Weak SoT; conflicts with `07-source-of-truth`; hard to query “ratings of user X” |
| **B** | `ratings/{rideId}_{type}` only | Matches schema + SoT; natural uniqueness |
| **C** | Only under `users`/`drivers` | Loses per-ride audit; wrong SoT |
| **D** | Ratings doc + ride denorm + user/driver aggregates | Matches full schema vision; highest txn complexity |
| **E** | Subcollection `rides/{id}/ratings/{raterId}` | Viable uniqueness; diverges from documented doc-ID scheme |

### Evaluation (summary)

| Concern | Best approach |
|---------|---------------|
| Source of truth | **B** (`ratings` collection) |
| Uniqueness | Doc ID `{rideId}_{ratingType}` (create-once) |
| Idempotency | Natural key + Idempotency-Key (see §9) |
| Concurrent writes | Firestore txn: create-if-absent |
| Queryability | By `ratedId` later (index when querying) |
| Security | Rules already deny client writes |
| Aggregation | Derived; defer or minimal (see §12) |
| Historical correctness | Immutable rating docs |
| Scalability | Per-ride docs scale with trips |
| Privacy/deletion | Soft-delete / moderation later; not MVP |

### Recommendation (subject to freeze)

**Primary SoT: Option B** — `ratings/{rideId}_{ratingType}`.

**Optional denorm (open):** write `rides.passengerRating` / `rides.driverRating` in the **same txn** for cheap history/get surfaces **without** changing ride `state` and **preferably without** bumping `ride.version` (rating is not a ride SM transition). If denorm is deferred, history reads rating via GET rating endpoint or a join later.

**Do not** use Option A alone. **Do not** invent Redis/RTDB counters.

---

## 7. API proposal

### Minimum surface (proposal)

| Method | Path | Purpose |
|--------|------|---------|
| `POST` | `/v1/rides/:rideId/ratings` | Submit my rating for this ride |
| `GET` | `/v1/rides/:rideId/ratings` | Read rating(s) visible to caller for this ride |

Avoid a separate top-level `/v1/ratings` until product needs cross-ride listing.

### `POST /v1/rides/:rideId/ratings`

| Aspect | Proposal |
|--------|----------|
| Auth | Firebase JWT (existing ride auth) |
| Idempotency | Required `Idempotency-Key` (8–200), same machinery as close |
| Body (stars-only MVP) | `{ "stars": 1\|2\|3\|4\|5 }` optionally `{ "expectedRideVersion": number }` — **open** whether version is required |
| Body (if tags/comment approved) | `{ "stars": n, "tags"?: string[], "comment"?: string }` |
| Server derives | `raterId` from token; `ratedId` from counterpart; `role` from direction; `rideId` from path |
| Response | `200` with rating DTO; replay returns stored snapshot |
| Errors | `401` unauthenticated; `403` not participant / wrong target; `404` ride; `409` `STATE_CONFLICT` (wrong state / already rated); `409` `IDEMPOTENCY_KEY_REUSED`; `400` validation |

### `GET /v1/rides/:rideId/ratings`

| Aspect | Proposal |
|--------|----------|
| Auth | Participant only |
| Returns | Caller’s submitted rating (if any); optionally counterpart’s rating if product wants mutual visibility — **open** |
| Non-participants | `403` / `404` consistent with `getRide` |

### Non-goals for API

- Public profile rating history listing
- Admin moderation endpoints
- Tip / payment endpoints
- Batch rate endpoints

---

## 8. Authorization model

Reuse ride participant checks; add a thin rating-direction boundary.

| Rule | Enforcement |
|------|-------------|
| Must be on the ride | `uid ∈ {passengerId, assignedDriverId}` |
| Passenger rates driver only | If passenger → `ratedId = assignedDriverId`, role `passenger_rates_driver` |
| Driver rates passenger only | If assigned driver → `ratedId = passengerId`, role `driver_rates_passenger` |
| No self-rate | `raterId !== ratedId` (also enforced by counterpart mapping) |
| No forge rater | `raterId` from token only |
| No forge target | Target derived from ride fields only |
| Wrong state | Reject `NO_SHOW`, `CANCELLED`, `EXPIRED`, pre-complete |
| Direct Firestore write | Denied by rules |
| Modify another user’s rating | Doc ownership + no update API in MVP |

**Existing helpers are mostly sufficient** (`getRide` / `closeRide` participant pattern). Recommend a dedicated `assertCanRate(ride, caller)` helper for clarity — not a new auth subsystem.

---

## 9. Idempotency model

### Recommended contract

1. **Natural uniqueness:** `ratings/{rideId}_{ratingType}` created at most once.  
2. **HTTP Idempotency-Key:** required on POST (align with close/complete).  
3. **Mutability:** **immutable after successful create** for Phase 2N MVP.  
4. **Same key + same body:** replay original `200` snapshot.  
5. **Same key + different body:** `IDEMPOTENCY_KEY_REUSED` 409.  
6. **Different key after success:** `STATE_CONFLICT` / `ALREADY_RATED` 409 (no overwrite).  
7. **Changed stars after success:** rejected (not editable in MVP).

### Idempotency-Key scope

| Item | Proposal |
|------|----------|
| Document ID | Raw key (existing global collection) |
| `requestHash` input | `{ rideId, operation: 'RIDE_RATING_SUBMIT', stars, tags?, comment?, ratingType }` |
| Actor binding | `actorId === caller.uid` |
| TTL | Existing 7 days |

**Note:** Architecture-final condition closure mentions a **15-minute editable window**. That conflicts with a simple immutable MVP. Treat editability as an **open decision** (§21). Recommendation: **immutable first**; editable window = later slice.

---

## 10. Concurrency model

| Scenario | Expected |
|----------|----------|
| Double-tap / duplicate HTTP | One doc; one outbox (if any); idempotent replay |
| Lost response + retry (same key) | Replay |
| Lost response + retry (new key) | Already-rated conflict |
| Same user concurrent POSTs | Exactly one create wins; other sees existing / conflict |
| Both participants rate concurrently | Two independent docs (`…_passenger` / `…_driver`); both succeed |
| Rating vs close concurrent | Both legal; neither overwrites the other (rating must not require specific closed/completed exclusivity beyond allow-set) |
| Rating vs NO_SHOW | Impossible if already COMPLETED; if somehow wrong state, reject |
| Stale client | State/participant checks in txn; conflict errors |

**Correctness boundary:** Firestore transaction that:

1. Reads idempotency record  
2. Reads ride  
3. Reads rating doc (must not exist)  
4. Writes rating (+ optional denorm / outbox / idempotency success)

---

## 11. Event / outbox decision

### Recommendation

**Emit** `ride.rating.submitted` in the **same txn** as the rating create (consistent with ride mutations).

**Not** in current `docs/architecture-review/event-contracts.md` — must be added at implementation freeze.

### Proposed payload (lean)

```json
{
  "rideId": "<string>",
  "ratingId": "<rideId>_<ratingType>",
  "ratingType": "passenger_rates_driver" | "driver_rates_passenger",
  "raterId": "<uid>",
  "ratedId": "<uid>",
  "stars": 1
}
```

**Omit from payload:** review text, tags (or include only if approved in freeze), `occurredAt` (envelope), payment fields, GPS, display names.

**Causation ID:** Idempotency-Key (user mutation pattern), **or** `rating:{rideId}:{ratingType}` if worker-less path prefers deterministic causation — prefer **Idempotency-Key** for consistency with close/complete.

---

## 12. Aggregation decision

### What exists today

| Field | Schema | Runtime |
|-------|--------|---------|
| `users.rating` | Documented | **Not written** |
| `drivers.rating` / `ratingCount` | Documented | **Not written** |
| Matching `adjusted_rating` | Algorithms docs | **Not implemented** |

### Options for Phase 2N

| Option | Description | Recommendation |
|--------|-------------|----------------|
| **A** | Individual ratings only | **Preferred for first slice** |
| **B** | Ratings + update aggregates in same txn | Higher risk (average math, contention on hot driver docs) |
| **C** | Ratings now; aggregates later | Same as A with explicit deferral |
| **D** | Distributed counters / CF / Redis | **Reject** — not required |

**Conservative recommendation:** **A / C** — persist authoritative `ratings` docs (+ optional ride denorm). **Defer** `users.rating` / `drivers.rating` / `ratingCount` updates and ranking algorithms.

If product insists aggregates ship with 2N, freeze a **simple** incremental update in-txn (read count/mean, write new mean) — still no Redis/CF — and accept driver-doc contention under high concurrency.

---

## 13. History integration

Phase 2I: `GET /v1/rides` / `GET /v1/rides/:id` via `publicRide` — **no** rating fields today.

### Recommendation (minimum clean contract)

| Surface | Proposal |
|---------|----------|
| New history filter | **Do not add** (`status=rated` etc.) |
| `GET /v1/rides` list | **Do not** bloate list with full rating objects in MVP |
| `GET /v1/rides/:rideId` | Optional thin flags: `myRatingStars: number \| null` and/or `counterpartRated: boolean` — **open** |
| Dedicated `GET …/ratings` | Preferred place for full rating DTO |

Clients can use history `state ∈ {RIDE_COMPLETED, RIDE_CLOSED}` + GET rating to decide “show rate CTA”.

---

## 14. Offline / retry behavior

| Step | Server behavior |
|------|-----------------|
| Submit succeeds; response lost | Retry with **same** Idempotency-Key → replay; one rating doc |
| Retry with new key after success | `ALREADY_RATED` / `STATE_CONFLICT` |
| Retry with same key, changed stars | `IDEMPOTENCY_KEY_REUSED` |
| App restart | Local pending queue must retain Idempotency-Key |
| Stale local “not rated” after success | GET ratings / getRide flags reconcile |

**Server is authoritative.** Client must not assume create succeeded without HTTP success or replay.

---

## 15. Firestore / index requirements

### Writes (MVP)

- Create `ratings/{rideId}_{ratingType}` by ID — **no composite index required** for the primary write path.  
- Idempotency + optional outbox + optional ride denorm — existing patterns.

### Reads (MVP)

- GET by known doc ID — **no index**.  
- List-by-`ratedId` (profile history) — **out of MVP**; when needed, add:

```text
Collection: ratings
Fields: ratedId ASC, timestamp DESC
```

(documented in `indexes.md`, **not** yet in deployed `firestore.indexes.json`)

**Do not add speculative indexes in Phase 2N implementation until a query exists.**

---

## 16. Testing strategy

### Unit (MemoryDb / supertest) — required

**Positive**

- Passenger rates driver on `RIDE_COMPLETED`
- Driver rates passenger on `RIDE_COMPLETED`
- Rating allowed on `RIDE_CLOSED`
- Both directions independently

**Negative**

- Unauthenticated  
- Non-participant  
- Wrong / forged ride  
- Self-rate attempt  
- Invalid stars (0, 6, 3.5 if integers-only, non-number)  
- `NO_SHOW`, `CANCELLED`, `EXPIRED`, `RIDE_STARTED`, etc.  
- Duplicate rating (second submit)  
- Idempotency key reuse with different body  

**Retry**

- Same key / same body replay  
- Lost-response simulation  

**Security**

- Client cannot write `ratings` (rules contract test if present)  
- Target always derived server-side  

### Live Firestore — required before eventual close

See §17.

### Regression

Re-run established harnesses: **2E–2M** (or the repo’s current live progression/close/list/expire/offer-expire/arrivedAt/no-show proofs). Do not claim pass without execution.

---

## 17. Live Firestore proof strategy

Minimum before Phase 2N can close (future implementation phase):

| # | Proof | Verify in Firestore (Admin SDK) |
|---|-------|----------------------------------|
| 1 | Normal passenger rating | Exactly one `ratings` doc; fields exact; optional outbox |
| 2 | Normal driver rating | Second direction doc |
| 3 | Duplicate retry same key | No second doc; replay |
| 4 | Same key different body | No mutation |
| 5 | Concurrent same-user 2-way / 10-way | One doc only; contention observed |
| 6 | Both participants concurrent | Two docs, one each direction |
| 7 | `NO_SHOW` rejection | Zero rating docs |
| 8 | `CANCELLED` rejection | Zero rating docs |
| 9 | Participant auth | Foreign uid cannot create |
| 10 | History/get visibility | Per frozen contract |
| 11 | Rating ∥ close race | Both legal; no state corruption |

Persisted document inspection required — not HTTP-body-only.

---

## 18. Security model

| Threat | Mitigation |
|--------|------------|
| Rate ride not on | Participant check |
| Rate wrong person | Counterpart derived from ride |
| Rate self | Direction mapping + assert |
| Rate NO_SHOW / CANCELLED | State allow-list |
| Forge rater | Token uid |
| Modify others’ ratings | No update API; rules deny client |
| Direct Firestore create | Rules `allow write: if false` |
| Enumerate others’ ratings | GET participant-scoped only |

No AI moderation, reporting UI, or trust-and-safety platform in 2N.

---

## 19. Scope / non-goals

**Must not enter Phase 2N unless freeze explicitly expands:**

- Payments, fees, tips, wallet, ledger, earnings, promotions  
- GPS / Maps / dispatch / FCM / Redis / RTDB  
- AI moderation / reporting systems  
- Ranking / matching / reputation algorithms  
- `noShowCount` mutation  
- Editable window / rewrite history  
- Deep “reviews” product (inventory #50)  
- Flutter UI screens  
- Unrelated refactors  
- Changing ride SM states  
- Coupling rating to payment or forcing `COMPLETED → rating → payment → close`

---

## 20. Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Coupling rating to `RIDE_CLOSED` only | Medium | Blocks offline users who never close; prefer COMPLETED∪CLOSED |
| Coupling rating to payment | High | Violates locked ride/payment separation |
| Shipping aggregates + averages in v1 | Medium | Contention / correctness bugs; defer |
| Editable ratings without audit | Medium | Immutable MVP |
| API churn (unfrozen contracts) | High | Decision freeze before code |
| Denorm on ride without clear semantics | Low–Med | Prefer ratings SoT; denorm optional |
| Schema `passengerRating` naming confusion | Low | Document: passengerRating = stars **given to driver** (per schema note) |

---

## 21. Open decisions

These **block** a “READY FOR IMPLEMENTATION” verdict:

| ID | Decision | Options | Lean |
|----|----------|---------|------|
| **D1** | Eligibility states | (a) `RIDE_COMPLETED` only (b) `RIDE_CLOSED` only (c) **both** | **(c)** |
| **D2** | Directionality | (a) passenger→driver only (b) driver→passenger only (c) **both** | **(c)** product |
| **D3** | Mutability | (a) **immutable** (b) 15-min edit window | **(a)** for 2N |
| **D4** | Payload richness | (a) **stars only** (b) stars + optional tags (c) stars + tags + optional comment | **(a)** or **(b)**; avoid mandatory text |
| **D5** | Aggregation | (a) **ratings only** (b) + ride denorm (c) + user/driver aggregates | **(a)** or **(a)+(b)**; defer **(c)** |
| **D6** | Ride version bump on rating | (a) **never** (b) bump if denorm | **(a)** |
| **D7** | Outbox event | (a) **emit `ride.rating.submitted`** (b) no event | **(a)** |
| **D8** | History exposure | (a) separate GET only (b) thin flags on getRide (c) full objects on list | **(a)** or **(a)+(b)** |
| **D9** | Counterpart visibility | (a) see only my rating (b) see both after submit (c) see counterpart always | Product call |
| **D10** | HTTP paths / error code names | Freeze exact routes + `ALREADY_RATED` vs reuse `STATE_CONFLICT` | Align with existing codes where possible |

---

## 22. Recommended decision freeze

Copy/paste freeze proposal for product/engineering approval:

```text
PHASE 2N DECISION FREEZE PROPOSAL

D1 — Eligibility:
  Allow rating iff ride.state ∈ { RIDE_COMPLETED, RIDE_CLOSED }.
  Forbidden: NO_SHOW, CANCELLED, EXPIRED, and all pre-completion states.
  Independent of payment settlement and of whether close has occurred.

D2 — Direction:
  Both directions:
    passenger → assignedDriver (passenger_rates_driver)
    assignedDriver → passenger (driver_rates_passenger)

D3 — Mutability:
  One rating per direction per ride; immutable after successful create.
  No 15-minute edit window in Phase 2N.

D4 — Content:
  Stars only: integer 1..5 inclusive.
  No mandatory review text. Tags/comment deferred unless explicitly approved.

D5 — Storage:
  Authoritative: ratings/{rideId}_{ratingType}
  Phase 2N: do NOT update users.rating / drivers.rating / ratingCount.
  Optional: denormalize stars onto rides.passengerRating / rides.driverRating
            in the same transaction WITHOUT bumping ride.version / changing state.
  (Approve or reject denorm explicitly.)

D6 — API:
  POST /v1/rides/:rideId/ratings  (Idempotency-Key required)
  GET  /v1/rides/:rideId/ratings  (participant-scoped)
  No new history status filter.

D7 — Event:
  Atomic outbox ride.rating.submitted with lean payload
  (rideId, ratingId, ratingType, raterId, ratedId, stars).
  causationId = Idempotency-Key.

D8 — Non-goals:
  Payments, tips, moderation, ranking, FCM, Redis, RTDB, Maps, UI, noShowCount.
```

---

## 23. Explicit implementation readiness verdict

### What is already safe / ready as foundation

- Ride success + close terminals exist  
- Participant auth + idempotency + outbox patterns exist  
- `ratings` collection documented; client writes denied  
- Product intent for two-way post-trip stars is clear  
- Payment/close independence is locked (do not couple)

### What is not frozen

D1–D10 above — especially eligibility vs close-only, mutability vs editable window, stars-only vs tags/comment, aggregation/denorm, event contract, and history exposure.

---

### NOT READY — OPEN DECISIONS REMAIN

Do **not** begin Phase 2N production implementation until the decision freeze (proposed in §22) is explicitly approved and recorded (e.g. `docs/implementation/phase-02n-decision-freeze.md`).

After freeze approval, implementation can proceed as a bounded greenfield aggregate without changing the ride state machine.
