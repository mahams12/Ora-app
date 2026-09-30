#!/usr/bin/env bash
# Production Memorystore + Secret Manager (separate from staging). No secret values printed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="${GCP_PROJECT_ID:-ora-app-d8112}"
REGION="${GCP_REGION:-us-central1}"
REDIS_INSTANCE="${PRODUCTION_REDIS_INSTANCE:-ora-production-n3-redis}"
SECRET_NAME="${PRODUCTION_REDIS_SECRET_NAME:-ora-production-redis-url}"
SA_EMAIL="${CLOUD_RUN_RUNTIME_SA:-firebase-adminsdk-fbsvc@${PROJECT}.iam.gserviceaccount.com}"

gcloud config set project "$PROJECT" >/dev/null
gcloud services enable redis.googleapis.com secretmanager.googleapis.com --project="$PROJECT" >/dev/null 2>&1 || true

if ! gcloud redis instances describe "$REDIS_INSTANCE" --region="$REGION" >/dev/null 2>&1; then
  echo "== creating Memorystore instance $REDIS_INSTANCE (may take several minutes) =="
  gcloud redis instances create "$REDIS_INSTANCE" \
    --project="$PROJECT" \
    --region="$REGION" \
    --tier=basic \
    --size=1 \
    --redis-version=redis_7_0 \
    --network=default \
    --quiet
fi

STATE="$(gcloud redis instances describe "$REDIS_INSTANCE" --region="$REGION" --format='value(state)')"
if [[ "$STATE" != "READY" ]]; then
  echo "ERROR: Redis instance $REDIS_INSTANCE state=$STATE (expected READY)" >&2
  exit 2
fi

HOST="$(gcloud redis instances describe "$REDIS_INSTANCE" --region="$REGION" --format='value(host)')"
PORT="$(gcloud redis instances describe "$REDIS_INSTANCE" --region="$REGION" --format='value(port)')"
REDIS_URL="redis://${HOST}:${PORT}"

if ! gcloud secrets describe "$SECRET_NAME" --project="$PROJECT" >/dev/null 2>&1; then
  printf '%s' "$REDIS_URL" | gcloud secrets create "$SECRET_NAME" --data-file=- --project="$PROJECT"
  echo "OK created secret name=$SECRET_NAME"
else
  printf '%s' "$REDIS_URL" | gcloud secrets versions add "$SECRET_NAME" --data-file=- --project="$PROJECT"
  echo "OK added secret version name=$SECRET_NAME"
fi

gcloud secrets add-iam-policy-binding "$SECRET_NAME" \
  --project="$PROJECT" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/secretmanager.secretAccessor" \
  --quiet >/dev/null

echo "OK production Redis wired instance=$REDIS_INSTANCE secret=$SECRET_NAME (host redacted)"
