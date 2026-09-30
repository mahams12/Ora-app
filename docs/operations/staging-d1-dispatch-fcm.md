# Staging — real D1 FCM dispatch proof

Uses **remote Cloud Run only** (no local backend, no Firestore hacks).

## Prerequisites

- Staging APK built with `firebase_messaging` and driver token registration.
- `ORA_INTERNAL_WORKER_TOKEN` set locally (same as Cloud Run secret; never commit).
- Driver: approved, **online in Firestore** (N4/N3 path), FCM token registered via app.
- Redis wired for N3 on staging (see `staging-remote-backend.md`).

## Worker chain (after passenger creates ride)

From repo root, with `mobile/.staging_api_url` or `STAGING_API_BASE_URL`:

```bash
source backend/auth-service/.env   # ORA_INTERNAL_WORKER_TOKEN, FIREBASE_PROJECT_ID
BASE="${STAGING_API_BASE_URL:-$(cat mobile/.staging_api_url)}"
HDR=( -H "X-Ora-Worker-Token: ${ORA_INTERNAL_WORKER_TOKEN}" )

# N4 — process dispatch waves for SEARCHING rides
curl -sS -X POST "${BASE%/}/internal/rides/dispatch-sweep" "${HDR[@]}"

# D1 — deliver pending ride.dispatch.wave_completed → FCM
curl -sS -X POST "${BASE%/}/internal/outbox/dispatch-fcm-sweep" "${HDR[@]}"
```

Optional: `POST /internal/rides/dispatch-tick/:rideId` for a single ride.

## Verify (no tokens in logs)

Cloud Logging:

- `N4_DISPATCH_WAVE` / `N4_DISPATCH_TICK`
- `D1_DISPATCH_FCM` — `outcome`, `sent`, `skippedNoToken`, `eventId`
- `D1_DISPATCH_FCM_SWEEP` — `delivered`, `retryable`, `deadLetter`

Firestore (Console, server-only collections): `outboxEvents`, `outboxDeliveries`, `driverDeviceTokens` — do not paste token values into reports.

## Safety cases (manual)

| Case | Expected |
|------|----------|
| Expired / cancelled / assigned ride | Open list / offer APIs fail closed; notification is wake-only |
| Duplicate sweep | Delivery doc `ACKED`; no duplicate offers |
| Duplicate FCM | Client dedupes by `eventId`; same open-ride refresh |

## Scheduler (production follow-up, out of slice)

Cloud Scheduler → `dispatch-sweep` + `dispatch-fcm-sweep` on interval; not required for one-off proof.
