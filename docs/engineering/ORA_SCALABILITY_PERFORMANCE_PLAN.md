# Ora Scalability & Performance Plan

Date: 2026-11-24. Measurements marked [RT] are from emulator/staging
runs documented in prior audits — not production telemetry.

---

## 1. Performance budget (current)

| Path | Budget | Current [RT] | Headroom |
|---|---|---|---|
| `/v1/location/update` idle | p95 < 500 ms | ~10 ms emulator; remote Firestore adds ~100–300 ms | OK |
| `findNearby` empty | p95 < 500 ms | ~280 ms staging | OK |
| `findNearby` candidates | p95 < 500 ms target | ~1.1 s staging → hardened (local) est. ~500–700 ms | **verify on staging** |
| Dispatch wave | inside 60 s sweep tick | ~3 s typical, 13.4 s peak | OK |
| Trip location E2E lag | < 8 s | driver 4 s publish + RTDB push ≈ ~5–6 s | OK |
| Invite delivery | booking → driver awareness | FCM ~1–3 s typical; **unbounded if FCM dropped** (GAP-001) | gap |
| App cold start | < 3 s to interactive | Firebase init + App Check + bootstrap ~1–2 s [ASM] | verify on low-end |

## 2. Hot-path analysis

### Presence write path (hottest: ~1,440–2,160 ops/driver-day)

```
POST /v1/location/update
 → auth.verifyIdToken (revocation check = network call to Firebase)
 → rate limit (in-memory)
 → loadApprovedOnlineDriver: eligibilityCache(15s) → users+drivers get
 → [trip only] assertTripPublishAuthorization: rides/{id} get  ← GAP-011
 → streamStore.accept: Firestore tx (locationStreams or merged geoDrivers)
 → [trip only] RTDB projectAcceptedTripLocationLatest (best-effort)
 → geoProjection.projectAcceptedLocation: geoDrivers tx/set (1R+1W merged)
 → 2× logSafe lines (GAP-006/C-3)
```

Serialization note: `verifyIdToken(token, true)` checks revocation —
cached by Admin SDK briefly; fine.

### Matching path (per dispatch wave)

```
findNearby: georadius bbox (1–33 queries) → marker piggyback →
  parallel [busy-ride chunks + users/drivers getAll chunks] →
  per-candidate eligibility (prefetched) → nearest-first
revalidation: lazy chunked loadInviteRevalidationContext(25) →
  isStillEligibleForInvite per candidate → tx: wave doc + ride update + outbox
```

Reads per wave @1k fleet ≈ geo ~54 + busy ~2–6 + getAll ~4 RPCs
(~104 docs) + revalidation ~1–4 batched sets ≈ **~200–400 reads/wave**.

### Polling paths (client-driven)

| Poller | Cadence | Cap | Reads/session |
|---|---|---|---|
| Offers inbox (passenger) | 2→3→5 s | 6 min | ≤~80 × (1+offers page) |
| Active ride (passenger) | 3→5→8 s | 4 h | ≤~3,000 worst; ~500–1,000 typical |
| Driver assigned ride | similar backoff | bounded | similar |
| Driver invites/open rides | **none periodic** | — | mount + FCM only (GAP-001) |
| RTDB trip listener | per driver packet ~4 s | ride-state gated | ~200 B/event |

## 3. Identified performance gaps

| ID | Gap | Evidence | Sev | Fix sketch |
|---|---|---|---|---|
| P-1 | N3 candidate-bearing ~1.1 s staging | prior audit measured; hardening implemented locally, **not re-measured on staging** | P2 | deploy + re-measure `N3_NEARBY` |
| P-2 | Trip-authz ride read per 4 s packet | `location_update_service.ts:347` | P2 | 10–15 s authz cache (DR-006) |
| P-3 | Per-packet double logging | `location/routes.ts:43`, `geo_projection.ts:252` | P2 | sample logs (e.g. 1-in-N or duration-threshold) |
| P-4 | Estimate→Routes call per estimate + snapshot write per estimate | `estimate_service.ts:216-338` | P2 | route-result cache (deferred trigger), snapshot only on create-adjacent or TTL'd reuse |
| P-5 | `listOpenRides` ≤200-doc scan per refresh | `ride_service.ts:1746-1759`, cap=200 | P3 | acceptable; add city/serviceType index path if refresh rate grows |
| P-6 | `sweepNoShowRides` multi-pass re-query (≤20 passes) | `ride_service.ts:5359+` | P3 | bounded; fine |
| P-7 | Cold start minScale 0 | deploy config | P3 | monitor; minScale 1 if needed |
| P-8 | Mobile: invites section renders ≤8 cards (ANR fix present) | `driver_invites_section.dart:128` | solved | — |
| P-9 | Mobile: `_serverOffsetMs` skew clamp ±10 min | `driver_invites_view_model.dart:114-118` | good | — |
| P-10 | Firestore `getAll` chunk = 100 docs/RPC; N3 uses it correctly | `nearby_service.ts` | good | — |

## 4. Mobile performance notes [VC]

- Bounded polling everywhere it exists; no Firestore listeners (by
  design — cheaper).
- Presence publisher: single GPS watch shared with map display via
  `driverPresenceLatestFixProvider`; trip publisher suppresses idle.
- Invite cards capped at 8 rendered (documented ANR fix on SM-A325F).
- Estimate calls debounced (pickup/destination ~350 ms + 600 ms draft
  write); place search ≥3 chars.
- Retry policy cannot retry non-idempotent mutations — no duplicate
  ride creates from network flaps.
- RTDB listener soft-closes on permission errors (post-cleanup
  `permission_denied` is expected and handled).
- Image pipeline: avatar resize 512 px JPEG q82 on-device before
  upload — but see GAP-003 (body limit makes most uploads fail).

## 5. Scalability roadmap (trigger-based, already defined)

| Trigger | Action | Cost of acting early |
|---|---|---|
| >2k drivers/city AND >$50/mo geo reads | geohash-p5 dual-write index | migration + fan-out latency — not worth it now |
| >$30/mo geo writes | re-evaluate Redis GEOSEARCH | $59+/mo floor — still likely loses |
| >~50–100 concurrent tracked trips | RTDB Blaze or poll-based tracking | conn cap / billing |
| Routes >$20/mo | geohash route cache ~6 h TTL | ~80 lines, deferred correctly |
| findNearby p95 >500 ms sustained | parallelize remaining serial reads; consider read replicas | premature now |
| Cloud Run p95 >300 ms or >5 instances sustained | raise maxScale / concurrency tuning | deploy decision |

## 6. Verification still owed (from prior audit, still open)

- Moving 10 s cadence on real physical travel (boost path proven;
  mechanism identical).
- FCM delivery proof independent of poll fallback.
- Sweep 503 fault-injection on staging (unit-verified only).
- N3 hardened latency re-measurement on staging.
- Production billing reconciliation once real traffic exists.
