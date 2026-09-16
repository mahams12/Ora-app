# Phase 2N — Ratings Decision Freeze

**Status:** DECISION FREEZE (no production code modified)  
**Date:** 2026-09-15  
**Prerequisite:** Phase 2M CLOSED (`docs/implementation/phase-02m-no-show.md`)  
**Basis:** `docs/implementation/phase-02n-ratings-architecture-investigation.md` + repository verification  
**Constraint:** This document freezes the contract only. Do **not** implement APIs, indexes, rules, Flutter, or rating writes until the implementation phase.

---

## 1. Status

**FROZEN** — Phase 2N implementation contract approved for a future greenfield ratings slice.

Phase 2M remains **CLOSED** and untouched.

---

## 2. Date

2026-09-15

---

## 3. Prerequisite

| Prerequisite | Status |
|--------------|--------|
| Phase 2M NO_SHOW CLOSED | **Yes** |
| Ride success path through `RIDE_COMPLETED` | Implemented |
| `RIDE_CLOSED` close path | Implemented (2H) |
| History list (2I) | Implemented |
| Idempotency + outbox patterns | Implemented |
| Ratings HTTP / write path | **Absent** (to be built) |

---

## 4. Scope

Phase 2N (future implementation) is a **greenfield rating write/read aggregate** hanging off the existing ride architecture:

- Stars-only rating after successful trip end (`RIDE_COMPLETED` or `RIDE_CLOSED`)
- Both directions (passenger ↔ assigned driver)
- Authoritative `ratings/{rideId}_{ratingType}` documents
- Backend-mediated POST/GET under `/v1/rides/:rideId/ratings`
- Atomic `ride.rating.submitted` outbox
- Independent of payment, close ordering, ride version, and user/driver aggregates

**Out of this freeze task:** any production code, Flutter, Firestore rules, indexes, or tests.

---

## 5. Frozen decisions (D1–D19)

### D1 — Rating eligibility

A rating may be submitted **only** when:

```text
ride.state ∈ { RIDE_COMPLETED, RIDE_CLOSED }
```

**Not allowed** for:

`SEARCHING`, `OFFERS_AVAILABLE`, `DRIVER_ASSIGNED`, `DRIVER_EN_ROUTE`, `DRIVER_ARRIVED`, `RIDE_STARTED`, `CANCELLED`, `EXPIRED`, `NO_SHOW`

| Rule | Frozen |
|------|--------|
| Rating requires `RIDE_CLOSED` | **No** |
| `RIDE_COMPLETED` → rating allowed | **Yes** |
| `RIDE_COMPLETED` → `RIDE_CLOSED` remains independently allowed | **Yes** |
| Coupled to payment | **No** |
| Coupled to ride closure | **No** |
| Rating changes ride state | **No** |

---

### D2 — Rating direction

Both directions are supported:

| Direction | `ratingType` |
|-----------|--------------|
| Passenger rates assigned driver | `passenger_rates_driver` |
| Assigned driver rates passenger | `driver_rates_passenger` |

Server derives (client **must not** supply/override):

| Field | Derivation |
|-------|------------|
| `raterId` | Authenticated caller UID |
| `ratedId` | Passenger → `assignedDriverId`; Driver → `passengerId` |
| `ratingType` | From caller direction on the ride |

---

### D3 — Rating mutability

| Rule | Frozen |
|------|--------|
| Exactly one rating per direction per ride | **Yes** |
| Editable after create | **No** |
| Overwritable | **No** |
| Public API delete | **No** |
| Changed stars on new attempt after create | **Reject** |
| 15-minute edit window | **Not in Phase 2N** |

Later editability requires a separate architecture decision and slice.

---

### D4 — Rating content

**Stars only.**

Request body:

```json
{
  "stars": 1
}
```

Allowed integers: `1`, `2`, `3`, `4`, `5`.

**Reject:** `0`, negatives, `> 5`, decimals, strings, `null`, missing `stars`, arrays/objects.

**Deferred:** tags, comments, review text, moderation, sentiment analysis.

---

### D5 — Authoritative storage

