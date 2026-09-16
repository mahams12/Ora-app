# Phase 2H — Architecture / Invariant Investigation

**Date:** 2026-09-09  
**Status:** INVESTIGATION ONLY — no production code modified  
**Verdict:** see §24

---

## 1. Executive summary

Phases 2C–2G closed the marketplace + post-assignment operational path through **`RIDE_COMPLETED`**.

In **running code**, `RIDE_COMPLETED` is a success terminal (`state_machine.ts` `TERMINAL`). There is **no** `RIDE_CLOSED` state, no close API, no setter for `closedAt`, and no payment/rating/history implementations.

Locked architecture (`docs/ORA_STATE_MACHINE.md`, `docs/architecture-final/03-state-machines.md`, Phase 0.6/0.7) still requires:

`RIDE_COMPLETED → RIDE_CLOSED` (server; ride-aggregate terminal)

ADR-008 + concurrency Case 28 allow **`RIDE_CLOSED` without payment settlement**.

**Recommended Phase 2H:**

> **Ride aggregate closure vertical slice**  
> Implement `RIDE_COMPLETED → RIDE_CLOSED` on the existing `rides/{rideId}` aggregate with durable idempotency, Firestore transactions, version bump, `closedAt`, and outbox — **without** payments, Maps, RTDB, Redis, FCM, ratings UI, or history list.

This is the smallest coherent **domain** continuation of the verified lifecycle.  
`GET /v1/rides` history is valuable and contract-backed but is a **read/query** slice that does not complete the state machine; it should follow or be a separate micro-phase after closure semantics exist.

---

## 2. Current verified architecture

### Inspected

| Area | Path |
|------|------|
| Ride module | `backend/auth-service/src/rides/*` |
| States / gates | `types.ts`, `state_machine.ts` |
| Service / routes | `ride_service.ts`, `routes.ts` |
| Tests / harnesses | `rides.test.ts`, `run_ride_proof.ts`, live Firestore concurrency scripts |
| Flutter ride domain | `mobile/lib/features/ride/**` |
| Closure docs | `docs/implementation/phase-02e*.md`, `phase-02f*.md`, `phase-02g*.md` |
| Locked SM / API / events | `ORA_STATE_MACHINE.md`, `ride-api.md`, `04-api-contracts.md`, `event-contracts.md`, ADR-008, Case 28 |
| Later phases | `phase-09-realtime.md`, `phase-10-trip.md`, `phase-11-payments.md`, `phase-06-driver-system.md` |

### Implemented lifecycle (code)

```
SEARCHING → OFFERS_AVAILABLE → DRIVER_ASSIGNED
  → DRIVER_EN_ROUTE → DRIVER_ARRIVED → RIDE_STARTED → RIDE_COMPLETED
  | CANCELLED | EXPIRED
```

APIs: create, get-by-id, offers CRUD/select, cancel (pre+post assign), en-route, arrive, start, complete.  
Outbox write-only through `ride.completed` / `ride.cancelled`.  
No `GET /v1/rides` list. No close. No payments. No ratings. No go-online.

---

## 3. Current state machine (code vs contract)

| State | In code? | Role today |
|-------|----------|------------|
| … through `RIDE_COMPLETED` | Yes | Operational success end |
| `CANCELLED` / `EXPIRED` | Yes | Terminal (cancel / reserved expiry) |
| `RIDE_CLOSED` | **No** | Contracted ride-aggregate terminal after complete |
| `DRIVER_CANCELLED` / `PASSENGER_CANCELLED` / `NO_SHOW` | No | Full SM; 2E/2G kept single `CANCELLED` |

`RideDoc.closedAt` exists, always `null`, not exposed in `publicRide()`.

**`RIDE_COMPLETED` should NOT remain the final aggregate terminal** once Phase 2H lands — contracts distinguish operational complete vs aggregate close. Until 2H, treating COMPLETED as terminal in code is correct for 2G DoD.

---

## 4. Closed-phase invariants that must not regress

