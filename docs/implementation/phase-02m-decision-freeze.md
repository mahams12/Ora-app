# Phase 2M — Decision Freeze Verification

**Status:** DECISION FREEZE (no production code modified)  
**Date:** 2026-09-11  
**Basis:** `docs/implementation/phase-02m-architecture-investigation.md` + repository verification  
**Prior:** Phase 2L CLOSED (`arrivedAt` wait-clock)

---

## Verified decision matrix (D1–D6)

| ID | Decision | Repo compatibility | Status |
|----|----------|-------------------|--------|
| **D1** | `arrivedAt` authoritative; inclusive due `arrivedAt <= serverNow - 5m` | `RideDoc.arrivedAt` set once on arrive (2L); mirrors 2J `expiresAt <= now` inclusivity | **APPROVED / COMPATIBLE** |
| **D2** | No payment / fee / ledger / PSP / cancellationFee mutation | No NO_SHOW fee in payment docs; ADR-010; cancel today writes fee `0` without FeePolicy engine | **APPROVED / COMPATIBLE** |
| **D3** | History: visible under `status=all` only; not `completed`/`cancelled`; no new filter | `list_query.ts`: filters are only `all \| completed \| cancelled`; `EXPIRED` already all-only | **APPROVED / COMPATIBLE** |
| **D4** | Do not touch `drivers.noShowCount` | Field in schema/matching docs only; never written in code | **APPROVED / COMPATIBLE** |
| **D5** | `ride.no_show` atomic outbox; payload per § below | Type listed in event-contracts; no payload schema; peer = `ride.expired` | **APPROVED / COMPATIBLE** (shape frozen here) |
| **D6** | Skip `DRIVER_ARRIVED` + `arrivedAt == null`; no backfill/infer | 2L left legacy null clocks; no backfill exists | **APPROVED / COMPATIBLE** |

---

## D5 — Final exact `ride.no_show` payload

### Envelope (existing outbox — do not duplicate in payload)

Implemented fields on every outbox write:

```text
eventId, eventType, aggregateType, aggregateId, aggregateVersion,
schemaVersion, occurredAt, correlationId, causationId,
publishState, attemptCount, nextAttemptAt
```

Therefore:

| Candidate field | Disposition |
|-----------------|-------------|
| `occurredAt` | **Envelope only** — omit from payload |
| `rideId` | Keep in payload (same as `ride.expired` / progression) |
| `passengerId` | **Omit** — not on `ride.expired` / progression payloads; speculative |
| `assignedDriverId` | **Omit** — speculative vs sweeper-terminal peer |

### Closest peer: `ride.expired` (server timer → terminal)

```text
payload: {
  rideId,
  fromState,
  toState: "EXPIRED",
  reason: "search_ttl_elapsed",
  expiresAt
}
```

### Frozen Phase 2M payload

```json
{
  "rideId": "<string>",
  "fromState": "DRIVER_ARRIVED",
  "toState": "NO_SHOW",
  "reason": "arrived_wait_ttl_elapsed",
  "arrivedAt": "<ISO string from ride.arrivedAt>"
}
```

| Field | Why |
|-------|-----|
| `rideId` | Convention on sweeper + progression events |
| `fromState` / `toState` | Convention on `ride.expired` and progression |
| `reason` | Parallel to `search_ttl_elapsed` on `ride.expired` (only sweeper-terminal peer); not a new fee/product code |
| `arrivedAt` | Parallel to `expiresAt` on `ride.expired` — the clock that made the ride due |

**CausationId (envelope):** `no-show:{rideId}` (parallel to `expire:{rideId}`).  
**No Idempotency-Key** on worker path (state-based idempotency like 2J/2K).

---

## Terminal semantics — verified

| Rule | Source | Conflict with freeze? |
|------|--------|----------------------|
| `DRIVER_ARRIVED → NO_SHOW` | `ORA_STATE_MACHINE.md` | No |
| `NO_SHOW → ANY` forbidden (except admin) | SM §3 | No |
| No auto `NO_SHOW → RIDE_CLOSED` | SM: close only from `RIDE_COMPLETED` | No |
| No `STARTED` / `COMPLETED` / `CANCELLED` after NO_SHOW | Terminal + code gates to add | No |

**Pre-existing doc/code mismatch (not blocking 2M):** SM lists `PASSENGER_CANCELLED` / `DRIVER_CANCELLED`; code uses single `CANCELLED` + `cancelledBy`. Cancel-from-`ARRIVED` remains legal **until** NO_SHOW wins. Phase 2M must **not** reopen cancel taxonomy.

---

## Actor / sweeper / version / idempotency — verified

| Topic | Verification |
|-------|----------------|
| Actor | Server worker only; reuse `X-Ora-Worker-Token` / `ORA_INTERNAL_WORKER_TOKEN` (2J/2K) |
| Public API | None |
| Query | `state == DRIVER_ARRIVED` AND `arrivedAt <= now - 5m` |
| Txn re-read | Required: state, non-null `arrivedAt`, due check; else skip / already_no_show |
| Version | Exactly +1 on first transition; already `NO_SHOW` → no bump (mirror `already_expired`) |
| Idempotency | **State-based only**; no worker Idempotency-Key (same as expire sweeps) |
| Batch | default 100 / max 200 (2J/2K) |

---

## Offers — verified

Assignment txn supersedes PENDING siblings; `TERMINAL_FOR_OFFERS` already includes `DRIVER_ARRIVED`.

**Conclusion:** No PENDING marketplace offers are expected at NO_SHOW time. **Do not** add offer writes in Phase 2M. Add `NO_SHOW` to aggregate `TERMINAL` / `TERMINAL_FOR_OFFERS` so offers cannot reopen.

---

## Firestore index (plan only — not deployed)

```text
Collection: rides
Fields: state ASC, arrivedAt ASC
```

Required for the sweeper query. **Not created in this freeze step.**

---

## Implementation boundary (unchanged)

1. Add `NO_SHOW` to state machine / gates  
2. Server-controlled transition + bounded sweeper + worker route  
3. Index `state + arrivedAt`  
4. Atomic `ride.no_show` with frozen payload above  
5. Version / state-idempotency / concurrency  
6. Skip legacy null `arrivedAt`  
7. Tests + live proof + 2G–2L regressions  
8. Self-audit — nothing else (D2–D4 non-goals)

---

## FINAL VERDICT

All six decisions are compatible with existing authoritative contracts and implemented peer patterns (`arrivedAt`, 2J/2K sweepers, 2I history filters, ADR-010).

Terminal semantics match SM: NO_SHOW is terminal; no automatic close.

```text
READY FOR PHASE 2M IMPLEMENTATION
```

**HARD STOP.** No production code, state machine, index, worker, ADR, or schema was modified in this freeze.