```text
ratings/{rideId}_{ratingType}
```

Examples:

```text
ratings/ride123_passenger_rates_driver
ratings/ride123_driver_rates_passenger
```

| Forbidden | Frozen |
|-----------|--------|
| Subcollection `rides/{rideId}/ratings` | **Do not use** |
| Users/drivers as authoritative rating SoT | **Do not use** |
| Another rating collection | **Do not create** |

The rating document is the **source of truth**.

---

### D6 — No ride denormalization

**Do not write** during Phase 2N:

- `rides.passengerRating`
- `rides.driverRating`

(Historical schema fields remain deferred.)

Rating write **must not** modify the ride document:

- no `ride.version` increment  
- no `ride.updatedAt` mutation  
- no ride state mutation  
- no ride denormalization  

---

### D7 — No user/driver aggregates

Phase 2N **does not** update:

`users.rating`, `drivers.rating`, `drivers.ratingCount`, `drivers.noShowCount`

No running averages, counters, ranking, reputation, or matching changes.

No Redis, Cloud Functions, distributed counters, or other aggregation systems.

---

### D8 — Ride version

Rating submission **must not** bump the ride aggregate version.

Rating is **not** a ride state-machine transition.

The rating transaction may **read** the ride for authorization/lifecycle validation; it must **not** update the ride.

---

### D9 — API contract

Future implementation:

| Method | Path |
|--------|------|
| `POST` | `/v1/rides/:rideId/ratings` |
| `GET` | `/v1/rides/:rideId/ratings` |

**POST requires:**

- `Authorization: Bearer <Firebase JWT>`
- `Idempotency-Key: <key>`

**POST body:**

```json
{
  "stars": 1
}
```

Server derives: `rideId` (URL), `raterId` (UID), `ratedId` (ride fields), `ratingType` (direction).

---

### D10 — GET visibility

`GET /v1/rides/:rideId/ratings` is **participant-scoped**.

Phase 2N returns **only the caller’s own rating** for that ride.

| Forbidden | Frozen |
|-----------|--------|
| Counterpart rating exposure | **No** |
| Public ratings | **No** |
| Public user rating-history endpoint | **No** |
| Rating objects on `GET /v1/rides` list | **No** |
| New history filter | **No** |

---

### D11 — Idempotency

POST requires `Idempotency-Key` via existing Ora idempotency machinery.

Bind record to: authenticated actor, request hash, `rideId`, `ratingType`, `stars`, operation name.

| Case | Result |
|------|--------|
| Same key + same body | Replay original success |
| Same key + different body | `IDEMPOTENCY_KEY_REUSED` |
| Different key after rating exists | `ALREADY_RATED` **or** existing equivalent conflict code chosen at implementation |
| Overwrite existing rating | **Forbidden** |

Natural document ID is also a uniqueness boundary.

---

### D12 — Concurrency

| Scenario | Result |
|----------|--------|
| Same participant concurrent submits | Exactly one rating doc; one logical mutation; one outbox event; others → replay/conflict |
| Passenger + driver concurrent | Two independent docs (both directions valid) |
| Rating vs close | Both legal; neither corrupts the other |
| Eligible states | Both `RIDE_COMPLETED` and `RIDE_CLOSED` remain valid |

---

### D13 — Event / outbox

Emit **`ride.rating.submitted`** atomically with the rating document.

**Payload:**

```json
{
  "rideId": "<string>",
  "ratingId": "<string>",
  "ratingType": "passenger_rates_driver | driver_rates_passenger",
  "raterId": "<uid>",
  "ratedId": "<uid>",
  "stars": 1
}
```

Do **not** duplicate envelope fields (`eventId`, `occurredAt`, `aggregateVersion`, `correlationId`, `causationId`, …) inside the payload.

**Causation ID:** Idempotency-Key.

No payment, GPS, display names, or review text in the payload.

---

### D14 — Security

All rating mutations are backend-mediated.

Existing `firestore.rules` deny client read/write on `ratings/{id}` — **do not weaken**.

Server **must** verify: authenticated caller; passenger or assigned driver; ride exists; eligible state; not self-rating; `ratedId` / `ratingType` derived; rating doc does not already exist.