1. Exactly one `assignedDriverId` after select; assignment sole path to `DRIVER_ASSIGNED`.  
2. `agreedFare*` immutable after assignment.  
3. Durable idempotency (key + hash + actor) in Firestore.  
4. Outbox atomic with mutations; no external publish required yet.  
5. Strict progression ordering (2G).  
6. Post-assign cancel only before complete; retain assignee on cancel.  
7. Client never writes authoritative ride/offer docs.  
8. Live Firestore concurrency proofs for assignment / offer-create / progression remain green.  
9. ADR-008: no payment writes forced by ride mutations.

---

## 5. Candidate next slices (evaluated)

| Candidate | Prerequisites | Infra | Fits now? | Rework risk |
|-----------|---------------|-------|-----------|-------------|
| **A. `RIDE_CLOSED` closure** | `RIDE_COMPLETED` exists | None beyond txn/idempotency/outbox | **Yes — recommended** | Low if payment-free |
| **B. `GET /v1/rides` history** | Auth + ride docs | Indexes/pagination | Yes as read slice | Low; better after CLOSED for status filters |
| **C. Ratings** | Completed/closed ride | New `ratings` collection/API | Later | Medium if before close semantics |
| **D. Outbox consumers / FCM** | Events exist | Pub/Sub/FCM | No (Phase 9+) | High if forced now |
| **E. Driver go-online** | Auth | Redis GEO + RTDB (Phase 6) | No | High |
| **F. Dispatch/matching** | Online drivers + location | Redis/RTDB/waves | No | High |
| **G. GPS/Maps** | Phase 4 | Maps SDKs, location API | No | High |
| **H. Payments** | Agreed fare; Phase 11 deps | Ledger/PSP/wallet | No — ADR separates | High if merged into close |
| **I. NO_SHOW / EXPIRED sweepers** | Timers | Cloud Scheduler/workers | Later | Medium |
| **J. Fold close into `complete`** | — | None | Reject — collapses contracted two states | High product/SM rework |

**Rejected for Phase 2H:** C–J as primary scope.  
**Deferred but adjacent:** B (history) — recommend Phase 2I or immediate follow-on after 2H, not mixed into closure DoD unless explicitly expanded.

---

## 6. Recommended Phase 2H boundary

### In scope

1. Add `RIDE_CLOSED` to `RideState`.  
2. Transition **only** `RIDE_COMPLETED → RIDE_CLOSED`.  
3. Set `closedAt` (server time); bump `version` once.  
4. Durable idempotency + Firestore transaction + outbox event.  
5. Authorization: authenticated **passenger owner or assigned driver** may request close (server still authoritative — see open questions).  
6. Expose `closedAt` on `publicRide`.  
7. Update terminal gates: `RIDE_CLOSED` immutable; no cancel/progress from CLOSED; COMPLETED no longer in “final terminal” set once CLOSED exists.  
8. Flutter domain/data use case only (no UI).  
9. Tests + live Firestore concurrency proof for close races.

### Out of scope

Payments/wallet/ledger, receipt generation, ratings, history list, Maps/GPS, RTDB, Redis, FCM, NO_SHOW/sweepers, Admin, Cargo/Delivery, UI, changing assignment/offer/progression contracts.

### Why this is the smallest coherent slice

1. **State machine incomplete:** contracts require COMPLETED → CLOSED; code stops at COMPLETED.  
2. **No new infra:** same modular-monolith patterns as 2E–2G.  
3. **ADR-008 compliant:** Case 28 explicitly allows CLOSED while payment pending — 2G’s “depends on payment consumers” is ops commentary, not a hard invariant. Prefer ADR/Case 28.  
4. **Unblocks later slices:** ratings/history/payments can key off CLOSED or COMPLETED without inventing ad-hoc “isDone” flags.  
5. **Not wishlist-driven:** continues the exact verified chain rather than jumping to Maps/dispatch.

---

## 7. Why not history / ratings / payments / realtime first?

