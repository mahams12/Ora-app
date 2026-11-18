# ORA Backend Handoff

**Date:** 2026-11-18 · **Audience:** developers starting the next backend-module phase
**Projects:** `oraapp-a9be5` (new, billing ACTIVE — dev target) · `ora-app-d8112` (old, billing CLOSED — do not deploy; suspended legacy resources remain, see `audits/ORA_GCP_RESOURCE_DELETION_PROOF.md`)

---

## 1. Architecture (current, not planned)

```
Flutter app (mobile/) ──HTTPS──> Cloud Run `ora-auth-service` (Express modular monolith)
                                       │
                                       ├── Firebase Auth (Admin SDK verifies ID tokens)
                                       ├── Firestore — durable SoT (rides, offers, users,
                                       │   geoDrivers, wallet, marketplace, outboxEvents,
                                       │   pricing, idempotencyRecords, driverInvites…)
                                       ├── RTDB — live projections (tripLocations, locationStreams)
                                       ├── Cloud Tasks — dispatch deadline wakeups
                                       ├── Cloud Scheduler → /v1/internal/* sweeps
                                       └── FCM — outbox projectors → device tokens
```

- **Geo matching is Firestore-native** — progressive-ring bounding-box + haversine on `geoDrivers`. **No Redis/ioredis/REDIS_URL anywhere**; `src/geo/` (was `src/redis/`) exposes `GeoStoreClient` with Firestore + memory + RTDB-optional implementations. `GEO_BACKEND=firestore` in production parity.
- No VPC connector, no Memorystore, no H3, no paid caches.
- Cloud Run deploys scale-to-zero (`min=0`), no VPC.
- Source dirs: `src/{auth,drivers,rides,geo,location,rtdb,wallet,marketplace,pricing,delivery,tasks,cities,routing,maintenance,middleware,config}` + `routes/` (http wiring) + `__tests__/`.

## 2. Implemented backend modules — status

**FULLY IMPLEMENTED AND VERIFIED** (unit + live emulator E2E):

| Module | Evidence |
|---|---|
| Auth + registration + mode-switch (passenger↔driver) | E2E |
| Driver onboarding + **admin approval** `POST /v1/internal/drivers/:uid/status` (approve/reject/suspend/pending; suspend forces offline) | 8/8 live |
| Presence/location: adaptive heartbeat, merged cursor, trip-mode throttle, stale expiry | 18/18 live |
| Progressive-radius geo matching (nearest-first, `[10,15,25]`km wave radii) | unit + E2E |
| Dispatch waves + 20s invite TTL + accept/decline + expiry + idempotency | E2E 52/52 |
| Offers → passenger select → assign (accept ≠ assign) | E2E |
| Full ride lifecycle incl. courier OTP pickup/delivery | E2E |
| Ratings | E2E |
| Shared wallet: atomic 10% commission, append-only ledger, topups, negative-balance work gate, **commission↔fee-policy mutual exclusion** (`SUPERSEDED_BY_COMMISSION`) | unit + E2E |
| Marketplace: listings + bookings lifecycle, vendor approval gate, services/rental/logistics-cargo | 45/45 + 42/42 + 10/10 |
| Pricing estimates (haversine routing fallback, `pricingSnapshotId` required at create) | E2E |
| FCM outbox projectors, device tokens, invite FCM wakeups | unit + staging-verified earlier |
| Sweeps (dispatch, expire, no-show, offer-expire, ride-state-FCM, dispatch-FCM, storage cleanup) via `/v1/internal/*` | wired, jobs not provisioned |
| Security: Firestore rules 43/43, RTDB rules 11/11, App Check gate, rate limiting, idempotency | rules tests + E2E |

**PARTIALLY IMPLEMENTED:** admin ops (endpoint exists, **no admin UI**); marketplace photos (data-URL today, Storage migration analyzed not built); observability (structured `logSafe` logs, no dashboards/alerts); Auth data-migration tooling (UID-preserving export/import not built).

**NOT STARTED:** production data migration execution; admin dashboard backend; production Scheduler wiring; >10k-driver load harness; payout/disbursement (cash model by design).

## 3. Data model (Firestore + RTDB)

Key collections: `users/{uid}` (profile, role, driverStatus, wallet ref), `drivers`, `rides/{id}` (+ `offers`, `ratings`), `geoDrivers/{driverId}` (geo membership + marker + freshness twins + TTL), `driverOnline` (legacy marker), `driverInvites`, `outboxEvents` (PENDING→CLAIMED→SENT), `idempotencyRecords`, `pricingRules`/`pricingSnapshots`, `walletAccounts`/`walletLedger`, `marketplaceListings`, `marketplaceBookings`, `vendorApplications`, `deviceTokens`, `otpSessions`, `feePolicies`, `paymentIntents`, `adminAuditLogs`, `safetyEvents`, `blocks`, `reports`, `savedPlaces`, `cities`. See `database/firestore-schema.md`, `database/indexes.md` (29 composite indexes).

RTDB: `tripLocations/{rideId}/...`, `locationStreams/{driverId}` cursor, `geoPresence` — all **server-write-only** (rules-verified).

## 4. API surface (v1)

