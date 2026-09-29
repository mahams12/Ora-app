# N2C + N3 Coordinate-Primary — Production Hardening Audit

**Status:** AUDIT COMPLETE — **READ-ONLY** (no code/Redis/Firestore changes)  
**Date:** 2026-09-21  
**Scope:** Correctness, migration, rollback, scale, and N4 readiness of the coordinate-primary cutover.  
**Authority:** Code under `backend/auth-service/src` + N2C/N3 docs + [`CITY-PARTITION-STRATEGY-DECISION.md`](CITY-PARTITION-STRATEGY-DECISION.md) + [`N4-dispatch-planning.md`](N4-dispatch-planning.md).

```text
Tests prove tested behavior. This audit identifies production / migration / N4 risks.
```

---

## 1. Executive Verdict

```text
YELLOW
```

Coordinate-primary matching is **correctly implemented** for the intended product rule (physical proximity + existing eligibility gates). It is **not** production-risk-free:

| Risk | Severity for starting N4 |
| ---- | ------------------------ |
| COUNT-100 post-filter starvation | Known limitation (pre-existed); denser under national key |
| Legacy city-key staleness | Migration debt; **does not** affect current N3 reads |
| Rollback not behaviorally equivalent | Emergency/compatibility only |
| Sequential Firestore eligibility N+1 | Needs profiling before high concurrency |
| N4 freeze text still assumes city matching | **Docs must be resynced before N4 code** |

No RED correctness bug found that makes nearby assignment wrong relative to Firestore SoT. Redis remains non-authoritative.

---

## 2. Audit 1 — Candidate Starvation

### Mechanism (code)

```text
GEORADIUS geo:drivers … COUNT 100 ASC
  → for each hit (nearest first):
       Redis GET marker → freshness / accuracy filters
       sequential Firestore eligibility
       stop when surviving.length >= limit
```

Evidence: `nearby_service.ts` `findNearby` + `N3_REDIS_GEO_COUNT = 100`.

### Answers

1. **Can N3 return fewer candidates than requested even though more eligible drivers exist farther away?**  
   **Yes.** If the nearest 100 Redis members are mostly rejected (stale marker, bad accuracy, offline, unapproved, busy), eligible drivers ranked 101+ within radius are **never inspected**.

2. **Already present in the old city-sharded implementation?**  
   **Yes.** Same COUNT-100 + filter pattern (N3 D3 / matching-engine). City shards often had smaller sets, so the wall was hit less often.

3. **Does coordinate-primary make it materially more important?**  
   **Yes, in dense metros / national online pools.** One `geo:drivers` set can contain many more members near a pickup than a single city shard, increasing the chance the nearest-100 window is polluted by ineligible members.

4. **Would N4 wave dispatch be affected?**  
   **Yes, under high rejection density.** Waves need up to 5/10/15 new invites (cap 30). If one `findNearby(limit≈30)` call under-fills because of the COUNT-100 wall, later waves calling the same API face the same ceiling unless N4 adds refill/over-fetch logic.

5. **Would a bounded refill/over-fetch strategy be needed?**  
   **Recommended before dense production**, not required to *start* N4 MVP if early supply density stays modest. Safer future designs (docs only here):
   - raise Redis COUNT with a hard cap; and/or
   - iterative GEORADIUS with expanding COUNT / exclude-seen; and/or
   - soft radius expansion (N4 previously froze fixed 10 km — would need a new decision).

6. **Safest future design**  
   Keep distance ASC; keep eligibility gates; add **bounded refill** so N4 can obtain up to 30 *eligible* invites without scanning unbounded Redis members. Do not remove COUNT bounds.

### Verdict

```text
ACCEPTABLE KNOWN LIMITATION
```

**Not a PRE-N4 BLOCKER** to begin N4 MVP, provided N4/docs acknowledge under-supply is possible and dense-market refill is a follow-up. **Would become a production reliability issue** if Lahore/Karachi online pools routinely exceed ~100 nearby members with high reject rates.

---

## 3. Audit 2 — Legacy City GEO Staleness

