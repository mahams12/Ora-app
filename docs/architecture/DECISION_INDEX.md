# Architecture Decision Index

**Status:** CURRENT  
**ADR folder:** `docs/architecture-final/ADRs/`  
**Live snapshot:** [`ORA_CURRENT_STATE.md`](../ORA_CURRENT_STATE.md)

Classification:

| Class | Meaning |
| ----- | ------- |
| ACTIVE | Decision still governs design |
| PARTIALLY IMPLEMENTED | Accepted; only some consequences exist in code |
| PLANNING ONLY | Accepted target; little/no code |
| HISTORICAL | Context / superseded process |
| SUPERSEDED | Replaced by later decision or CURRENT_STATE |

---

## ADR catalog

| ADR | Title | Classification | Code reality |
| --- | ----- | -------------- | ------------ |
| ADR-001 | MVVM | ACTIVE (mobile) | Flutter feature VMs present |
| ADR-002 | Clean Architecture | ACTIVE (mobile intent) | Layered features; incomplete domains |
| ADR-003 | Firestore Assignment Authority | ACTIVE + PARTIALLY IMPLEMENTED | `selectOffer` Firestore txn exists; Redis never assigns |
| ADR-004 | Redis GEO Optimization | ACTIVE + IMPLEMENTED (N2C write + N3 GEORADIUS read) | N2C GEOADD/ZREM; N3 `GEORADIUS`; N4 IMPLEMENTED; D1 delivery FROZEN — `n-series/D1-dispatch-delivery-planning.md` |
| ADR-005 | Durable Outbox | ACTIVE + PARTIALLY IMPLEMENTED | PENDING writes; **D1** minimal `fcm_dispatch_invite` projector IMPLEMENTED (YELLOW — real FCM optional) |
| ADR-006 | Durable Idempotency | ACTIVE + IMPLEMENTED (ride/auth paths) | `idempotencyRecords` |
| ADR-007 | P2P Offer Fare Model | ACTIVE + IMPLEMENTED | offers + agreed fare from select |
| ADR-008 | Server-Authoritative State Machine | ACTIVE + IMPLEMENTED | `state_machine.ts` + ride_service |
| ADR-009 | Realtime Event Versioning | PLANNING ONLY | outbox schemaVersion field; no RTDB signals consumer |
| ADR-010 | Immutable Payment Ledger | PLANNING ONLY | no payment writers |
| ADR-011 | Location Architecture | ACTIVE + PARTIALLY IMPLEMENTED | N2A validation+cursor; **RTDB tripLocations not implemented** |
| ADR-012 | API Versioning | ACTIVE (prefix `/v1`) | `/v1` used |
| ADR-013 | Offline Reconnect Strategy | PLANNING ONLY | client reconnect incomplete |
| ADR-014 | Security Model | ACTIVE + PARTIAL | App Check optional; rules fail-closed; prod enforcement unproven |
| ADR-015 | Observability Model | PARTIAL | `logSafe` events; full SLO/metrics not wired |
| ADR-016 | Firebase Native OTP | ACTIVE + IMPLEMENTED | Flutter phone auth path |

---

## Conflicting documents — which artifact wins

