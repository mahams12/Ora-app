# D1 — Dispatch Invite Delivery MVP (Decision Freeze)

**Status:** **IMPLEMENTED** (2026-09-21) + **H2/H4/H5/H6 hardened** (2026-09-22) — **YELLOW** closure: real FCM Admin send **NOT PROVEN** in CI (stubbed at FCM boundary; enable `ORA_D1_REAL_FCM=1` + `ORA_D1_TEST_FCM_TOKEN` for live send). H1 sweep-query scaling remains deferred.  
**Freeze date:** 2026-09-21  
**Slice ID:** `D1`  
**Slice name:** Dispatch Invite Delivery MVP  
**Authority:** This freeze + code under `backend/auth-service/src` + ADR-005 + N4 freeze.  
**Live snapshot:** [`docs/ORA_CURRENT_STATE.md`](../../ORA_CURRENT_STATE.md)  
**Template:** [`docs/implementation/PHASE_TEMPLATE.md`](../PHASE_TEMPLATE.md)

**Depends on (CLOSED):** N1, N2A, N2C, N3, **N4 Dispatch MVP**, existing `createOffer` / `selectOffer`, Firestore `outboxEvents` PENDING writers (including `ride.dispatch.wave_completed`).  
**Does not depend on:** N2B, RTDB, WebSockets, PBS catalog, city matching, COUNT-100 refill, N4 H1–H8 fixes.

**Must not become:** assignment, auto-offer, auto-accept, offer fabrication, city matching, N2B tripLocations, full multi-subscriber outbox platform, Pub/Sub mesh, RTDB `rideRequests` cards.

**Implementation (code):**
- `POST/DELETE /v1/drivers/device-tokens`
- `POST /v1/internal/outbox/dispatch-fcm-sweep`
- Collections: `driverDeviceTokens`, `outboxDeliveries`
- Services: `delivery/device_token_service.ts`, `delivery/dispatch_fcm_projector.ts`, `delivery/fcm_sender.ts`

---

## Decision

**Exact next engineering slice:** **`D1` — Dispatch Invite Delivery MVP**

**Observable capability:** After N4 writes a durable wave invite ledger, invited drivers receive a **best-effort FCM data-message wake-up** so they can open the app and act through the **existing** offer flow. Delivery is **not** assignment and **not** offer creation.

**Identifier convention:** `D1` is the first **Delivery** slice after N4. It is **not** `N5` (no N5 series id exists). It lives under `docs/implementation/n-series/` because it consumes the N4 ledger.

---

## Context

N4 Dispatch MVP is **CLOSED** (durable `rideDispatchWaves` + ride dispatch cursors; waves 5/10/15; max 30; 5s; 10 km; coordinate-primary N3). N4 **D-DELIVERY** deferred actual driver wake-up.

Roadmap cluster after N4 (`ORA_CURRENT_STATE`): **Delivery / N2B / outbox projector** — previously unordered. This freeze **orders** that cluster for the next implementable slice.

N4 hardening residual items **H1–H8** remain deferred and are **not** prerequisites for D1 (see below).

---

## Problem

Today, after N4:

```text
Passenger creates ride
  → N3 discovers nearby drivers
  → N4 persists invite ledger + outbox ride.dispatch.wave_completed PENDING
  → ✗ nothing consumes the outbox
  → ✗ invited drivers are not woken
  → drivers only discover rides via M0 pull (GET /v1/rides/open)
```

N4’s invite ledger and `ride.dispatch.wave_completed` events therefore have **no delivery path**. That is the product gap D1 closes.

---

## Chosen Architecture

### MVP delivery mechanism

| Layer | Choice |
| ----- | ------ |
| Durable intent | Existing N4 wave ledger + existing `outboxEvents` row (`ride.dispatch.wave_completed`) |
| Projector | **Minimal outbox projector** (worker-authenticated), D1-scoped |
| Wake channel | **FCM data-only messages** to invited `driverIds` |
| Pub/Sub | **Not required for D1** — projector may call FCM Admin SDK directly |
| RTDB `rideRequests` cards | **Deferred** (not D1) |
| Dedicated HTTP invite-poll API | **Deferred** (not D1) |
| Recovery if FCM misses | **M0** `GET /v1/rides/open` remains available |

### Dependency ordering (FROZEN)