### Write / remove paths traced

| Event | Primary `geo:drivers` | Legacy `geo:drivers:{city}` |
| ----- | --------------------- | --------------------------- |
| Accepted location + homeCity | GEOADD | GEOADD that city |
| Accepted location + no homeCity | GEOADD | no write; ZREM previous marker city if any |
| homeCity A→B on **next** projection | GEOADD (same key) | ZREM A (if `prev.city`), GEOADD B |
| Go-offline | ZREM | ZREM homeCity ∪ marker.city |
| homeCity changed in Firestore **without** location update | unchanged | **stale until** next projection or offline |
| No homeCity writer API | N/A | Admin/Console edits not hooked to Redis |

Evidence: `geo_projection.ts` (lines ~73–100, ~168–171); `location_update_service.ts` only passes `homeCity` at projection time; no other `homeCity` writers in `src/`.

### Answers

1. **Can stale legacy membership exist?**  
   **Yes** — e.g. Firestore `homeCity` edited while driver stays online without a subsequent accepted location / offline; Redis failure swallowed on ZREM; crash between FS offline and Redis cleanup.

2. **Affect CURRENT matching?**  
   **No.** N3 reads only `GEO_DRIVERS_KEY` (`geo:drivers`).

3. **Affect rollback?**  
   **Yes.** City-key reads may show ghosts in wrong cities and miss drivers never dual-written.

4. **Accumulate indefinitely?**  
   **Possible** on unused city keys for drivers who never project again / never offline. Bounded by active driver churn in practice, but **no sweeper** exists in code.

5. **Safe cleanup strategy (future)**  
   - Offline already cleans known cities.  
   - Future: periodic ZREM of members missing `driver:online:*` / not online in Firestore; or drop dual-write entirely after rollback window closes. **Do not flush Redis blindly.**

### Verdict

```text
ACCEPTABLE MIGRATION DEBT
```

Not a PRE-N4 BLOCKER for current matching.

---

## 4. Audit 3 — Rollback Correctness

Conceptual drivers under **coordinate-primary** vs **emergency city-key N3**:

| Driver | homeCity | Live coords | CP N3 | City rollback N3 (`city=lahore`) |
| ------ | -------- | ----------- | ----- | -------------------------------- |
| A | Lahore | Lahore | Visible | Visible (if dual-written) |
| B | null | Lahore | Visible | **Invisible** (never dual-written) |
| C | Lahore | Islamabad | Visible near ISB pickup; not near LHE if far | Still in Lahore key with **Islamabad coords** → may appear for Lahore query if GEO distance from Lahore pickup happens to include them, or confuse ops |

### Answers

1. **Behaviorally equivalent?** **No.**
2. **Who disappears?** Drivers without homeCity (B); also anyone whose legacy ZREM raced / failed; supply shape differs for cross-city live positions (C).
3. **Real supply reduction?** **Yes** — especially after coordinate-primary adoption when many drivers lack homeCity.
4. **Safe as emergency?** **Yes, with eyes open** — restores *some* city-sharded path if dual-write still warm; not a lossless revert.
5. **Wording** — Rollback should be described as:

```text
COMPATIBILITY / EMERGENCY ROLLBACK
(not behaviorally equivalent rollback)
```

### Verdict

```text
ACCEPTABLE IF DOCUMENTED AS NON-EQUIVALENT
```

Update ops language; not a PRE-N4 BLOCKER for forward path.

---

## 5. Audit 4 — N3 Firestore Read Amplification

### Per `findNearby` call (code)

| Step | Ops | Parallelism |
| ---- | --- | ----------- |
| 1 GEORADIUS | 1 Redis | — |
| Per hit (≤100) until `limit` filled | 1 Redis GET marker | **Sequential** `for` loop |
| Per hit passing marker gates | 1 users get + 1 drivers get + 1 rides query (`assignedDriverId` + `state in` busy, `limit 1`) | **Sequential** |

No batching / `getAll` / `Promise.all` in `isAuthoritativelyEligible`.

