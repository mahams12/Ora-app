#!/usr/bin/env bash
# Wire Memorystore Redis to Cloud Run staging (infra only; no secret values printed).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="${GCP_PROJECT_ID:-ora-app-d8112}"
REGION="${GCP_REGION:-us-central1}"
SERVICE="${CLOUD_RUN_SERVICE:-ora-auth-service-staging}"
REDIS_INSTANCE="${REDIS_INSTANCE:-ora-staging-n3-redis}"
VPC_CONNECTOR="${VPC_CONNECTOR:-ora-staging-vpc}"
SECRET_NAME="${REDIS_SECRET_NAME:-ora-staging-redis-url}"
SA_EMAIL="${CLOUD_RUN_RUNTIME_SA:-firebase-adminsdk-fbsvc@${PROJECT}.iam.gserviceaccount.com}"

gcloud config set project "$PROJECT" >/dev/null

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
else
  printf '%s' "$REDIS_URL" | gcloud secrets versions add "$SECRET_NAME" --data-file=- --project="$PROJECT"
fi

gcloud secrets add-iam-policy-binding "$SECRET_NAME" \
  --project="$PROJECT" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/secretmanager.secretAccessor" \
  --quiet >/dev/null

gcloud run services update "$SERVICE" \
  --project="$PROJECT" \
  --region="$REGION" \
  --vpc-connector="$VPC_CONNECTOR" \
  --vpc-egress=private-ranges-only \
  --set-secrets="REDIS_URL=${SECRET_NAME}:latest" \
  --quiet

echo "OK wired Redis to Cloud Run service=$SERVICE connector=$VPC_CONNECTOR secret=$SECRET_NAME (host redacted)"