- **History:** MVP and contract-backed, but does not finish the SM; filtering `completed|cancelled` is ambiguous until CLOSED exists; can be 2I.  
- **Ratings:** new aggregate; product places after trip; needs clear terminal predicate; no code stubs.  
- **Payments:** Phase 11; separate aggregate; would expand 2H into ledger/PSP.  
- **Realtime/GPS/dispatch:** Phase 6/9/10; RTDB/Redis/Maps.  

---

## 8. State-machine impact

### Add

`RIDE_CLOSED`

### Legal transition

| From | To | Actor | Mechanism |
|------|----|-------|-----------|
| `RIDE_COMPLETED` | `RIDE_CLOSED` | Passenger owner **or** assigned driver (recommended) / server | `POST /v1/rides/:rideId/close` |

### Illegal

- Close from any state other than `RIDE_COMPLETED`  
- Backward from CLOSED  
- Cancel/progress after COMPLETED or CLOSED  
- Client-supplied `state` / `closedAt`  
- Close without assignment snapshot on a completed ride (should already exist)

### Terminal behavior

| State | After 2H |
|-------|----------|
| `RIDE_CLOSED` | Aggregate terminal (immutable) |
| `CANCELLED` / `EXPIRED` | Remain terminals (no path to CLOSED) |
| `RIDE_COMPLETED` | Operationally done; **awaiting close** |

### Cancellation / expiry

Unchanged: no cancel after COMPLETED (2G). No new expiry for CLOSED.

---

## 9. Data-model impact

| Collection | Change |
|------------|--------|
| `rides/{rideId}` | New state; set `closedAt`; version++ |
| New collections | **None** |
| `idempotencyRecords` | Operation `RIDE_CLOSE` |
| `outboxEvents` | New event type (recommended `ride.closed`) |
| Read models | Not required for close |

**Server-authoritative:** `state`, `version`, `closedAt`, timestamps, identities, assignment/fare snapshots (unchanged).

**Historical immutability:** after CLOSED, ride document fields for fare/assignment/lifecycle must not be rewritten (same as other terminals).

---

## 10. API impact

### New

**`POST /v1/rides/:rideId/close`**

- Auth: passenger owner or assigned driver (recommendation)  
- `Idempotency-Key`: required  
- Body: `{}` or `{ "expectedVersion": n }` — reject unknown keys  
- Success: 200 + public ride (`RIDE_CLOSED`, `closedAt`, version+1)  
- Errors: `FORBIDDEN`, `RIDE_NOT_FOUND`, `STATE_CONFLICT`, `VERSION_CONFLICT`, `IDEMPOTENCY_KEY_REUSED`, `VALIDATION_ERROR`

### Not in 2H

`GET /v1/rides` history (unless scope explicitly expanded).  
No payment fields on response beyond existing `agreedFare*`.

Note: `ride-api.md` sample for complete mentions `paymentIntentId` — **must remain null** in 2H (ADR-008).

---

## 11. Authorization / security

| Check | Rule |
|-------|------|
| Close | `uid === passengerId` OR `uid === assignedDriverId` |
| Foreign actor | `FORBIDDEN` |
| Forged ids in body | Rejected via `rejectUnknownKeys` + token identity |
| Direct Firestore client write | Still denied by rules |

Server derives actor from verified token only.

---

## 12. Idempotency

Reuse existing durable records:

- Same key + same hash + same actor → replay (no second close / no double version)  
- Same key + different body/actor → `IDEMPOTENCY_KEY_REUSED`  
- Different key when already CLOSED → success snapshot without version bump (mirror 2G already-at-target) or `STATE_CONFLICT` — **prefer already-at-target replay pattern** for close consistency with en-route/complete  

Concurrency token: `ride.version` / optional `expectedVersion` (not `requestVersion`).

---

## 13. Concurrency model

