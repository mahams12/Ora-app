# Ora — Current State (Authoritative Snapshot)

**Status:** CURRENT  
**Evidence date:** 2026-09-21  
**Git tip at documentation:** `master` @ `4fb0a6b` (verify with `git log -1`)  
**Rule:** Code + executable proofs outrank historical markdown. If this file conflicts with older docs, **this file wins** until updated with new code evidence.

Read this first in any new Cursor/engineering session. Then follow links to phase docs, architecture maps, and diagnostics.

---

## A. Project identity

| Concern | Actual |
| ------- | ------ |
| Product | **Ora** — P2P offered-fare ride-hailing (passenger + driver in one Flutter app) |
| Backend | `backend/auth-service/` — Express modular monolith (auth + rides + drivers + location + Redis GEO) |
| Mobile | `mobile/` — Flutter (Riverpod, go_router, Firebase Auth / App Check) |
| Identity | Firebase Auth ID tokens verified by Admin SDK |
| Durable SoT | **Firestore** (`firestore.rules`, `firestore.indexes.json`, emulator port **8181**) |
| Redis | **Optional** via `REDIS_URL` — N2C GEO projection only (`ioredis`) |
| RTDB | **Not implemented** (documented target; no Admin `databaseURL`, no client SDK) |
| Outbox | Firestore `outboxEvents` writes `PENDING` — **no projector / Pub/Sub / FCM consumer yet** |

**Start here for diagnosis:**

| Need | Document |
| ---- | -------- |
| Location pipeline | [`docs/architecture/N_LOCATION_FLOW.md`](architecture/N_LOCATION_FLOW.md) |
| Request traces | [`docs/architecture/N_REQUEST_FLOWS.md`](architecture/N_REQUEST_FLOWS.md) |
| Symptom → fix | [`docs/diagnostics/BACKEND_TROUBLESHOOTING.md`](diagnostics/BACKEND_TROUBLESHOOTING.md) |
| Error codes | [`docs/diagnostics/BACKEND_ERROR_INDEX.md`](diagnostics/BACKEND_ERROR_INDEX.md) |
| Data ownership | [`docs/architecture/DATA_OWNERSHIP.md`](architecture/DATA_OWNERSHIP.md) |
| API surface | [`docs/architecture/API_CONTRACT_INDEX.md`](architecture/API_CONTRACT_INDEX.md) |
| ADRs | [`docs/architecture/DECISION_INDEX.md`](architecture/DECISION_INDEX.md) |
| Engineering rules | [`docs/ENGINEERING_RULES.md`](ENGINEERING_RULES.md) |

---

## B. Current implementation status

Status vocabulary used below:

| Status | Meaning |
| ------ | ------- |
| **IMPLEMENTED** | Routes/services exist and are wired in `createApp` |
| **PARTIAL** | Core code exists; production/Console/client gaps remain |
| **NOT IMPLEMENTED** | No registered route / no writer path |
| **PLANNED** | Docs only |
| **DEFERRED** | Intentionally postponed (named in code comments) |

Live proof column: **PASS** (claimed in phase closure docs on disk), **SCRIPT EXISTS** (not re-run in this doc session), **NOT RUN**, **N/A**, **NONE**.