**Worst-case FS reads per nearby call:** if all 100 hits have fresh markers and most fail only at Firestore filters → up to **~300 Firestore reads** (100×3) plus 100 Redis GETs.  
**Best-case:** empty GEO / early marker drops → ~0 FS reads.

Existing bound: Redis COUNT **100** caps the loop. No unbounded collection scan.

### Estimated pressure (estimates only)

Assume avg **40 FS reads** per nearby (mixed early rejects) and **1 nearby call per dispatchable ride per wave tick**:

| Concurrent dispatchable rides (order of magnitude) | Est. FS reads / tick (wave 1) |
| -------------------------------------------------- | ----------------------------- |
| 10 | ~400 |
| 100 | ~4,000 |
| 1,000 | ~40,000 |
| 10,000 | ~400,000 |

Multiple waves / retries multiply. Label: **engineering estimate**, not measured.

### Verdict

```text
NEEDS PROFILING
```

**Not a PRE-N4 BLOCKER** for low-QPS N4 MVP. **Is a scale risk** before national peak concurrency. Future: batch gets, parallelize with concurrency limit, or cache online/approved bits — **do not implement here**.

---

## 6. Audit 5 — Redis Scale

Single key `geo:drivers` + radius-bounded GEORADIUS + COUNT 100.

| Online drivers (order of magnitude) | Assessment |
| ----------------------------------- | ---------- |
| 100 – 10,000 | **Acceptable** for immediate Ora rollout |
| ~100,000 concurrent national | Still typically workable with COUNT-bound queries; monitor latency/memory |
| ~1,000,000 | Reconsider **coordinate-derived cell** partitioning (not city labels) — future decision |

Repository does not encode Redis hard limits; thresholds above are **labeled engineering judgment**, not measured SLOs.

### Verdict

```text
SAFE FOR IMMEDIATE ROLLOUT
```

Cell sharding is a later scale tactic inside coordinate-primary — not required for N4 start.

---

## 7. Audit 6 — Location Update Safety

### Path

```text
POST /v1/location/update
  → approved + online gate (location_update_service)
  → parseAndValidateLocationBody (finite coords, accuracy ≤50, speed ≤200, stale/future window)
  → Firestore locationStreams cursor txn (N2A SoT)
  → projectAcceptedLocation (best-effort Redis)
       → monotonic seq/ts guard vs existing marker
       → GEOADD geo:drivers
       → optional legacy dual-write
       → SET driver:online EX 30
```

Rejected N2A updates **never** call projection.

### Residual risks (not introduced as regressions)

| Risk | Mitigation today |
| ---- | ---------------- |
| Offline driver left in GEO if Redis ZREM fails | N3 drops missing/stale markers; zombie GEO member until next successful cleanup |
| Marker TTL 30s vs GEO no TTL | Intentional; N3 freshness ≤15s |
| Accuracy in GEO vs N3 | N2A rejects >50m; N3 also checks marker accuracy |

### Verdict

```text
GREEN (with known best-effort Redis cleanup caveats)
```

---

## 8. Audit 7 — Duplicate / Idempotency

- Redis GEO: **one member id per key**; repeated `GEOADD` **updates coordinates** (standard GEO semantics; memory fake matches).
- Older `locationSeq` / same seq older `lastLocationTs` → **skip** projection (`stale_projection`).
- Newer seq → overwrite primary (+ legacy dual-write).
- Offline remove is idempotent (repeated ZREM/DEL safe).

### Verdict

```text
GREEN
```

---

## 9. Audit 8 — Security

| Check | Status |
| ----- | ------ |
| N2A requires approved + online driver | Yes |
| N3 internal worker token only | Yes (`/v1/internal/drivers/nearby`); JWT public nearby **404** |
| Clients cannot mutate GEO | No client Redis API |
| Redis cannot assign rides | ADR-004 / no assignment writes in N2C/N3 |
| Firestore assignment SoT | Unchanged (`selectOffer`) |
| City not authorization | Confirmed — ignored for matching |
| Live coords not on unauthorized public API | N3 internal-only |

### Verdict

