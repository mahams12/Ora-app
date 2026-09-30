# D1 Real FCM — physical proof (2026-09-30, retry)

## Samsung ADB: **PASS**

```
RF8R40ZQ1JH    device
emulator-5554  device
```

## Run summary

| Gate | Result |
|------|--------|
| Samsung adb authorized | **PASS** |
| Driver auth (+923012345677 / 000000) | **PASS** |
| Driver open rides tab (UI automation) | **FAIL** — shell often still on passenger home; non-blocking for FCM |
| FCM token in Firestore (`hasToken`, hashed doc id) | **PASS** — `driverUid=SRjL7BJgCKTduhtpjtYMRZMq5fD2`, `tokenDocCount=1` |
| Fresh SEARCHING ride + N4 wave | **PASS** — via `staging_d1_dispatch_prep.ts` (API, no Places UI) |
| `dispatch-tick` | **PASS** — `wave_completed`, `invitedCount=1`, driver in wave |
| `dispatch-fcm-sweep` | **PASS** — `delivered=2`, `failed=0` |
| Physical notification (dumpsys) | **PASS** — `com.ora.ora` + **New ride request** in notification service dump |

**Proof rideId (this run):** `762867a3-e4ac-42e1-890a-284740b5b2ce`  
**Artifact:** `mobile/.e2e_artifacts/d1_real_fcm_physical_proof_report.json`

## How this run worked

1. Debug staging APK already on Samsung (driver session registers token).
2. **`backend/auth-service/scripts/staging_d1_dispatch_prep.ts`** — driver `go-online`, `location/update` at Liberty pickup, passenger `pricing/estimate` + `POST /rides`, then worker `dispatch-tick` + `dispatch-fcm-sweep` (token from Cloud Run env via gcloud).
3. **`mobile/.e2e_artifacts/d1_real_fcm_physical_proof.py`** — driver login on Samsung, token check, API prep (default `ORA_D1_USE_API_PREP=1`), notification dump check.

Passenger UI ride creation was **not** used (no `ORA_GOOGLE_PLACES_API_KEY` in this shell); API path is valid staging proof per ops doc (real Redis N3, real outbox, real FCM).

## Notification tap continuation (2026-09-30)

See **[D1_NOTIFICATION_TAP_PHYSICAL_PROOF.md](./D1_NOTIFICATION_TAP_PHYSICAL_PROOF.md)** for ride `762867a3-e4ac-42e1-890a-284740b5b2ce`.

| Tap gate | Result |
|----------|--------|
| Notification exists | **PASS** |
| Notification tap | **PASS** |
| Navigation → Open rides | **PASS** |
| Target ride visible | **BLOCKED** (expired; API `rideCount=0`) |
| Duplicate / safety | **PASS** |

## Not proven in this session

| Item | Status |
|------|--------|
| Target ride visible after tap (expired ride) | **BLOCKED** — see tap report |
| Duplicate FCM with two tray notifications | **N/A** — single notification consumed on first tap |
| `build_staging_apk.sh` with real Places key | **Not run** (Places still placeholder in prior debug APK) |

## Resume commands

```bash
export GOOGLE_APPLICATION_CREDENTIALS=backend/auth-service/secrets/service-account.json
export ORA_INTERNAL_WORKER_TOKEN="$(gcloud run services describe ora-auth-service-staging \
  --region=us-central1 --project=ora-app-d8112 --format=json | python3 -c '…')"
cd backend/auth-service && npx tsx scripts/staging_d1_dispatch_prep.ts

python3 mobile/.e2e_artifacts/d1_real_fcm_physical_proof.py
```

Sweeps only: `backend/auth-service/scripts/run_staging_d1_fcm_sweep.sh`

---

## FINAL physical verification (fresh ride) — 2026-09-30

Full end-to-end on Samsung: **fresh ride** `212d0068-9ad2-4658-bc68-da13b0784515` → dispatch → FCM → **physical notification tap** → **Open rides** → **API + UI rideId visible** (unexpired). All gates **PASS**.

Details: **[D1_NOTIFICATION_TAP_PHYSICAL_PROOF.md](./D1_NOTIFICATION_TAP_PHYSICAL_PROOF.md)** · JSON: `d1_fresh_physical_final_report.json`

Orchestrator: `python3 mobile/.e2e_artifacts/d1_fresh_physical_final_verify.py`

---

## FINAL VERDICT

**D1 FINAL PHYSICAL VERDICT = GREEN**

**D1 REAL FCM = GREEN** — core FCM path plus closed tap/open-rides/visibility gap on a **new non-expired** ride (no Firestore mutation, no deep-link-only shortcut).