| Race | Legal outcome |
|------|----------------|
| Concurrent close (2/10/50) | Exactly one version bump; one `closedAt`; one outbox close event |
| Same idempotency key concurrent | Both 200 replay; version +1 once |
| Different keys after success | Already CLOSED → replay/conflict without second mutation |
| Close vs cancel | Cancel already illegal on COMPLETED → close only |
| Close when not COMPLETED | `STATE_CONFLICT` |
| Stale `expectedVersion` | `VERSION_CONFLICT` |
| Crash before commit | No mutation; retry |
| Crash / timeout after commit | Idempotent replay |

Firestore **transaction required** for close mutation.  
**Not required:** pure GETs (if any).

---

## 14. Transaction boundaries

Single txn per close:

1. Idempotency read/assert  
2. Ride read  
3. Auth + `state === RIDE_COMPLETED` (or already CLOSED → snapshot)  
4. Optional `expectedVersion`  
5. Write `state=RIDE_CLOSED`, `closedAt`, `version+1`, `updatedAt`  
6. Idempotency SUCCEEDED  
7. Outbox `ride.closed`  

Do not touch offers, payments, or other rides.

---

## 15. Outbox / event implications

| Event | When |
|-------|------|
| `ride.closed` | Successful COMPLETED→CLOSED |

Payload minimum: `{ rideId, fromState, toState, actorId }` + `aggregateVersion`.  

**Note:** `event-contracts.md` does not yet list `ride.closed`; Phase 2H implementation should add it to the durable ride event set (contract extension justified by SM). Still write-only; no FCM/RTDB consumers.

Do **not** emit payment events.

---

## 16. Failure / retry semantics

| Case | Expected |
|------|----------|
| Success | 200 + CLOSED ride |
| Unauthorized | 403 |
| Wrong state | 409 `STATE_CONFLICT` |
| Stale version | 409 `VERSION_CONFLICT` |
| Idempotent replay | Original success |
| Key reuse | 409 `IDEMPOTENCY_KEY_REUSED` |
| Txn contention | SDK retries; one winner |

---

## 17. Observability / debugging plan

Structured logs (no PII beyond ids already used):

| Field | Purpose |
|-------|---------|
| `correlationId` / `requestId` | Trace |
| `operation` = `RIDE_CLOSE` | Classify |
| `actorType` = passenger\|driver | Auth path |
| `actorId` | Token uid |
| `rideId` | Aggregate |
| `fromState` / `toState` | SM |
| `expectedVersion` / `resultingVersion` | Concurrency |
| `idempotencyOutcome` = miss\|replay\|reuse | Idempotency |
| `txnOutcome` = committed\|conflict\|error | Persistence |
| `outboxEventType` / `outboxEventId` | Event audit |
| `error.code` | Failure category |

Do **not** log: phone numbers, precise lat/lng payloads (none in close body), fare beyond existing safe codes, tokens.

Reuse existing `logSafe` pattern from routes (`ride_complete_failed`, etc.).

---

## 18. Test matrix (future implementation)

### Positive

- COMPLETED → CLOSED happy path  
- `closedAt` set; version +1; agreed fare unchanged  
- Idempotent same-key replay  
- Already CLOSED + new key → deterministic success/conflict per chosen rule  

### Negative

- Passenger/driver foreign close  
- Close from STARTED/ASSIGNED/CANCELLED  
- Unauthenticated  
- Forged body fields  
- Stale expectedVersion  
- Cancel after CLOSED  

### Idempotency

Same key same body; same key different body; different actor; timeout replay  

### Concurrency

2/10/50-way concurrent close → one persisted CLOSED; one outbox event  

### Persistence

Verify Firestore ride + idempotency + outbox documents  

### Regression

2E proof, 2F offer live, 2G progression live, vitest rides suite  

---

## 19. Live Firestore proof plan

New harness (implementation phase):  
`scripts/run_ride_close_firestore_concurrency.ts`  
+ `npm run test:ride-close-firestore-concurrency`

Must use emulator + firebase-admin + real `runTransaction` + contention instrumentation + persisted asserts.