```text
GREEN
```

---

## 10. Audit 9 — inDrive-style Product Correctness

Coordinate-primary **only** changes candidate **discovery index**. Unchanged:

```text
Passenger request → nearby/suitable drivers → driver offers
→ passenger chooses → transactional assignment → progression → rating
```

Not introduced: auto-assignment, auto-fare, Uber-style assign, city-based matching.

### Verdict

```text
GREEN
```

---

## 11. Audit 10 — Future N4 Readiness

### Fit vs frozen N4 waves

| N4 need | N3 today |
| ------- | -------- |
| Waves 5 / 10 / 15; cap 30 | Can request `limit`; subject to COUNT-100 starvation |
| Distance ordering | Yes (ASC) |
| Repeated waves | Possible; same candidates may reappear unless N4 tracks invites |
| Stale / busy exclusion | Yes (marker + Firestore) |
| Duplicate invite prevention | **N4 responsibility** (not in N3) |
| Radius 10 km | Supported |

### Critical doc mismatch

[`N4-dispatch-planning.md`](N4-dispatch-planning.md) still states:

- depends on / invites with **city match**
- **D-CITY** client city → `rides.city` as matching input
- Flutter city + ops homeCity as blockers

**Code reality after cutover:** N3 does **not** city-match; homeCity not required for GEO.

Implementing N4 against the **stale freeze** would be incorrect.

### Verdict

```text
YELLOW — candidate source usable AFTER N4 freeze resync
```

**PRE-N4 DOCS BLOCKER (B1):** **RESOLVED** 2026-09-21 — see updated [`N4-dispatch-planning.md`](N4-dispatch-planning.md) (coordinate-primary resync).

**Not a code PRE-N4 BLOCKER** in N2C/N3 themselves for an MVP that accepts COUNT-100 under-fill and profiles FS reads.

---

## 12. Exact Blockers

| ID | Item | Type |
| -- | ---- | ---- |
| B1 | N4 planning still requires city / homeCity for matching | **RESOLVED** (2026-09-21 N4 freeze resync) |
| B2 | COUNT-100 post-filter starvation | Known limitation — **not** hard blocker for N4 MVP; **must** be acknowledged |
| B3 | Sequential FS eligibility amplification | Profile before high concurrency — **not** hard blocker for low-QPS MVP |
| B4 | Legacy city-key drift | Migration debt — **not** current matching blocker |
| B5 | Rollback non-equivalence | Ops wording — **not** forward-path blocker |

No RED implementation defect found that invalidates coordinate-primary for current N3.

---

## 13. Recommended Fixes (DO NOT IMPLEMENT IN THIS SLICE)

1. **Docs:** Resync `N4-dispatch-planning.md` / indexes to pickup lat/lng + no city match.  
2. **Ops:** Rename rollback to “compatibility/emergency,” document Driver B/C loss modes.  
3. **Later N3 hardening:** Bounded refill / higher COUNT with cap for dense reject rates.  
4. **Later scale:** Batch/parallelize eligibility reads; measure under synthetic load.  
5. **Later cleanup:** Dual-write sunset + zombie legacy ZREM sweeper after rollback window.  
6. **Do not** reintroduce city as matching boundary.

---

## 14. Exact Next Slice

```text
N4 FREEZE RESYNC (COORDINATE-PRIMARY) — docs only
```

Update N4 architecture freeze so dispatch candidates come from N3 via **pickup lat/lng only**, remove city-match eligibility, clarify `rides.city` / Flutter / homeCity are **not** matching prerequisites, and record COUNT-100 under-fill + FS read profiling as known N4 risks.

**Then** (separate implementation prompt): `N4 DISPATCH MVP`.

**STOP.** No fixes implemented in this audit slice.

---

## Scope Confirmation

| Area | Changed? |
| ---- | -------- |
| Production code | **NO** |
| Redis | **NO** |
| Firestore | **NO** |
| N3 | **NO** |
| N4 | **NO** |
| API / Flutter / PBS / Maps | **NO** |
| Only artifact | This audit document |
