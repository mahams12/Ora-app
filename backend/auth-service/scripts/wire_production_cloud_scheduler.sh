#!/usr/bin/env bash
# Production Cloud Scheduler → Cloud Run Jobs → production internal workers.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="${GCP_PROJECT_ID:-ora-app-d8112}"
REGION="${GCP_REGION:-us-central1}"
SERVICE="${PRODUCTION_CLOUD_RUN_SERVICE:-ora-auth-service}"
RUNTIME_SA="${CLOUD_RUN_RUNTIME_SA:-firebase-adminsdk-fbsvc@${PROJECT}.iam.gserviceaccount.com}"
# GCP SA account id max length 30 (ora-production-scheduler-invoker is too long).
SCHEDULER_SA="${PRODUCTION_SCHEDULER_INVOKER_SA:-ora-prod-sched-invoker@${PROJECT}.iam.gserviceaccount.com}"
WORKER_SECRET="${PRODUCTION_WORKER_SECRET_NAME:-ora-production-internal-worker-token}"
URL_FILE="${ROOT}/../../mobile/.production_api_url"

if [[ ! -f "$URL_FILE" ]]; then
  echo "ERROR: missing $URL_FILE — run deploy_production_cloud_run.sh first" >&2
  exit 2
fi

WORKER_API_BASE_URL="$(tr -d '[:space:]' <"$URL_FILE")"
if [[ "$WORKER_API_BASE_URL" != https://* ]]; then
  echo "ERROR: production API base must be HTTPS" >&2
  exit 2
fi

gcloud config set project "$PROJECT" >/dev/null
gcloud services enable cloudscheduler.googleapis.com run.googleapis.com --project="$PROJECT" >/dev/null 2>&1 || true

IMAGE="$(gcloud run services describe "$SERVICE" --project="$PROJECT" --region="$REGION" --format='value(spec.template.spec.containers[0].image)')"
if [[ -z "$IMAGE" ]]; then
  echo "ERROR: could not resolve image for $SERVICE" >&2
  exit 2
fi

if ! gcloud iam service-accounts describe "$SCHEDULER_SA" --project="$PROJECT" >/dev/null 2>&1; then
  gcloud iam service-accounts create ora-prod-sched-invoker \
    --project="$PROJECT" \
    --display-name="Ora production Cloud Scheduler job invoker"
  SCHEDULER_SA="ora-prod-sched-invoker@${PROJECT}.iam.gserviceaccount.com"
fi

gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:${SCHEDULER_SA}" \
  --role="roles/run.jobsExecutor" \
  --quiet >/dev/null 2>&1 || true

upsert_run_job() {
  local job_name="$1"
  local invoker_path="$2"
  local method="${3:-POST}"

  if gcloud run jobs describe "$job_name" --project="$PROJECT" --region="$REGION" >/dev/null 2>&1; then
    gcloud run jobs update "$job_name" \
      --project="$PROJECT" \
      --region="$REGION" \
      --image="$IMAGE" \
      --service-account="$RUNTIME_SA" \
      --set-secrets="ORA_INTERNAL_WORKER_TOKEN=${WORKER_SECRET}:latest" \
      --set-env-vars="WORKER_API_BASE_URL=${WORKER_API_BASE_URL},WORKER_INVOKER_PATH=${invoker_path},WORKER_INVOKER_METHOD=${method}" \
      --command=node \
      --args=scripts/staging_worker_http_invoke.mjs \
      --max-retries=0 \
      --task-timeout=300s \
      --quiet
  else
    gcloud run jobs create "$job_name" \
      --project="$PROJECT" \
      --region="$REGION" \
      --image="$IMAGE" \
      --service-account="$RUNTIME_SA" \
      --set-secrets="ORA_INTERNAL_WORKER_TOKEN=${WORKER_SECRET}:latest" \
      --set-env-vars="WORKER_API_BASE_URL=${WORKER_API_BASE_URL},WORKER_INVOKER_PATH=${invoker_path},WORKER_INVOKER_METHOD=${method}" \
      --command=node \
      --args=scripts/staging_worker_http_invoke.mjs \
      --max-retries=0 \
      --task-timeout=300s \
      --quiet
  fi
  echo "OK run_job name=$job_name path=$invoker_path"
}

upsert_scheduler_job() {
  local sched_name="$1"
  local run_job="$2"
  local cron="$3"
  local uri="https://${REGION}-run.googleapis.com/v2/projects/${PROJECT}/locations/${REGION}/jobs/${run_job}:run"

  if gcloud scheduler jobs describe "$sched_name" --project="$PROJECT" --location="$REGION" >/dev/null 2>&1; then
    gcloud scheduler jobs update http "$sched_name" \
      --project="$PROJECT" \
      --location="$REGION" \
      --schedule="$cron" \
      --uri="$uri" \
      --http-method=POST \
      --oauth-service-account-email="$SCHEDULER_SA" \
      --oauth-token-scope="https://www.googleapis.com/auth/cloud-platform" \
      --quiet
  else
    gcloud scheduler jobs create http "$sched_name" \
      --project="$PROJECT" \
      --location="$REGION" \
      --schedule="$cron" \
      --uri="$uri" \
      --http-method=POST \
      --oauth-service-account-email="$SCHEDULER_SA" \
      --oauth-token-scope="https://www.googleapis.com/auth/cloud-platform" \
      --quiet
  fi
  echo "OK scheduler name=$sched_name cron=$cron target_job=$run_job"
}

upsert_run_job ora-production-worker-expire-sweep /internal/rides/expire-sweep POST
upsert_run_job ora-production-worker-offer-expire-sweep /internal/rides/offer-expire-sweep POST
upsert_run_job ora-production-worker-dispatch-sweep /internal/rides/dispatch-sweep POST
upsert_run_job ora-production-worker-dispatch-fcm-sweep /internal/outbox/dispatch-fcm-sweep POST
upsert_run_job ora-production-worker-no-show-sweep /internal/rides/no-show-sweep POST
upsert_run_job ora-production-worker-expires-at-cleanup /internal/storage/expires-at-cleanup POST

upsert_scheduler_job ora-production-sched-expire-sweep ora-production-worker-expire-sweep '* * * * *'
upsert_scheduler_job ora-production-sched-offer-expire-sweep ora-production-worker-offer-expire-sweep '* * * * *'
upsert_scheduler_job ora-production-sched-dispatch-sweep ora-production-worker-dispatch-sweep '* * * * *'
upsert_scheduler_job ora-production-sched-dispatch-fcm-sweep ora-production-worker-dispatch-fcm-sweep '* * * * *'
upsert_scheduler_job ora-production-sched-no-show-sweep ora-production-worker-no-show-sweep '*/5 * * * *'
upsert_scheduler_job ora-production-sched-expires-at-cleanup ora-production-worker-expires-at-cleanup '*/15 * * * *'

echo "OK production Cloud Scheduler wired (6 jobs)"
