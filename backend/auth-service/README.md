# Ora Auth Service

**STATUS:** CURRENT pointer (README was historically Phase 2A-only).

Primary live snapshot: **[`docs/ORA_CURRENT_STATE.md`](../../docs/ORA_CURRENT_STATE.md)**

This service is the Ora Cloud Run modular monolith: **auth + rides + drivers + location + optional Redis GEO**.

## Quick links

| Topic | Doc |
| ----- | --- |
| Phase status / frontier | `docs/ORA_CURRENT_STATE.md` |
| API index | `docs/architecture/API_CONTRACT_INDEX.md` |
| Location flow | `docs/architecture/N_LOCATION_FLOW.md` |
| Request traces | `docs/architecture/N_REQUEST_FLOWS.md` |
| Troubleshooting | `docs/diagnostics/BACKEND_TROUBLESHOOTING.md` |
| N1 / N2A / N2C | `docs/implementation/n-series/` |

## Endpoints (summary)

Registered in `src/app.ts`:

| Area | Routes |
| ---- | ------ |
| Health | `GET /healthz` |
| Auth | `POST /v1/auth/register`, `GET /v1/auth/me`, `PATCH /v1/auth/profile` |
| Rides | `/v1/rides` (+ offers, progression, ratings, open discovery) |
| Drivers | `POST /v1/drivers/go-online`, `POST /v1/drivers/go-offline` |
| Location | `POST /v1/location/update` |
| Internal | expire / offer-expire / no-show / **dispatch** sweeps + tick; nearby; **D1 outbox→FCM sweep** (worker token) |
| Drivers | go-online / go-offline; **D1 device-tokens** register/clear |

N3 nearby, N4 dispatch, and D1 FCM projector are **worker-only** (`X-Ora-Worker-Token`).Identity is **always** from `admin.auth().verifyIdToken()`. Client-supplied `uid` / `role` are ignored.

## Local run

1. Firebase Console → service account JSON (store **outside** `mobile/`).
2. Copy `.env.example` → `.env`; set `GOOGLE_APPLICATION_CREDENTIALS`, `FIREBASE_PROJECT_ID`.
3. Optional: `REDIS_URL=redis://127.0.0.1:6379` for N2C.
4. Optional: `ORA_INTERNAL_WORKER_TOKEN` for internal sweeps.
5. `REQUIRE_APP_CHECK=false` for local; `true` for production (ADR-014).

```bash
cd backend/auth-service
npm ci
npm test
npm run dev
```

### Physical Android phone (USB)

**Keep the backend running once** (pick one):

```bash
cd backend/auth-service
./scripts/dev_backend.sh install   # macOS: auto-start at login, restarts if it crashes
# — or per session —
./scripts/dev_backend.sh start     # background daemon; idempotent
./scripts/dev_backend.sh status
./scripts/dev_backend.sh logs
```

After each USB plug-in (or when the app shows “Cannot reach Ora API”):

```bash
./scripts/dev_adb_reverse.sh       # all connected phones: 8081 → Mac :8080
```

Same via npm: `npm run dev:backend`, `npm run dev:adb-reverse`.

Foreground alternative (one terminal tab): `./scripts/run_local_device_backend.sh`

Flutter / shared debug APK (phone localhost **8081** → Mac **8080**):

```bash
cd mobile
flutter run -d <deviceId> \
  --dart-define=ORA_API_BASE_URL=http://127.0.0.1:8081/v1 \
  --dart-define=ORA_ALLOW_HTTP_API=true
```

Emulator (host loopback via `10.0.2.2`):

```bash
cd mobile
flutter run --dart-define=ORA_API_BASE_URL=http://10.0.2.2:8080/v1 \
  --dart-define=ORA_ALLOW_HTTP_API=true
```

## Proof scripts

See `package.json` scripts (`test:phase-n1-unit-proof`, `test:phase-n2a-unit-proof`, `test:phase-n2c-unit-proof`, `test:redis-geo-proof`, ride concurrency proofs). Root `package.json` wraps Firestore emulator proofs.

## Security notes

- Never put the service-account JSON in the Flutter project.
- Firestore rules deny client writes to rides/drivers/locationStreams/etc.
- Redis is non-authoritative (ADR-004).