- Auth: `POST /v1/auth/register`, `GET /v1/auth/me`, `POST /v1/auth/mode`, `POST /v1/auth/profile`
- Drivers: `POST /v1/drivers/onboarding|go-online|go-offline|device-tokens`, `GET /v1/drivers/availability|nearby`
- Location: `POST /v1/location/update`
- Rides: `POST /v1/rides`, `GET /v1/rides/open|invited`, `POST /v1/rides/:id/offers|en-route|arrive|start|complete|cancel|close|ratings`, `POST /v1/rides/:rideId/invites/:waveId/accept|decline`
- Pricing: `POST /v1/pricing/estimate` (returns `pricingSnapshotId` — required by ride create)
- Marketplace: `GET|POST /v1/marketplace/listings[/:id]`, `POST /v1/marketplace/bookings[/:id]`, `POST /v1/marketplace/bookings/:id/vendor-action`
- Wallet: `/v1/wallet/...` topups, transactions (see `src/wallet/`)
- Internal (worker token `X-Ora-Worker-Token`): `/v1/internal/sweeps/all`, `/rides/{dispatch-sweep,dispatch-tick,expire-sweep,expire,no-show-sweep,offer-expire-sweep}`, `/outbox/{dispatch-fcm-sweep,ride-state-fcm-sweep}`, `/geo/presence-sweep`, `/storage/expires-at-cleanup`, `/drivers/nearby`, **`POST /v1/internal/drivers/:uid/status`**
- `GET /healthz`, `GET /v1/delivery-config`

## 5. Key env vars

`FIREBASE_PROJECT_ID` (=`oraapp-a9be5`), `PORT` (8080), `GEO_BACKEND` (`firestore`), `LOCATION_STREAMS_BACKEND`, `LOCATION_IDLE_MERGED_CURSOR`, `LOCATION_ADAPTIVE_FRESHNESS`, `ORA_ADAPTIVE_PRESENCE` (mobile dart-define), `DRIVER_AUTO_APPROVE` (**default OFF** — production/staging `false`; dev scripts opt in), `REQUIRE_APP_CHECK`, `ORA_INTERNAL_WORKER_TOKEN`, `GOOGLE_APPLICATION_CREDENTIALS`, `WALLET_COMMISSION_BPS` (default 10%). Deploy scripts actively strip `REDIS_URL` + `--clear-vpc-connector`.

## 6. Commands

```bash
# Backend dev (emulator stack)
backend/auth-service/scripts/dev_local_stack.sh      # emulators + backend
# or: firebase emulators:start --project oraapp-a9be5   (firestore:8181 rtdb:9000)
#     dev_emulator_backend.sh                          (backend on :8080, GEO_BACKEND=firestore)

# Tests
cd backend/auth-service && npx vitest run             # 784 tests (maxForks:4 bound)
npx tsx scripts/run_local_emulator_e2e.ts             # 52-step live E2E (needs stack up)
npx tsx scripts/test_adaptive_presence.ts             # 18 checks
npx tsx scripts/test_driver_admin.ts                  # 8 checks
npx tsx scripts/test_marketplace_e2e.ts               # 45 checks
npx tsx scripts/test_marketplace_fidelity.ts          # 42 checks
npx tsx scripts/verify_vendor_gate.ts                 # 10 checks
cd .. && npx mocha --timeout 30000 test/firestore.rules.test.mjs   # 43 (needs emulator)
npx mocha --timeout 30000 test/database.rules.test.mjs              # 11 (needs emulator)
cd mobile && flutter test && flutter analyze          # 876 tests, 4 pre-existing infos

# Deploy (approval-gated)
backend/auth-service/scripts/deploy_production_cloud_run.sh   # min=0, no VPC, oraapp-a9be5
backend/auth-service/scripts/test_env_{up,down,deadman}.sh    # temp E2E env lifecycle
```

## 7. Known limitations / blockers

- Old-project Redis/VPC deletion **BLOCKED BY `BILLING_DISABLED`** — resources dormant at $0, resurface only if billing re-enabled.
- Old launchd agent `com.ora.auth-service.dev` was crash-looping on a stale repo path — plist repointed to `Ora-app-orange`, PATH fixed in `launchd_entry.sh`, agent **unloaded** (re-enable manually if a long-lived non-emulator backend is wanted; needs `secrets/service-account.json`).
- Backend suite occasionally throws transport-level socket hang-ups under heavy parallel CPU (documented mechanism — rerun; `maxForks:4` bounds it). Don't run `flutter test` concurrently with `vitest run`.
- Test UIDs with fixed emails accumulate wallet commission across runs — E2E scripts self top-up.
- Real-device FCM and App Check attestation: **NOT VERIFIED** this pass (staging-verified earlier; final cloud E2E pending CLOUD GO).

## 8. Recommended next development sequence

1. **Admin dashboard backend** (driver/vendor approvals UI surface, wallet resolve, ride monitor) — backend endpoint exists, biggest operational gap.
2. **Production Auth/data migration tooling + run** (UID-preserving cutover from old project).
3. **Production Scheduler + Tasks wiring** on `oraapp-a9be5` (endpoints already live).
4. Observability (dashboards/alerts on structured logs).
5. Marketplace photo Storage migration (analyzed, deferred to first scale signal).