Must never succeed for: another person’s ride; arbitrary other drivers/passengers; self; `NO_SHOW`; `CANCELLED`; `EXPIRED`.

---

### D15 — History

Do **not** change the Phase 2I history contract.

`GET /v1/rides` unchanged. No `status=rated` / rating filters.

Ratings via `GET /v1/rides/:rideId/ratings` only.

Ride = SoT for lifecycle; `ratings` = SoT for ratings.

---

### D16 — Offline / retry

Server is authoritative.

| Client behavior | Server result |
|-----------------|---------------|
| Retry same Idempotency-Key after lost response | Replay |
| New key after rating exists | `ALREADY_RATED` / conflict |
| Same key, different stars | `IDEMPOTENCY_KEY_REUSED` |

No client assumption may create a duplicate rating.

---

### D17 — Explicit non-goals

Phase 2N **must not** implement:

payment, fees, tips, wallet, ledger, driver earnings/payout, `noShowCount`, rating averages, `ratingCount`, reputation, matching/ranking, moderation, reporting, comments, tags, review text, editable ratings, public rating history, counterpart visibility, Maps, GPS, dispatch, FCM, Redis, RTDB, unrelated ride refactors, ride state changes.

---

### D18 — Implementation boundary

Future implementation is a greenfield rating slice. It **must not** alter:

existing ride state transitions; close; NO_SHOW; expiry; offers; assignment; payment architecture; ride version semantics.

The rating aggregate is **independent**.

---

### D19 — Testing requirements (future implementation)

**Unit:** passenger/driver valid; COMPLETED/CLOSED allowed; pre-completion / CANCELLED / EXPIRED / NO_SHOW rejected; non-participant; self-rate impossible; invalid stars; duplicate; same-key replay; same-key different body; different-key duplicate; no ride version/state change; no aggregate writes; event contract; authorization.

**Live Firestore:** normal both directions; persisted docs + exact IDs; outbox; same-key retry; changed-body; concurrent same-user (2-way + 10-way); both participants concurrent; rating vs close; NO_SHOW/CANCELLED rejection; unauthorized; GET visibility.

**Regression (executed, not assumed):** 2E, 2F, 2G, 2H, 2I, 2J, 2K, 2L, 2M.

---

## 6. API contract (summary)

```text
POST /v1/rides/:rideId/ratings
  Authorization: Bearer <Firebase JWT>
  Idempotency-Key: <key>
  Body: { "stars": 1|2|3|4|5 }

GET /v1/rides/:rideId/ratings
  Authorization: Bearer <Firebase JWT>
  Returns: caller's own rating only (or empty/not-found equivalent)
```

---

## 7. Firestore storage contract

| Item | Contract |
|------|----------|
| Collection | `ratings` |
| Document ID | `{rideId}_{ratingType}` |
| SoT | Rating document |
| Ride document | **Read-only** during rating txn |
| Client rules | Remain deny-all (`allow read, write: if false`) |
| Indexes for MVP write/GET-by-id | Not required for primary path |

Minimum rating document fields (implementation may add timestamps consistent with existing ISO string conventions):

```text
rideId, raterId, ratedId, ratingType (or role), stars, createdAt (or timestamp)
```

Stars only — no tags/comment in Phase 2N.

---

## 8. Authorization

| Check | Required |
|-------|----------|
| Firebase JWT | Yes |
| `uid` is `passengerId` or `assignedDriverId` | Yes |
| Eligible state | `RIDE_COMPLETED` \| `RIDE_CLOSED` |
| Direction → counterpart | Server-derived only |
| Self-rate | Impossible / rejected |
| Direct Firestore client write | Denied by rules |

---

## 9. Idempotency

Existing `idempotencyRecords` machinery; actor + hash binding; replay vs `IDEMPOTENCY_KEY_REUSED`; natural key uniqueness; no overwrite.

---

## 10. Concurrency

Firestore transaction is the correctness boundary. One doc/event per direction. Cross-direction independent. Close ∥ rating safe.

---

## 11. Outbox event