```text
N4 CLOSED
  → D1 (this freeze): device token registration + minimal outbox→FCM for dispatch waves
  → D2+ (later freezes): optional invite-poll API; RTDB rideRequests cards; broader outbox subscribers
  → N2B: independently deferred (tripLocations) — NOT before D1
```

**Outbox projector is part of D1** (minimal, dispatch-FCM subscriber only) — not a separate preceding slice, and not a full ADR-005 multi-subscriber platform.

---

## Alternatives Considered

| Alternative | Factual tradeoff | Why not D1 MVP |
| ----------- | ---------------- | -------------- |
| **FCM via minimal outbox projector** (**CHOSEN**) | Matches ADR-005 (side effects from durable outbox); N4 already emits `ride.dispatch.wave_completed`; wakes backgrounded drivers; non-authoritative | — |
| **Polling-only invite API** | Fits existing Flutter HTTP-poll patterns (offers inbox); no FCM tokens; no projector | Does not wake backgrounded drivers; N4/CURRENT_STATE cluster groups delivery with **outbox / FCM**; poll remains deferred recovery/enhancement |
| **RTDB `rideRequests` cards** | Architecture-final primary in-app channel | RTDB not initialized; overlaps future realtime work; larger surface than wake-up; **not** N2B but still RTDB — deferred |
| **Outbox-projector-only (no FCM)** | Builds ADR-005 infra | Delivers **no** user-visible wake-up by itself |
| **N2B first** | Needed for live trip map UX | Explicitly **deferred** (`ENGINEERING_RULES` §16); solves trip GPS projection, **not** dispatch invite wake-up |
| **WebSockets** | Push without FCM | Not in Ora locked delivery architecture; would invent a new channel |

---

## Data Flow

```text
N4 tick/sweep (CLOSED)
  → Firestore txn: rideDispatchWaves/{rideId}_w{n} + ride cursors
                 + outboxEvents ride.dispatch.wave_completed PENDING
        ↓
D1 outbox projector (worker)
  → claim PENDING event (lease / attemptCount / nextAttemptAt)
  → read payload.driverIds[] (invited cohort)
  → for each driverId: lookup registered FCM device token(s)
  → send FCM data message (best-effort)
  → mark subscriber delivery ACKED / retry / dead-letter
        ↓
Driver device receives wake-up (non-authoritative)
        ↓
Driver app MUST revalidate via existing backend APIs
  → M0 open discovery and/or get ride
  → existing POST /v1/rides/:rideId/offers (createOffer)
  → passenger selectOffer (assignment)
```

Redis is **not** on this path. City is **not** on this path.

---

## Authorization

| Rule | Decision |
| ---- | -------- |
| Who may receive a D1 FCM wake-up | `driverId` present in the completed wave’s `driverIds` for that `ride.dispatch.wave_completed` payload |
| Token registration | Authenticated **approved driver** only; binds token to `req.caller.uid` (never client-supplied uid) |
| Can passenger/driver JWT invoke projector? | **No** — projector is **internal worker** (`X-Ora-Worker-Token`), same model as N4 sweep |
| Is FCM authoritative? | **No** — wake-up only |
| Must client re-read backend before offering? | **Yes** — ride must still be offerable; existing `createOffer` gates apply |
| Does createOffer require ledger membership? | **No for D1** — see H3 |

---

## H3 Relationship (N4 ledger role) — FROZEN

**D1 treats the N4 dispatch ledger as notification / invitation intent only.**

- FCM is sent **only** to drivers listed on the wave ledger (delivery targeting).
- **`RideService.createOffer` MUST NOT gain a ledger membership gate in D1.**
- M0 chronological open discovery **remains** a valid way for eligible drivers to find open rides.
- Making the ledger an **offer authorization gate** requires a **new freeze** (product change).

---

## Reliability

| Case | Semantics |
| ---- | --------- |
| Duplicate FCM | Safe — client dedupes by `eventId` / message id; re-read Firestore; createOffer remains idempotent |
| Delayed FCM | Safe — client revalidates; if ride no longer offerable → existing STATE_CONFLICT / errors |
| Stale FCM (assigned/cancelled/expired) | Safe — must not assign; client re-read; offer/select rejected by existing SM |
| Missed FCM / no token | Durable intent remains in Firestore; projector retries then dead-letters FCM subscriber; **M0 recovery** |
| Driver became ineligible after invite | FCM may still arrive; **createOffer** / eligibility rules remain authoritative |
| Projector crash | At-least-once via PENDING + attempts; must not double-assign (assignment not in D1) |