Minimum live cases: happy close; 2/10/50 concurrent close; same-key concurrent; close when not completed; fare/assignee immutable.

MemoryDb ≠ final proof.

---

## 20. Risks

| Risk | Mitigation |
|------|------------|
| Interpreting “server ONLY” as no client API | Treat as server-authoritative decision; authenticated request allowed (open Q1) |
| Vacuous close without payment | Document ADR-008; close ≠ paid |
| History filters incomplete | Keep history out of 2H |
| Event contract missing `ride.closed` | Add during 2H with SM justification |
| Auto-close temptation on complete | Reject — preserves two-state contract |
| TERMINAL set still includes COMPLETED | Update gates carefully so COMPLETED allows only close |

---

## 21. Non-goals

Maps, GPS, geofencing, RTDB, Redis, FCM, payments/wallet/ledger, ratings, `GET /v1/rides` history (unless separately approved), NO_SHOW sweepers, Admin, Cargo, Delivery, UI, navigation, ML matching, offer/assignment redesign.

---

## 22. Implementation plan (for next prompt only — do not execute here)

1. Add `RIDE_CLOSED` to types; update `state_machine` terminal/progress gates.  
2. Implement `closeRide` in `RideService` (txn + idempotency + outbox).  
3. Wire `POST /:rideId/close`.  
4. Extend `publicRide` with `closedAt`.  
5. Flutter: parse `closedAt` / state; `CloseRideUseCase` + repo/datasource.  
6. Vitest matrix (§18).  
7. Live close concurrency harness (§19).  
8. Regression 2E/2F/2G suites.  
9. Closure doc `phase-02h-*.md`.  

---

## 23. Definition of Done

1. COMPLETED→CLOSED works with auth, versioning, idempotency, outbox.  
2. Illegal transitions/actors rejected.  
3. Fare/assignment immutable across close.  
4. Live Firestore close concurrency proven.  
5. 2E/2F/2G regression green.  
6. No payments/Maps/RTDB/FCM/history/ratings in scope.  
7. Limitations documented.  

---

## 24. Open questions

| # | Question | Recommendation |
|---|----------|----------------|
| 1 | Who may call close — passenger/driver vs system-only worker? | Passenger **or** assigned driver (no worker in 2H) |
| 2 | Event name? | `ride.closed` (extend event contracts) |
| 3 | Auto-close inside `complete`? | **No** |
| 4 | Include `GET /v1/rides` in 2H? | **No** — Phase 2I candidate |
| 5 | Already-CLOSED + new idempotency key? | Return success snapshot (2G pattern) |
| 6 | Should ratings require CLOSED vs COMPLETED? | Defer to ratings phase; either COMPLETED or CLOSED acceptable later |
| 7 | Cancelled rides and `closedAt`? | Leave null; CANCELLED already terminal |

---

## Final verdict

# READY FOR PHASE 2H IMPLEMENTATION

### Exact implementation boundary for the next prompt

**Phase 2H — Ride Aggregate Closure**

Implement only:

`RIDE_COMPLETED → RIDE_CLOSED`

via `POST /v1/rides/:rideId/close` on the existing ride aggregate, with:

- server-set `closedAt`
- durable idempotency + Firestore `runTransaction` + version increment
- outbox `ride.closed` (atomic)
- passenger-or-assigned-driver authorization
- Flutter domain/data only
- unit + **live Firestore** concurrency proof
- no payments, Maps, GPS, RTDB, Redis, FCM, ratings, history list, UI, or sweepers

---

### Hard stop

- Production code **not** modified in this investigation  
- Phase 2H **not** implemented  
- Phase 2I+ **not** started  

### Inspected vs unknown

**Inspected:** ride module post-2G, SM, APIs, outbox, Flutter use cases, 2E–2G docs, ORA SM, ADR-008, Case 28, payment/trip/realtime/driver phase docs, ride history contract.  

**Unknown / decisions:** §24 open questions (actor for close, event naming, history sequencing) — none block starting implementation under the recommendations above.
