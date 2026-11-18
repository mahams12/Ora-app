#!/usr/bin/env bash
# Temporary migration-test environment UP — oraapp-a9be5 / asia-south1.
#
# COST-CONTROLLED by construction:
#   Cloud Run:   min-instances=0, max-instances=2, concurrency=50,
#                request-based billing (CPU allocated only while serving)
#   Cloud Tasks: ora-dispatch at 5 dispatches/sec, 5 concurrent max
#   Scheduler:   one */5 job hitting /v1/internal/sweeps/all (OIDC)
#   No Redis, no VPC connector, no Memorystore, no always-on anything.
#
# Arms ONLY with:  ORA_TEMP_TEST_GO=1 ./scripts/test_env_up.sh
# Requires:        billing linked; gcloud auth as project editor.
# Optional env:    ORA_TEST_MAPS_KEY  — if set, Secrets Manager + Google
#                  Routes enabled; otherwise haversine (still $0).
#                  ORA_TEST_WORKER_TOKEN — else a random one is generated.
#
# Teardown counterpart: ./scripts/test_env_down.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "${ORA_TEMP_TEST_GO:-0}" != "1" ]]; then
  echo "Refusing: set ORA_TEMP_TEST_GO=1 to arm the test deployment." >&2
  exit 2
fi

PROJECT="${GCP_PROJECT_ID:-oraapp-a9be5}"
REGION="${GCP_REGION:-asia-south1}"
SERVICE="${SERVICE_NAME:-ora-auth-service}"
SA_NAME="ora-tasks-invoker"
SA_EMAIL="${SA_NAME}@${PROJECT}.iam.gserviceaccount.com"
QUEUE="ora-dispatch"
SCHED_JOB="ora-worker-sweeps"
PROJNUM="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"

echo "== test-env up: project=$PROJECT region=$REGION service=$SERVICE =="

# ── 1. APIs (control-plane; all free-tier at this scale) ──────────────
gcloud services enable run.googleapis.com cloudbuild.googleapis.com \
  artifactregistry.googleapis.com secretmanager.googleapis.com \
  cloudtasks.googleapis.com cloudscheduler.googleapis.com \
  ${ORA_TEST_MAPS_KEY:+routes.googleapis.com} \
  --project="$PROJECT"

# ── 2. Invoker service account + token-creator for Tasks ──────────────
gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT" \
  >/dev/null 2>&1 || gcloud iam service-accounts create "$SA_NAME" \
  --project="$PROJECT" --display-name="Cloud Tasks dispatch invoker"

gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --member="serviceAccount:service-${PROJNUM}@gcp-sa-cloudtasks.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountTokenCreator" --project="$PROJECT" \
  --condition=None >/dev/null

# ── 3. Secrets (worker token + optional maps key) ─────────────────────
WORKER_TOKEN="${ORA_TEST_WORKER_TOKEN:-$(openssl rand -hex 24)}"
printf '%s' "$WORKER_TOKEN" | gcloud secrets create ora-test-worker-token \
  --data-file=- --project="$PROJECT" 2>/dev/null || \
printf '%s' "$WORKER_TOKEN" | gcloud secrets versions add \
  ora-test-worker-token --data-file=- --project="$PROJECT" >/dev/null

# Runtime SA (compute default — same as prod's firebase-adminsdk pattern) must
# be able to read the mounted secrets; Editor alone does NOT cover this.
RUNTIME_SA="${PROJNUM}-compute@developer.gserviceaccount.com"
for s in ora-test-worker-token ora-test-google-maps-key; do
  gcloud secrets add-iam-policy-binding "$s" \
    --member="serviceAccount:${RUNTIME_SA}" \
    --role="roles/secretmanager.secretAccessor" \
    --project="$PROJECT" >/dev/null 2>&1 || true
done

SECRETS_LIST="ORA_INTERNAL_WORKER_TOKEN=ora-test-worker-token:latest"
if [[ -n "${ORA_TEST_MAPS_KEY:-}" ]]; then
  printf '%s' "$ORA_TEST_MAPS_KEY" | gcloud secrets create \
    ora-test-google-maps-key --data-file=- --project="$PROJECT" \
    2>/dev/null || printf '%s' "$ORA_TEST_MAPS_KEY" | \
    gcloud secrets versions add ora-test-google-maps-key \
    --data-file=- --project="$PROJECT" >/dev/null
  SECRETS_LIST="${SECRETS_LIST},GOOGLE_MAPS_SERVER_KEY=ora-test-google-maps-key:latest"
  ROUTING="google"
else
  ROUTING="haversine"
fi