| Phase | Capability | Status | Implementation | Tests | Live Proof | Next Dependency |
| ----- | ---------- | ------ | -------------- | ----- | ---------- | --------------- |
| 2A | Auth register / me | IMPLEMENTED | `src/routes/auth.ts`, `services/users.ts` | `src/__tests__/auth.test.ts` | N/A | 2C profile |
| 2B | App Check option, rate limit, guards | PARTIAL (dev `REQUIRE_APP_CHECK=false`) | `middleware/auth.ts`, `rate_limit*`, `production_guards.ts` | `security_phase2b`, `production_guards` | Console checklist docs | Prod App Check enforce |
| 2C | Onboarding / PATCH profile | IMPLEMENTED | `routes/auth.ts`, `services/profile.ts`, rules deny client user writes | `profile.test.ts` | Closure doc claims PASS | Ride slices |
| 2E | Ride create / get / cancel / assign | IMPLEMENTED | `rides/ride_service.ts`, `rides/routes.ts` | `rides.test.ts`, `test:ride-proof` | SCRIPT EXISTS (`test:ride-firestore-concurrency`) | 2F+ |
| 2F | Offers create/list/withdraw/select | IMPLEMENTED | `ride_service.ts`, `offer_lifecycle.ts` | rides + offer proofs | SCRIPT EXISTS | 2G |
| 2G | Post-assign progression | IMPLEMENTED | `markEnRoute`…`completeRide` | rides + progression proof | SCRIPT EXISTS | 2H |
| 2H | Ride close | IMPLEMENTED | `closeRide` | close proof | SCRIPT EXISTS | 2I |
| 2I | Ride history list | IMPLEMENTED | `GET /v1/rides`, `list_query.ts` | rides + list proof | SCRIPT EXISTS | 2J |
| 2J | Ride expire sweeper | IMPLEMENTED | `POST /v1/internal/rides/expire-sweep` | `run_phase_2j_unit_proof` | SCRIPT EXISTS | 2K |
| 2K | Offer expire sweeper | IMPLEMENTED | `POST /v1/internal/rides/offer-expire-sweep` | `run_phase_2k_unit_proof` | SCRIPT EXISTS | 2L |
| 2L | Durable `arrivedAt` | IMPLEMENTED | arrive path sets `arrivedAt` once | `run_phase_2l_unit_proof` | SCRIPT EXISTS | 2M |
| 2M | NO_SHOW sweeper | IMPLEMENTED | `POST /v1/internal/rides/no-show-sweep` | `run_phase_2m_unit_proof` | SCRIPT EXISTS | 2N |
| 2N | Ratings (stars) | IMPLEMENTED | `POST/GET .../ratings` | `run_phase_2n_unit_proof` | SCRIPT EXISTS | N-series |
| M0 | Open-ride discovery | IMPLEMENTED | `GET /v1/rides/open` chronological | `open_discovery.test.ts`, `run_phase_m0_unit_proof` | SCRIPT EXISTS | N3 ≠ M0 |
| N1 | Driver go-online/offline | IMPLEMENTED | `drivers/*` | `driver_availability.test.ts`, `run_phase_n1_unit_proof` | SCRIPT EXISTS (`test:driver-availability-firestore`) | N2A |
| N2A | Location accept + cursor | IMPLEMENTED | `location/*` | `run_phase_n2a_unit_proof` | SCRIPT EXISTS (`test:location-update-firestore`) | N2C |
| N2B | RTDB tripLocations projection | **DEFERRED / NOT IMPLEMENTED** | none | none | NONE | Optional before trip UX |
| N2C | Redis GEO projection | IMPLEMENTED — **coordinate-primary** `geo:drivers` (+ legacy dual-write) | `redis/*`, hooked from location + go-offline | `run_phase_n2c_unit_proof`, `geo_projection.test.ts` | SCRIPT EXISTS (`test:redis-geo-proof`) | N3 |
| N3 | Nearby drivers query | **IMPLEMENTED** — lat/lng on `geo:drivers` (city not required) | `GET /v1/internal/drivers/nearby`, `drivers/nearby_service.ts` | `nearby.test.ts`, `run_phase_n3_unit_proof` | SCRIPT EXISTS (`test:nearby-redis-proof`) | N4 |
| N4 | Dispatch / matching waves | **IMPLEMENTED** (MVP) — invite ledger 5/10/15; pickup lat/lng → N3; no auto-assign | `dispatch_wave_service.ts`, internal dispatch-sweep/tick | `dispatch.test.ts`, `run_phase_n4_unit_proof` | SCRIPT EXISTS (`test:dispatch-live-proof`) | **D1** delivery freeze |
| D1 | Dispatch invite delivery (FCM wake) | **IMPLEMENTED (YELLOW)** — minimal projector + tokens; real FCM send optional/not default-proven | `delivery/*`, `POST .../device-tokens`, `POST .../outbox/dispatch-fcm-sweep` | `delivery_d1.test.ts`, `run_phase_d1_unit_proof` | SCRIPT EXISTS (`test:dispatch-fcm-live-proof`; FCM stubbed unless `ORA_D1_REAL_FCM=1`) | D2 / N2B / product priority |
| Ph 4–5 | Location resolve + pricing estimate | **4A GREEN**; **5A+4B/5B GREEN**; **5C CODE GREEN / DEVICE PENDING** | Flutter GPS+Places+estimate UI; server Routes+estimate+snapshot | fare/routes/estimate + Flutter 5C tests; `test:phase-5b-*` | 4A DEVICE GREEN; 5B live Routes GREEN; **5C device pending** | Device proof then audit; next slice TBD after accept |
| Ph 3, 6–15 | Remaining product (payments, safety, etc.) | **PLANNED** | stubs / docs | mobile stubs | NONE | After Ph 4–5 / product priority |