**Retry (architectural expectation, not implemented here):** follow ADR-005 / phase-1.6 outbox direction — bounded attempts with backoff for FCM subscriber (planning target ~10 attempts / 30 min), then dead-letter + ops signal. Exact numeric policy may be confirmed at implementation against `24-phase-1.6-condition-closure.md` §3 without changing this freeze’s product boundaries.

---

## State Ownership

| Store | Role in D1 |
| ----- | ---------- |
| **Firestore** | Authoritative ride state, N4 wave ledger, outbox intent, device token records |
| **Redis** | Unchanged — candidate GEO only; **not** used for delivery |
| **FCM** | Non-authoritative wake-up channel |
| **Client** | Non-authoritative; must revalidate before acting |
| **RTDB** | **Not used in D1** |

---

## N2B Relationship

**N2B (RTDB `tripLocations` / presence) remains independently DEFERRED.**

- Does **not** block D1  
- Does **not** run before D1  
- Does **not** run as part of D1  
- Trip live-map UX may require N2B later under an explicit start  

RTDB `rideRequests` pending cards (architecture-final) are **also deferred** and are **not** N2B; they are out of D1.

---

## Outbox Relationship

| Question | Answer |
| -------- | ------ |
| Is outbox projector a prerequisite? | **Yes — and it is inlined into D1** (minimal) |
| Separate projector-only slice before D1? | **No** |
| Full multi-subscriber outbox platform? | **Deferred** |
| Events D1 must handle | **`ride.dispatch.wave_completed` only** (other event types may remain PENDING untouched) |
| Pub/Sub required? | **No for D1** |

N4 already writes the event; D1 consumes it.

---

## Device token contract (FROZEN for D1 implementation)

D1 **must** introduce a server-authoritative device-token registration path (no tokens exist in code/schema today — freezing this removes the open question that would otherwise **block** FCM).

Conceptual contract (exact path may use `/v1/drivers/...` under existing driver JWT auth):

- **Actor:** approved driver (`caller.uid`)
- **Action:** upsert FCM registration token for that driver
- **Storage:** Firestore server-only collection/doc pattern (client SDK writes denied)
- **Delete/logout:** driver may clear own token(s)
- **Projector:** skips drivers with no usable token (counts as miss → M0 recovery); does not fail the whole wave

Payload guidelines: data-only FCM; include `type`, `rideId`, `waveNumber`, `eventId` (or equivalent references); **no** secrets, no fare authority, no assignment.

Suggested type string: `DISPATCH_INVITE` (distinct from architecture-final `NEW_RIDE_REQUEST` tied to `ride.created` / RTDB cards).

---

## Scope (D1 implementation boundaries)

**In scope when implementation is prompted:**

1. Driver FCM device-token register/clear API + Firestore persistence + rules deny client writes  
2. Minimal internal outbox projector worker endpoint (or scheduled worker entry) with existing worker auth  
3. Claim/process `ride.dispatch.wave_completed` → FCM to `payload.driverIds`  
4. Delivery attempt tracking sufficient for at-least-once + dead-letter for this subscriber  
5. Focused tests + proof harnesses (emulator/worker; FCM may be stubbed at Admin boundary with honest labels)  
6. Docs/status updates marking D1 IMPLEMENTED when exit criteria pass  

**Out of scope:** see Non-Goals.

---

## Non-Goals

- Payments / wallet / commission / tips  
- Maps / geocoding / live pricing  
- Automatic assignment or auto-accept  
- Fabricating `rideOffers`  
- City matching / PBS / homeCity gate  
- N3 redesign / COUNT-100 refill / N3 FS batching  
- N4 H1–H8 fixes  
- N2B tripLocations / driverPresence  
- RTDB `rideRequests` / `rideSignals`  
- WebSockets  
- Full Pub/Sub mesh / analytics sinks  
- Broad projector for all historical outbox event types  
- Replacing M0  
- Making ledger an offer authorization gate  
- Production App Check full rollout (unless already required by existing auth middleware for touched routes)  
- Flutter UI polish beyond what is needed to register tokens + handle data message wake (if a mobile sub-task is included in the implementation prompt)

