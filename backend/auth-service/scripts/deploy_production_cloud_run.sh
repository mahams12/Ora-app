#!/usr/bin/env bash
# Deploy ora-auth-service (production Cloud Run). No secret values printed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="${GCP_PROJECT_ID:-ora-app-d8112}"
REGION="${GCP_REGION:-us-central1}"
SERVICE="${PRODUCTION_CLOUD_RUN_SERVICE:-ora-auth-service}"
SA_EMAIL="${CLOUD_RUN_RUNTIME_SA:-firebase-adminsdk-fbsvc@${PROJECT}.iam.gserviceaccount.com}"

if ! command -v gcloud >/dev/null 2>&1; then
  echo "ERROR: gcloud not found" >&2
  exit 2
fi

if [[ ! -f .env ]]; then
  echo "ERROR: missing $ROOT/.env" >&2
  exit 2
fi

# shellcheck disable=SC1091
set -a
source .env
set +a

: "${FIREBASE_PROJECT_ID:?FIREBASE_PROJECT_ID required in .env}"
: "${PRODUCTION_GOOGLE_MAPS_SERVER_KEY:?PRODUCTION_GOOGLE_MAPS_SERVER_KEY required}"
: "${PRODUCTION_ORA_INTERNAL_WORKER_TOKEN:?PRODUCTION_ORA_INTERNAL_WORKER_TOKEN required}"

echo "== production deploy project=$PROJECT region=$REGION service=$SERVICE =="
gcloud config set project "$PROJECT" >/dev/null

gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com --project="$PROJECT"

chmod +x scripts/wire_production_redis.sh scripts/wire_production_server_secrets.sh
./scripts/wire_production_redis.sh
./scripts/wire_production_server_secrets.sh

ENV_VARS="FIREBASE_PROJECT_ID=${FIREBASE_PROJECT_ID},REQUIRE_APP_CHECK=true,ORA_ENV=production,NODE_ENV=production"
# L2 Step 2 — optional RTDB URL (Admin SDK only; never ship to Flutter).
if [[ -n "${FIREBASE_DATABASE_URL:-}" ]]; then
  ENV_VARS="${ENV_VARS},FIREBASE_DATABASE_URL=${FIREBASE_DATABASE_URL}"
fi

VPC_CONNECTOR="${PRODUCTION_VPC_CONNECTOR:-ora-staging-vpc}"
REDIS_SECRET_NAME="${PRODUCTION_REDIS_SECRET_NAME:-ora-production-redis-url}"
MAPS_SECRET_NAME="${PRODUCTION_MAPS_SECRET_NAME:-ora-production-google-maps-server-key}"
WORKER_SECRET_NAME="${PRODUCTION_WORKER_SECRET_NAME:-ora-production-internal-worker-token}"

SECRETS_LIST="GOOGLE_MAPS_SERVER_KEY=${MAPS_SECRET_NAME}:latest,ORA_INTERNAL_WORKER_TOKEN=${WORKER_SECRET_NAME}:latest"

if ! gcloud secrets describe "$REDIS_SECRET_NAME" --project="$PROJECT" >/dev/null 2>&1; then
  echo "ERROR: missing Redis secret $REDIS_SECRET_NAME" >&2
  exit 2
fi

SECRETS_LIST="REDIS_URL=${REDIS_SECRET_NAME}:latest,${SECRETS_LIST}"

DEPLOY_ARGS=(
  --project="$PROJECT"
  --region="$REGION"
  --source=.
  --platform=managed
  --allow-unauthenticated
  --service-account="$SA_EMAIL"
  --set-env-vars="$ENV_VARS"
  --set-secrets="$SECRETS_LIST"
  --vpc-connector="$VPC_CONNECTOR"
  --vpc-egress=private-ranges-only
  --min-instances=0
  --max-instances=10
  --memory=512Mi
  --cpu=1
  --timeout=300
  --port=8080
)

echo "== deploy Cloud Run production =="
gcloud run deploy "$SERVICE" "${DEPLOY_ARGS[@]}"

URL="$(gcloud run services describe "$SERVICE" --project="$PROJECT" --region="$REGION" --format='value(status.url)')"
REV="$(gcloud run services describe "$SERVICE" --project="$PROJECT" --region="$REGION" --format='value(status.latestReadyRevisionName)')"
OUT="$ROOT/../../mobile/.production_api_url"
printf '%s/v1\n' "${URL%/}" >"$OUT"
echo "PRODUCTION_API_BASE_URL=$(cat "$OUT")"
echo "REVISION=$REV"
echo "HEALTHZ=${URL%/}/healthz/"

curl -fsS "${URL%/}/healthz/" | head -c 200
echo
