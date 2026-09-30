# Staging deploy readiness (internal)

## Backend (`auth-service`)

| Item | Status |
|------|--------|
| Runtime | Node 20 Express modular monolith |
| Container | `Dockerfile` multi-stage, `PORT=8080`, `CMD node dist/index.js` |
| Health | `GET /healthz` → `{ ok, service }` |
| Required env | `FIREBASE_PROJECT_ID`; ADC via service account on Cloud Run |
| Optional env | `REDIS_URL`, `GOOGLE_MAPS_SERVER_KEY`, `ORA_INTERNAL_WORKER_TOKEN`, `REQUIRE_APP_CHECK` |
| CORS | Not used (native mobile clients) |
| RTDB | Not required for core auth/rides/pricing paths |
| Local-only | `adb reverse`, Mac `dev_backend.sh`, in-memory rate limit (multi-instance caveat) |

## Mobile

| Item | Status |
|------|--------|
| Config | `ORA_ENV`, `ORA_API_BASE_URL`, `ORA_APP_CHECK`, `ORA_GOOGLE_PLACES_API_KEY` |
| Staging default URL | `https://api-staging.ora.app/v1` (no DNS without domain — use `ORA_API_BASE_URL` override) |
| Shareable build | `mobile/scripts/build_staging_apk.sh` |

## Hosting choice

**Google Cloud Run** — matches repo architecture; free-tier friendly `*.run.app` HTTPS URL; platform-managed restart/scaling.

## Blocker encountered (2026-09-29)

Deploy attempted with Firebase Admin SDK service account only:

- Cannot enable `run.googleapis.com` / Cloud Build / Artifact Registry
- Cannot `gcloud run deploy`

**Required human step:** `gcloud auth login` with a **GCP project Owner/Editor** on `ora-app-d8112`, then run `backend/auth-service/scripts/deploy_staging_cloud_run.sh`.

OAuth URL was issued during agent run; interactive code entry was not completed in this environment.