Phase documentation for N1/N2A/N2C/N3/N4/D1: [`docs/implementation/n-series/`](implementation/n-series/).  
N3 closure: [`implementation/n-series/N3-nearby-planning.md`](implementation/n-series/N3-nearby-planning.md).  
N4: [`implementation/n-series/N4-dispatch-planning.md`](implementation/n-series/N4-dispatch-planning.md).  
D1 freeze (next): [`implementation/n-series/D1-dispatch-delivery-planning.md`](implementation/n-series/D1-dispatch-delivery-planning.md).
---

## CURRENT FRONTIER

```text
CURRENT FRONTIER
```

1. **Last completed backend slice (code evidence):** **Phase 4B/5B** — Google `RoutingProvider` + `POST /v1/pricing/estimate` + snapshot writer. Prior: **5A**, **4A**, **D1**, **N4**, N2C/N3, **2E–2N**, **M0**, **N1**, **N2A**.
2. **Passenger device auth baseline:** VERIFIED (OTP → onboarding → Home → relaunch).
3. **Passenger Ride Request:** **Phase 4A GREEN** + **Phase 5C CODE** — Flutter calls estimate, shows PKR, sends `pricingSnapshotId` + `city` on create. **Physical-device proof pending** (Samsung disconnected at 5C close).
4. **Next implementation slice:** Reconnect device → **5C physical proof** → audit/accept → then propose next (not auto-start 5D).
5. **4B/5B:** **IMPLEMENTED / VERIFIED** — live Google Routes proof passed; MemoryDb estimate + snapshot proofs passed.
6. **5A:** **IMPLEMENTED** — `calculateFare` + `PricingRulesRepository`.
7. **5C:** **IMPLEMENTED (code)** — `PricingRemoteDataSource`, review UI, city suggestion/picker, capabilities from live estimate.
8. **D1:** **IMPLEMENTED (YELLOW)** — FCM wake path.
9. **N4:** **IMPLEMENTED**.
10. **City / coverage:** `rides.city` + `pricingRules/{city}_{category}` metadata (not matching gate); Flutter sends suggested/selected city slug.
11. **Still deferred:** **N2B**; RTDB cards; invite-poll; Redis demandMult; surge/tolls; Phase 5D+.
12. **Must NOT be touched without a new freeze:** ride/offer SM; fabricating pricing snapshots; N3/N4 matching redesign; N2A/N2C write semantics.

### Nearby meaning (frozen product intent in architecture docs)

> **Nearby** = drivers near **passenger pickup** (Redis GEO candidate generation).  
> **Not** = open rides near the driver.  
> Open rides are **M0** chronological Firestore discovery (`GET /v1/rides/open`).

