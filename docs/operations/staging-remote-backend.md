# Staging remote backend (shareable APK)

Goal: phones reach **HTTPS** `auth-service` without Mac, USB, or `adb reverse`.

## Platform

**Google Cloud Run** in Firebase project `ora-app-d8112` (matches existing `Dockerfile` and architecture docs).

Public URL shape: `https://ora-auth-service-staging-<hash>-<region>.run.app`

## One-time GCP (project Owner)

1. Sign in: `gcloud auth login` (human Owner account — not the Firebase Admin SDK key alone).
2. Enable APIs (or run deploy script which enables them):
   - Cloud Run Admin API
   - Cloud Build API
   - Artifact Registry API
3. Ensure runtime service account `firebase-adminsdk-fbsvc@ora-app-d8112.iam.gserviceaccount.com` can access Firestore (already used locally).

## Deploy backend

```bash
cd backend/auth-service
cp .env.example .env   # if needed; set FIREBASE_PROJECT_ID, GOOGLE_MAPS_SERVER_KEY, ORA_INTERNAL_WORKER_TOKEN
chmod +x scripts/deploy_staging_cloud_run.sh
./scripts/deploy_staging_cloud_run.sh
```

Writes `mobile/.staging_api_url` (e.g. `https://….run.app/v1`).

Staging Cloud Run loads **`REDIS_URL`**, **`GOOGLE_MAPS_SERVER_KEY`**, and **`ORA_INTERNAL_WORKER_TOKEN`** from Secret Manager (`ora-staging-redis-url`, `ora-staging-google-maps-server-key`, `ora-staging-internal-worker-token`). Values stay in local `.env` for deploy/sync only — not plain Cloud Run env vars.

Optional: `REDIS_URL` in `.env` for local GEO/nearby; staging service uses the Memorystore secret above.

## Cloud Scheduler (staging workers)

Cloud Scheduler cannot bind Secret Manager to custom HTTP headers. Staging uses **Scheduler (OAuth)** → **Cloud Run Job** (worker token from Secret Manager) → HTTPS internal routes.

```bash
cd backend/auth-service
./scripts/deploy_staging_cloud_run.sh
chmod +x scripts/wire_staging_cloud_scheduler.sh
./scripts/wire_staging_cloud_scheduler.sh
```

## Firestore indexes (required for ride lists)

`GET /v1/rides` uses composite queries on `rides`. Deploy indexes from repo root before device QA:

```bash
firebase deploy --only firestore:indexes --project ora-app-d8112
```

If deploy is blocked on rules, create the indexes from `firestore.indexes.json` in Firebase Console or via `gcloud firestore indexes composite create`. Without them, authenticated ride history returns **500** (`Unexpected server error.`) even when Cloud Run `/healthz/` is OK.

## Ephemeral TTL cleanup (worker)

`POST /v1/internal/storage/expires-at-cleanup` (header `X-Ora-Worker-Token`) deletes **expired only**:

- `idempotencyRecords` where `expiresAt` ≤ now (7-day contract)
- `pricingSnapshots` where `expiresAt` ≤ now (10-minute estimate TTL)
- `locationStreams` where `expiresAt` ≤ now (sliding registry TTL; active streams refresh `expiresAt` on each accept)

Optional query: `?limit=` (default 100, max 200 per collection). Schedule via Cloud Scheduler; not a tight polling loop.

## Build shareable staging APK

```bash
export ORA_GOOGLE_PLACES_API_KEY=...   # client Places key only
chmod +x mobile/scripts/build_staging_apk.sh
./mobile/scripts/build_staging_apk.sh
```

Uses:

- `ORA_ENV=staging`
- `ORA_API_BASE_URL` from `.staging_api_url`
- HTTPS only (no `ORA_ALLOW_HTTP_API`)

## N3 nearby benchmark (observability)

After deploy, each worker `GET /v1/internal/drivers/nearby` emits one structured **`N3_NEARBY`** log (Cloud Logging) with `geoHits`, `redisGetCount`, Firestore read/query counts, `eligibleCount`, compact `rejected` buckets, and `durationMs`. No PII or tokens are logged.

```bash
# From mobile/.staging_api_url (includes /v1 suffix)
BASE="$(cat mobile/.staging_api_url)"
# Worker token: same value as Cloud Run env ORA_INTERNAL_WORKER_TOKEN (never commit)
export ORA_INTERNAL_WORKER_TOKEN='…'
curl -sS -G "${BASE%/}/internal/drivers/nearby" \
  -H "X-Ora-Worker-Token: ${ORA_INTERNAL_WORKER_TOKEN}" \
  --data-urlencode "lat=31.52" \
  --data-urlencode "lng=74.35" \
  --data-urlencode "radiusKm=10" \
  --data-urlencode "limit=30"
```

Requires **`REDIS_URL`** on the Cloud Run revision; otherwise **503** `DEPENDENCY_ERROR`. Compare logs for repeated calls at the same pickup (0 vs busy GEO) before any batching work.

Full staging benchmark (seed 100 bench drivers + 10/30/100 limits × repeated runs):

```bash
cd backend/auth-service
# .env must include REDIS_URL (same instance Cloud Run uses) and ORA_INTERNAL_WORKER_TOKEN
chmod +x scripts/run_n3_staging_benchmark.sh
./scripts/run_n3_staging_benchmark.sh
# Report: mobile/.e2e_artifacts/N3_STAGING_BENCHMARK_REPORT.json
```

Without `REDIS_URL` on Cloud Run and locally, the benchmark stops with **BLOCKED** (see `mobile/.e2e_artifacts/N3_STAGING_BENCHMARK_REPORT.md`).

## Verify Mac-independent

1. `curl https://<host>/healthz/` (trailing slash — bare `/healthz` may 404 at the Cloud Run edge)
2. Stop local backend; clear `adb reverse`.
3. Install APK; sign in with Firebase test numbers; confirm `/v1/auth/me`.

## Security

- Never put service-account JSON, Maps **server** key, or Redis URL in Flutter `dart-define`.
- Staging keeps `REQUIRE_APP_CHECK=false` until App Check is wired on clients.