| Field | Value |
|-------|-------|
| `eventType` | `ride.rating.submitted` |
| Atomic with | Rating document create |
| `causationId` | Idempotency-Key |
| Payload | Per D13 |

**Implementation note (not a product decision):** because ride `version` is not bumped, outbox `aggregateVersion` / `aggregateId` strategy must be chosen consistently with existing envelope conventions at implementation time (e.g. rating doc as aggregate, or ride id with non-bumped observed version). Payload must still match D13 exactly.

---

## 12. History behavior

Unchanged Phase 2I list/get-ride surfaces. No rating filter. Ratings only via GET ratings endpoint.

---

## 13. Offline / retry behavior

Same Idempotency-Key → replay. New key after create → conflict. Same key different stars → `IDEMPOTENCY_KEY_REUSED`. Server authoritative.

---

## 14. Testing gate

Phase 2N may close only when D19 unit + live Firestore + 2E–2M regression evidence is actually executed. No assumed passes.

---

## 15. Explicit non-goals

See **D17**. Additionally deferred vs historical docs:

- `rides.passengerRating` / `rides.driverRating` denorm  
- `users.rating` / `drivers.rating` / `ratingCount`  
- Tags/comment on `ratings`  
- 15-minute editable window (architecture-final condition closure)  
- Counterpart / public visibility  

---

## 16. Risks

| Risk | Notes |
|------|-------|
| Schema docs list denorm/aggregates/tags | **Deferred by freeze** — do not implement in 2N |
| `ALREADY_RATED` not yet in `docs/api/error-codes.md` | Freeze allows equivalent existing conflict code; add or map at implementation |
| `ride.rating.submitted` not yet in event-contracts | Add during implementation to match D13 |
| Doc ID example in schema (`…_passenger`) vs freeze (`…_passenger_rates_driver`) | **Freeze wins** — use full `ratingType` suffix |
| Outbox `aggregateVersion` without ride bump | Implementation detail; must not bump ride version (D8) |
| `assignedDriverId == null` on completed ride | Reject rating (cannot derive counterpart) |

None of these block starting implementation once this freeze is the contract.

---

## 17. Implementation checklist

Future Phase 2N implementation must:

1. [ ] Add rating service + routes under existing `/v1/rides` auth  
2. [ ] POST/GET contracts per D9–D10  
3. [ ] Write `ratings/{rideId}_{ratingType}` only; **no** ride/user/driver mutations  
4. [ ] Idempotency-Key + natural uniqueness  
5. [ ] Atomic `ride.rating.submitted` outbox (D13)  
6. [ ] Keep Firestore rules deny-all on `ratings`  
7. [ ] Do not add speculative indexes unless a query requires them  
8. [ ] Do not change ride SM / close / NO_SHOW / history filters  
9. [ ] Unit proofs per D19  
10. [ ] Live Firestore proofs per D19  
11. [ ] Regressions 2E–2M executed  
12. [ ] Closure doc only after evidence  

---

## Repo compatibility verification

| Area | Compatible? |
|------|-------------|
| Eligibility on COMPLETED∪CLOSED; not NO_SHOW/CANCELLED | Yes — matches investigation lean; no SM change required |
| Independent of payment/close | Yes — ADR / 2H already separate payment & close |
| Two-way directions | Yes — matches product + schema roles |
| Immutable stars-only | Yes — greenfield; overrides aspirational edit window / tags for 2N |
| `ratings/{id}` SoT; no ride/user writes | Yes — runtime has no rating fields/writes today |
| Idempotency + outbox patterns | Yes — reuse close/complete style |
| Rules deny client `ratings` | Yes — already present |
| History unchanged | Yes — 2I filters unchanged |
| Phase 2M untouched | Yes — freeze forbids SM/NO_SHOW changes |

**No architecture conflict prevents implementation.** Documented schema extras (denorm, aggregates, tags, edit window) are explicitly deferred by this freeze, not blockers.

---

## Final verdict

All decisions D1–D19 are recorded as the authoritative Phase 2N contract.

### READY FOR PHASE 2N IMPLEMENTATION