### Location stack (actual)

```text
Firestore = durable business SoT (rides, availability, locationStreams cursor)
Redis GEO = ephemeral nearby-driver projection (N2C write; N3 GEORADIUS read)
RTDB     = planned ephemeral trip projection (N2B) — NOT IMPLEMENTED
```

---

## Registered HTTP surface (summary)

See full index: [`API_CONTRACT_INDEX.md`](architecture/API_CONTRACT_INDEX.md).

- Auth: `POST /v1/auth/register`, `GET /v1/auth/me`, `PATCH /v1/auth/profile`
- Rides + offers + ratings + internal sweeps
- Drivers: `POST /v1/drivers/go-online`, `POST /v1/drivers/go-offline`
- Location: `POST /v1/location/update`
- Internal nearby: `GET /v1/internal/drivers/nearby` (worker token; N3)
- Health: `GET /healthz`
- **Not registered (by design for N3 MVP):** `GET /v1/drivers/nearby` (JWT/passenger)

---

## Proof commands (backend)

From `backend/auth-service` (after local `npm ci` — do not run as part of doc-only tasks unless asked):

| Slice | Unit / memory | Live |
| ----- | ------------- | ---- |
| N1 | `npm run test:phase-n1-unit-proof` | root `npm run test:driver-availability-firestore` |
| N2A | `npm run test:phase-n2a-unit-proof` | root `npm run test:location-update-firestore` |
| N2C | `npm run test:phase-n2c-unit-proof` | `REDIS_URL=... npm run test:redis-geo-proof` |
| N3 | `npm run test:phase-n3-unit-proof` / `nearby.test.ts` | `REDIS_URL=... npm run test:nearby-redis-proof` |
| 5A | `npm run test:phase-5a-unit-proof` / `fare_calculator.test.ts` + `pricing_rules_repository.test.ts` | N/A (seed is Admin/ops) |
| 4B/5B | `npm run test:phase-5b-unit-proof` / `google_routes_provider` + `pricing_estimate` tests | `GOOGLE_MAPS_SERVER_KEY=… npm run test:phase-5b-live-proof` |
| Rides | `npm test`, `npm run test:ride-proof` | root `npm run test:ride-*-firestore-*` |

CI (`.github/workflows/ci.yml`): Flutter + `auth-service` vitest + `test:ride-proof` + Firestore rules. **Does not** run N1/N2A/N2C/N3 unit proofs or Redis live proofs (vitest may include `nearby.test.ts` if present in suite).

---

## Stale documentation warning

These are **historical** and must not be used as live status:

- [`docs/audits/ORA_COMPLETE_ARCHITECTURE_AUDIT.md`](audits/ORA_COMPLETE_ARCHITECTURE_AUDIT.md) — claims Redis/rides absent (pre–Phase 2E / N-series)
- Auth-service README was auth-era only (updated to point here)
- Phase 2J/2K **investigation** docs that say go-online/Redis “missing” — superseded by N1/N2C code
- Much of [`docs/ORA_MASTER_PLAN.md`](ORA_MASTER_PLAN.md) remains aspirational — use the COMPLETED / FRONTIER sections added there

---

## Flutter / client gaps (evidence)

- Phase **4A** adds `geolocator` + Places HTTP (requires `ORA_GOOGLE_PLACES_API_KEY`)
- Phase **5C** adds `POST /v1/pricing/estimate` client + review fare UI + `city` on create (device proof pending)
- No Maps SDK / map-pin (deferred); no Routes client (Routes remain server-only)
- Driver UI uses **open rides** (M0), not GEO nearby
- No `firebase_database` / N2B in pubspec

---

## How to update this file

When a phase closes:

1. Verify routes + tests + proof scripts on disk.
2. Update the status table and CURRENT FRONTIER.
3. Add/update `docs/implementation/...` phase closure.
4. Do **not** rewrite historical audits; mark them HISTORICAL and link here.
