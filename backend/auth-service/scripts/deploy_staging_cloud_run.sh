#!/usr/bin/env bash
# Deploy ora-auth-service to Google Cloud Run (staging).
# Requires: gcloud CLI, project Owner (or equivalent) to enable APIs once.
# Does NOT print secret values.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="${GCP_PROJECT_ID:-ora-app-d8112}"
REGION="${GCP_REGION:-us-central1}"
SERVICE="${CLOUD_RUN_SERVICE:-ora-auth-service-staging}"
SA_EMAIL="${CLOUD_RUN_RUNTIME_SA:-firebase-adminsdk-fbsvc@${PROJECT}.iam.gserviceaccount.com}"

if ! command -v gcloud >/dev/null 2>&1; then
  echo "ERROR: gcloud not found. Install Google Cloud SDK." >&2
  exit 2
fi

if [[ ! -f .env ]]; then
  echo "ERROR: missing $ROOT/.env (copy from .env.example)" >&2
  exit 2
fi

# shellcheck disable=SC1091
set -a
source .env
set +a

: "${FIREBASE_PROJECT_ID:?FIREBASE_PROJECT_ID required in .env}"
: "${GOOGLE_MAPS_SERVER_KEY:?GOOGLE_MAPS_SERVER_KEY required in .env for pricing/estimate}"

REQUIRE_APP_CHECK="${REQUIRE_APP_CHECK:-false}"
ORA_ENV="${ORA_ENV:-staging}"
NODE_ENV="${NODE_ENV:-staging}"
: "${ORA_INTERNAL_WORKER_TOKEN:?ORA_INTERNAL_WORKER_TOKEN required in .env for staging deploy}"

echo "== gcloud project: $PROJECT region: $REGION service: $SERVICE =="
gcloud config set project "$PROJECT" >/dev/null

echo "== enabling APIs (requires project Owner once) =="
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com --project="$PROJECT"

echo "== upsert Secret Manager (Maps + worker token; no values printed) =="
chmod +x scripts/wire_staging_server_secrets.sh
./scripts/wire_staging_server_secrets.sh

ENV_VARS="FIREBASE_PROJECT_ID=${FIREBASE_PROJECT_ID},REQUIRE_APP_CHECK=${REQUIRE_APP_CHECK},ORA_ENV=${ORA_ENV},NODE_ENV=${NODE_ENV}"

VPC_CONNECTOR="${VPC_CONNECTOR:-ora-staging-vpc}"
REDIS_SECRET_NAME="${REDIS_SECRET_NAME:-ora-staging-redis-url}"
MAPS_SECRET_NAME="${MAPS_SECRET_NAME:-ora-staging-google-maps-server-key}"
WORKER_SECRET_NAME="${WORKER_SECRET_NAME:-ora-staging-internal-worker-token}"

SECRETS_LIST="GOOGLE_MAPS_SERVER_KEY=${MAPS_SECRET_NAME}:latest,ORA_INTERNAL_WORKER_TOKEN=${WORKER_SECRET_NAME}:latest"

DEPLOY_ARGS=(
  --project="$PROJECT"
  --region="$REGION"
  --source=.
  --platform=managed
  --allow-unauthenticated
  --service-account="$SA_EMAIL"
  --set-env-vars="$ENV_VARS"
  --min-instances=0
  --max-instances=3
  --memory=512Mi
  --cpu=1
  --timeout=300
  --port=8080
)

# Memorystore + server secrets (never plain env for these values).
if gcloud secrets describe "$REDIS_SECRET_NAME" --project="$PROJECT" >/dev/null 2>&1; then
  SECRETS_LIST="REDIS_URL=${REDIS_SECRET_NAME}:latest,${SECRETS_LIST}"
  DEPLOY_ARGS+=(
    --vpc-connector="$VPC_CONNECTOR"
    --vpc-egress=private-ranges-only
  )
else
  echo "ERROR: Redis secret $REDIS_SECRET_NAME missing — run scripts/wire_staging_redis.sh first" >&2
  exit 2
fi

DEPLOY_ARGS+=(--set-secrets="$SECRETS_LIST")

echo "== deploy Cloud Run from source (Dockerfile) =="
gcloud run deploy "$SERVICE" "${DEPLOY_ARGS[@]}"

URL="$(gcloud run services describe "$SERVICE" --project="$PROJECT" --region="$REGION" --format='value(status.url)')"
OUT="$ROOT/../../mobile/.staging_api_url"
printf '%s/v1\n' "${URL%/}" >"$OUT"
echo "STAGING_API_BASE_URL=$(cat "$OUT")"
# Cloud Run frontends may not forward bare /healthz; /healthz/ reaches the app.
echo "HEALTHZ=${URL%/}/healthz/"

curl -fsS "${URL%/}/healthz/" | head -c 200
echo
