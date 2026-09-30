#!/usr/bin/env bash
# Run N3 bench seed/cleanup inside VPC (Memorystore is private; local laptop cannot reach it).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="${GCP_PROJECT_ID:-ora-app-d8112}"
REGION="${GCP_REGION:-us-central1}"
JOB="${N3_SEED_JOB:-ora-n3-staging-seed}"
VPC_CONNECTOR="${VPC_CONNECTOR:-ora-staging-vpc}"
SECRET_NAME="${REDIS_SECRET_NAME:-ora-staging-redis-url}"
SA_EMAIL="${CLOUD_RUN_RUNTIME_SA:-firebase-adminsdk-fbsvc@${PROJECT}.iam.gserviceaccount.com}"
MODE="${1:-seed}"
COUNT="${2:-100}"
export BENCH_PREFIX="${BENCH_PREFIX:-n3bench_$(date -u +%Y%m%dT%H%M%SZ)}"

if [[ ! -f .env ]]; then
  echo "ERROR: missing .env for FIREBASE_PROJECT_ID" >&2
  exit 2
fi
# shellcheck disable=SC1091
set -a && source .env && set +a
: "${FIREBASE_PROJECT_ID:?}"

IMAGE="$(gcloud run services describe ora-auth-service-staging --project="$PROJECT" --region="$REGION" --format='value(spec.template.spec.containers[0].image)')"

if ! gcloud run jobs describe "$JOB" --project="$PROJECT" --region="$REGION" >/dev/null 2>&1; then
  gcloud run jobs create "$JOB" \
    --project="$PROJECT" \
    --region="$REGION" \
    --image="$IMAGE" \
    --service-account="$SA_EMAIL" \
    --vpc-connector="$VPC_CONNECTOR" \
    --vpc-egress=private-ranges-only \
    --set-secrets="REDIS_URL=${SECRET_NAME}:latest" \
    --set-env-vars="FIREBASE_PROJECT_ID=${FIREBASE_PROJECT_ID},NODE_ENV=staging,ORA_ENV=staging,BENCH_PREFIX=${BENCH_PREFIX}" \
    --memory=512Mi \
    --cpu=1 \
    --max-retries=0 \
    --task-timeout=600 \
    --command=node \
    --args="scripts/seed_n3_staging_benchmark.bundle.cjs,${MODE},${COUNT}"
else
  gcloud run jobs update "$JOB" \
    --project="$PROJECT" \
    --region="$REGION" \
    --image="$IMAGE" \
    --set-env-vars="FIREBASE_PROJECT_ID=${FIREBASE_PROJECT_ID},NODE_ENV=staging,ORA_ENV=staging,BENCH_PREFIX=${BENCH_PREFIX}" \
    --command=node \
    --args="scripts/seed_n3_staging_benchmark.bundle.cjs,${MODE},${COUNT}" \
    --quiet
fi

EXEC="$(gcloud run jobs execute "$JOB" --project="$PROJECT" --region="$REGION" --format='value(name)' --wait)"
echo "OK seed job execution=$EXEC prefix=$BENCH_PREFIX mode=$MODE"