---

## N4 Hardening Debt (H1–H8)

| Item | Prerequisite for D1? |
| ---- | -------------------- |
| H1 stop/exhaust hygiene | **No** |
| H2 cursor heal | **No** |
| H3 ledger ≠ offer gate | **No** — D1 **preserves** intent-only (explicitly frozen above) |
| H5 concurrent worker proof | **No** — D1 does not raise dispatch concurrency requirements |
| H6 sweep indexing | **No** |
| H7 orphan dispatchStatus | **No** |
| H8 N3 COUNT-100 / FS amplification | **No** — scale concern deferred |

---

## Security

- Projector: **internal worker token only**  
- Token registration: **driver JWT + approved driver**; IDOR-safe (own uid only)  
- FCM payload: references only; not SoT  
- Clients must not write `outboxEvents`, `rideDispatchWaves`, or token docs via Firestore SDK  
- Notification must not grant assignment privileges  

---

## Failure Model

| Failure | Behavior |
| ------- | -------- |
| FCM send fails | Retry with backoff; durable outbox remains; ride/wave unchanged |
| No device token | Skip driver; continue others; M0 recovery |
| Ride already terminal when FCM arrives | Client revalidation fails closed; no assign |
| Projector down | Events stay PENDING; catch-up when worker returns |
| Partial driver fan-out | At-least-once per driver attempt tracking; do not roll back N4 wave |

---

## Acceptance Criteria (for future D1 **implementation**)

1. Approved driver can register and clear an FCM device token via authenticated API.  
2. After N4 completes a wave, a worker projector processes `ride.dispatch.wave_completed` and attempts FCM to each `driverIds[]` entry with a registered token.  
3. Projector is unreachable without valid `X-Ora-Worker-Token`.  
4. Duplicate projector runs do not create duplicate durable ride/offer/assignment state.  
5. FCM failure does not mutate ride lifecycle or wave ledger incorrectly.  
6. D1 does **not** create `rideOffers` or write `assignedDriverId`.  
7. `createOffer` still succeeds for eligible drivers **without** requiring ledger membership (H3 preserved).  
8. Coordinate-primary / no city matching preserved.  
9. Focused unit tests + worker proof exist; FCM Admin boundary labeled honestly if stubbed.  
10. Prior N4 / ride / offer regression suites still pass.

---

## Migration / Rollback

- **Rollback:** disable projector worker / feature flag; N4 ledger and M0 continue; tokens may remain inert.  
- **No** Redis migration; **no** ride SM migration.

---

## Open Questions

**None** for D1 as frozen above.

(Deferred slices — D2 invite-poll, RTDB cards, full outbox platform, N2B — require their own freezes.)

---

## Documentation ↔ Code Mismatch (pre-implementation)

| Doc / reality | Note |
| ------------- | ---- |
| Architecture-final favors RTDB cards + FCM fallback | RTDB unimplemented; D1 chooses FCM-first wake + M0 recovery |
| `ORA_MASTER_PLAN.md` frontier still says N4 not implemented | **Stale** — CURRENT_STATE + this freeze win |
| No FCM token fields in current schema/code | D1 freeze **adds** token registration as in-scope contract |
| Event catalog omitted `ride.dispatch.wave_completed` | Exists in N4 code; D1 consumes it |

---

## Related

- [`N4-dispatch-planning.md`](N4-dispatch-planning.md)  
- [`ORA_CURRENT_STATE.md`](../../ORA_CURRENT_STATE.md)  
- [`DECISION_INDEX.md`](../../architecture/DECISION_INDEX.md)  
- ADR-005 Durable Outbox  
- [`14-notification-architecture.md`](../../architecture-final/14-notification-architecture.md)  
- [`ENGINEERING_RULES.md`](../../ENGINEERING_RULES.md)  

---

## Verdict

> **D1 is the frozen next engineering slice:** Dispatch Invite Delivery MVP = minimal outbox projector + FCM wake for N4 wave events + driver device-token registration.  
> **Do not implement D1 until an explicit implementation prompt.**  
> **N2B remains deferred. Ledger remains notification intent only (not offer gate).**