# ── 4. Cloud Run deploy — tight cost envelope ─────────────────────────
ENV_VARS="FIREBASE_PROJECT_ID=${PROJECT},ORA_ENV=staging,NODE_ENV=production"
ENV_VARS+=",REQUIRE_APP_CHECK=false"
ENV_VARS+=",FIREBASE_DATABASE_URL=https://${PROJECT}-default-rtdb.asia-southeast1.firebasedatabase.app"
ENV_VARS+=",GEO_BACKEND=firestore,LOCATION_STREAMS_BACKEND=firestore"
ENV_VARS+=",LOCATION_ADAPTIVE_FRESHNESS=true,LOCATION_IDLE_MERGED_CURSOR=true,DRIVER_AUTO_APPROVE=true"
ENV_VARS+=",LOCATION_TRIP_GEO_MIN_INTERVAL_MS=45000"
ENV_VARS+=",ORA_ROUTING_PROVIDER=${ROUTING}"
ENV_VARS+=",DISPATCH_TASKS_ENABLED=false"   # enabled in pass 2 once URL known
ENV_VARS+=",ORA_INTERNAL_OIDC_ALLOWED_SA=${SA_EMAIL}"

gcloud run deploy "$SERVICE" \
  --project="$PROJECT" --region="$REGION" --source=. \
  --platform=managed --allow-unauthenticated \
  --clear-vpc-connector \
  --min-instances=0 --max-instances=2 --concurrency=50 \
  --memory=512Mi --cpu=1 --timeout=300 --port=8080 \
  --set-env-vars="$ENV_VARS" --set-secrets="$SECRETS_LIST"

URL="$(gcloud run services describe "$SERVICE" \
  --project="$PROJECT" --region="$REGION" --format='value(status.url)')"
BASE="${URL%/}"

# Tasks caller must be able to invoke the service.
gcloud run services add-iam-policy-binding "$SERVICE" \
  --member="serviceAccount:${SA_EMAIL}" --role="roles/run.invoker" \
  --project="$PROJECT" --region="$REGION" >/dev/null

# ── 5. Pass 2: enable Cloud Tasks wake-ups with real target URL ───────
gcloud run services update "$SERVICE" \
  --project="$PROJECT" --region="$REGION" \
  --update-env-vars="DISPATCH_TASKS_ENABLED=true,TASKS_PROJECT_ID=${PROJECT},TASKS_LOCATION=${REGION},TASKS_QUEUE=${QUEUE},TASKS_TARGET_BASE_URL=${BASE},TASKS_OIDC_SERVICE_ACCOUNT=${SA_EMAIL}"

# ── 6. Cloud Tasks queue — rate-capped for test ───────────────────────
gcloud tasks queues describe "$QUEUE" --location="$REGION" \
  --project="$PROJECT" >/dev/null 2>&1 || \
gcloud tasks queues create "$QUEUE" --location="$REGION" \
  --project="$PROJECT" \
  --max-attempts=10 --min-backoff=1s --max-backoff=30s --max-doublings=4 \
  --max-concurrent-dispatches=5 --max-dispatches-per-second=5
gcloud tasks queues resume "$QUEUE" --location="$REGION" \
  --project="$PROJECT" >/dev/null 2>&1 || true

# ── 7. Recovery sweep — single */5 Scheduler job → /sweeps/all ─────────
if ! gcloud scheduler jobs describe "$SCHED_JOB" --location="$REGION" \
    --project="$PROJECT" >/dev/null 2>&1; then
  gcloud scheduler jobs create http "$SCHED_JOB" \
    --project="$PROJECT" --location="$REGION" \
    --schedule="*/5 * * * *" --time-zone="UTC" \
    --uri="${BASE}/v1/internal/sweeps/all" --http-method=POST \
    --oidc-service-account-email="$SA_EMAIL" \
    --oidc-token-audience="$BASE"
fi
gcloud scheduler jobs resume "$SCHED_JOB" --location="$REGION" \
  --project="$PROJECT" >/dev/null 2>&1 || true

mkdir -p "$ROOT/../../mobile"
printf '%s/v1\n' "$BASE" > "$ROOT/../../mobile/.test_api_url"

cat <<EOF

== TEST ENV UP ==
  Service:  $BASE  (healthz: $BASE/healthz)
  Routing:  $ROUTING   FCM: real   App Check: OFF (temp only)
  Queue:    $QUEUE (5 rps / 5 concurrent, resumed)
  Sweep:    $SCHED_JOB */5 → /v1/internal/sweeps/all (resumed)

  Test APK: ORA_API_BASE_URL=$BASE/v1 \\
            ORA_FIREBASE_DATABASE_URL=https://${PROJECT}-default-rtdb.asia-southeast1.firebasedatabase.app
            (no ORA_FIREBASE_EMULATOR_HOST — real Firebase)

  TEARDOWN: ./scripts/test_env_down.sh   ← run when the window ends
EOF
