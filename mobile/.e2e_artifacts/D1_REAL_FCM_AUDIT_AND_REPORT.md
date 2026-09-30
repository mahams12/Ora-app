# D1 Real FCM — Step 1 audit + slice status (2026-09-30)

## Step 1 — Existing D1 (already implemented on backend)

| Area | Status | Location |
|------|--------|----------|
| Device token register/clear | **Done** | `POST/DELETE /v1/drivers/device-tokens`, `device_token_service.ts` |
| Token doc ID | **SHA-256 prefix** (`deviceTokenDocId`) | `d1_types.ts`; token value stored server-side for FCM send only |
| N4 outbox | **Done** | `ride.dispatch.wave_completed` in `dispatch_wave_service.ts` |
| D1 projector + sweep | **Done** | `dispatch_fcm_projector.ts`, `POST /v1/internal/outbox/dispatch-fcm-sweep` |
| FCM sender | **Real Admin SDK** | `createFirebaseFcmSender()` in `index.ts` via ADC |
| Payload | **Data-only** | `type=DISPATCH_INVITE`, `rideId`, `waveNumber`, `eventId` |
| Lease / fencing / idempotency | **Done** | H2/H4/H5 in projector + `delivery_d1.test.ts` |
| Worker auth | **Done** | `X-Ora-Worker-Token` on internal routes |
| Unit tests | **Done** | `delivery_d1.test.ts`, N4 in `dispatch.test.ts` |

## What was missing for real end-to-end FCM (before this slice)

1. **Mobile:** no `firebase_messaging`, no token registration API calls, no `DISPATCH_INVITE` handler, no notification tap → open rides.
2. **Ops:** no Cloud Scheduler in repo for `dispatch-sweep` + `dispatch-fcm-sweep` (events stay `PENDING` until worker HTTP).
3. **Physical proof:** requires authorized USB device + staging APK with FCM + driver in N4 `driverIds[]` (backend online/nearby).

## FCM CONFIG (server)

| Item | Value |
|------|--------|
| **Firebase project** | `ora-app-d8112` (`FIREBASE_PROJECT_ID`) |
| **FCM server** | Firebase Admin `messaging().send()` — data-only, no extra FCM env vars |
| **Credentials** | Application Default Credentials on Cloud Run (`firebase-adminsdk-fbsvc@…`) |
| **Secret storage** | No FCM-specific secret; `ORA_INTERNAL_WORKER_TOKEN` for internal sweeps (Secret Manager / deploy env) |
| **Cloud Run revision** | Latest staging deploy (e.g. `ora-auth-service-staging-00019-z2h` at time of N3 MGET) — unchanged for D1 backend |

## Physical proof status

| Check | Result |
|-------|--------|
| Samsung `RF8R40ZQ1JH` | **adb unauthorized** — cannot automate driver device |
| Emulator `emulator-5554` | Available; FCM delivery **unreliable** vs physical device |
| Real notification on device | **Not proven in this session** |

---

## FINAL (this session)

**D1 REAL FCM = BLOCKED** (physical notification not demonstrated)

Reason: mobile FCM client path was not in production APK until this slice’s Flutter changes; USB driver device unauthorized; no honest claim of tray notification + tap without user-run staging proof.

### After installing new staging APK (user verification checklist)

1. Driver login `+923012345677` / OTP `000000` → enter driver shell → token registers via API.
2. Passenger creates ride on staging → run worker chain (see `docs/operations/staging-d1-dispatch-fcm.md`).
3. Confirm Cloud Logging: `D1_DISPATCH_FCM` outcome `delivered`, `sent` ≥ 1.
4. Driver device shows notification; tap → **Open ride requests** tab; ride visible via `GET /v1/rides/open` revalidation.

### TESTS (backend, unchanged D1 logic)

- Focused D1: `delivery_d1.test.ts`
- Full suite: run `npm test` in `backend/auth-service` (366 tests at last green)

### FILES CHANGED (this slice)

**Mobile**
- `pubspec.yaml` — `firebase_messaging`, `flutter_local_notifications`
- `lib/core/notifications/*` — D1 payload parse, local notification, FCM service
- `lib/features/driver/data/driver_device_token_remote_data_source.dart`
- `lib/app/app.dart`, `lib/app/di/providers.dart`, `lib/main.dart`
- `lib/app/router/routes.dart`, `app_router.dart` — `/driver/open`
- `lib/features/driver/presentation/views/driver_shell_view.dart` — register/clear token
- `lib/core/network/api_client.dart` — `DELETE` helper
- `android/app/src/main/AndroidManifest.xml` — `POST_NOTIFICATIONS`
- `test/core/notifications/dispatch_invite_message_test.dart`

**Ops / docs**
- `docs/operations/staging-d1-dispatch-fcm.md`
- `backend/auth-service/scripts/run_staging_d1_fcm_sweep.sh`

**Backend D1:** no logic changes (already implemented).