| Conflict | Authoritative today |
| -------- | ------------------- |
| Audit says Redis/rides absent | **Code +** [`ORA_CURRENT_STATE.md`](../ORA_CURRENT_STATE.md); audit is HISTORICAL |
| Master plan Phase 0 “do not implement” header vs shipped Phase 2/N | **CURRENT_STATE** + code; master plan roadmap sections updated |
| ADR-011 RTDB tripLocations vs code | ADR remains **target**; code has N2A/N2C only; N2B deferred |
| `GET /v1/drivers/nearby` vs internal nearby | **N3 IMPLEMENTED:** `GET /v1/internal/drivers/nearby` — [`N3-nearby-planning.md`](../implementation/n-series/N3-nearby-planning.md) |
| Nearby vs open rides | Nearby = GEO drivers near pickup (**N3**); open rides = M0 Firestore list |
| Dual auth on nearby (internal + passenger) in architecture-final | **Rejected for N3 MVP**; internal worker only |
| Matching/dispatch vs assignment | **N4 IMPLEMENTED:** wave invite ledger ≠ assign; **D1 FROZEN:** FCM wake only — [`D1-dispatch-delivery-planning.md`](../implementation/n-series/D1-dispatch-delivery-planning.md) |
| N4 D-CITY / D-CANDIDATE-SOURCE | **FROZEN (resync):** matching = pickup lat/lng → N3 `geo:drivers`; `rides.city` = metadata only — [`N4-dispatch-planning.md`](../implementation/n-series/N4-dispatch-planning.md), [`CITY-PARTITION-STRATEGY-DECISION.md`](../implementation/n-series/CITY-PARTITION-STRATEGY-DECISION.md) |
| Flutter city selector | **SUPERSEDED membership model** — Pakistan-wide server catalog — [`PAKISTAN-CITY-ARCHITECTURE.md`](../implementation/n-series/PAKISTAN-CITY-ARCHITECTURE.md) |
| Small Flutter launch-city const as SoT | **SUPERSEDED** by Pakistan-wide architecture |
| N4 D-DELIVERY | **SUPERSEDED for next-slice ordering by D1:** N4 remains durable-decision-only; **D1** owns FCM wake via minimal outbox projector — [`D1-dispatch-delivery-planning.md`](../implementation/n-series/D1-dispatch-delivery-planning.md) |
| D1 delivery channel | **FROZEN:** FCM data wake + M0 recovery; RTDB cards deferred; invite-poll API deferred; N2B independent deferred |
| D1 vs H3 (ledger gate) | **FROZEN:** ledger = notification intent only; `createOffer` not ledger-gated in D1 |
| Phase 4 Maps + Phase 5 Pricing | **FROZEN (2026-09-22):** Google Maps Platform; server snapshots — [`phase-4-5-location-pricing-decision.md`](../implementation/phase-4-5-location-pricing-decision.md). **4A/5A/4B/5B GREEN**; **5C CODE** (device proof pending) |
| Live pricing vs fixture snapshots | Fixtures = tests only; passenger path must use server estimate (no fabricated `pricingSnapshotId`) |
| N4 D-WAIT / D-RADIUS / D-RANK | **5s** / **fixed 10 km** / **distanceKm ASC** |
| Matching-engine requires RTDB presence for online | **STALE vs N-series** — use Redis marker + Firestore availability |
| Matching-engine `drivers.driverStatus` | **Code uses `users.driverStatus`** via `eligibility.ts` |
| Matching docs say `GEORADIUS` | **FROZEN for N3**; N4 reuses `NearbyDriversService` |
| `docs/database/redis-schema.md` many keys | Only `geo:drivers:*` + `driver:online:*` implemented; rest PLANNING |
| Phase 2J/2K investigation “go-online needs Redis+RTDB” | **Superseded by N1/N2C code** — investigations are HISTORICAL design notes |
| auth-service README auth-only | Point to CURRENT_STATE / this index |

---

## Document classes (quick)

| Path pattern | Typical class |
| ------------ | ------------- |
| `docs/ORA_CURRENT_STATE.md` | CURRENT |
| `docs/implementation/phase-02*-*.md` closures | CURRENT/HISTORICAL closure evidence |
| `docs/implementation/phase-02*-architecture-investigation.md` | HISTORICAL (pre-impl notes; may be stale) |
| `docs/implementation/phase-4-5-location-pricing-decision.md` | CURRENT freeze (Ph 4–5) |
| `docs/implementation/phase-03`…`15` | PLANNING (Ph 4–5 narrowed by freeze above) |
| `docs/audits/ORA_COMPLETE_ARCHITECTURE_AUDIT.md` | HISTORICAL / SUPERSEDED as live status |
| `docs/architecture-review/phase-0*` | HISTORICAL approvals |
| `docs/architecture-final/*` | ACTIVE targets; verify vs code |

Do not delete ADRs. Update this index when implementation catches up.
