#!/usr/bin/env bash
# Wire Cloud Scheduler → Cloud Run Jobs → staging internal worker HTTP (token from Secret Manager).
# Does not print ORA_INTERNAL_WORKER_TOKEN or Maps keys.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="${GCP_PROJECT_ID:-ora-app-d8112}"
REGION="${GCP_REGION:-us-central1}"
SERVICE="${CLOUD_RUN_SERVICE:-ora-auth-service-staging}"
RUNTIME_SA="${CLOUD_RUN_RUNTIME_SA:-firebase-adminsdk-fbsvc@${PROJECT}.iam.gserviceaccount.com}"
SCHEDULER_SA="${SCHEDULER_INVOKER_SA:-ora-staging-scheduler-invoker@${PROJECT}.iam.gserviceaccount.com}"
WORKER_SECRET="${WORKER_SECRET_NAME:-ora-staging-internal-worker-token}"
URL_FILE="${ROOT}/../../mobile/.staging_api_url"

if [[ ! -f "$URL_FILE" ]]; then
  echo "ERROR: missing $URL_FILE — deploy staging service first" >&2
  exit 2
fi

STAGING_API_BASE_URL="$(tr -d '[:space:]' <"$URL_FILE")"
if [[ "$STAGING_API_BASE_URL" != https://* ]]; then
  echo "ERROR: STAGING_API_BASE_URL must be HTTPS" >&2
  exit 2
fi

gcloud config set project "$PROJECT" >/dev/null
gcloud services enable cloudscheduler.googleapis.com run.googleapis.com --project="$PROJECT" >/dev/null 2>&1 || true

IMAGE="$(gcloud run services describe "$SERVICE" --project="$PROJECT" --region="$REGION" --format='value(spec.template.spec.containers[0].image)')"
if [[ -z "$IMAGE" ]]; then
  echo "ERROR: could not resolve Cloud Run image for $SERVICE" >&2
  exit 2
fi

if ! gcloud iam service-accounts describe "$SCHEDULER_SA" --project="$PROJECT" >/dev/null 2>&1; then
  gcloud iam service-accounts create ora-staging-scheduler-invoker \
    --project="$PROJECT" \
    --display-name="Ora staging Cloud Scheduler job invoker"
  SCHEDULER_SA="ora-staging-scheduler-invoker@${PROJECT}.iam.gserviceaccount.com"
fi

# Project-level permission to execute Cloud Run jobs (Scheduler OAuth identity).
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
      --set-env-vars="STAGING_API_BASE_URL=${STAGING_API_BASE_URL},WORKER_INVOKER_PATH=${invoker_path},WORKER_INVOKER_METHOD=${method}" \
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
      --set-env-vars="STAGING_API_BASE_URL=${STAGING_API_BASE_URL},WORKER_INVOKER_PATH=${invoker_path},WORKER_INVOKER_METHOD=${method}" \
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

# Cloud Run Job per worker route (token in job secret env only — not in Scheduler config).
upsert_run_job ora-staging-worker-expire-sweep /internal/rides/expire-sweep POST
upsert_run_job ora-staging-worker-offer-expire-sweep /internal/rides/offer-expire-sweep POST
upsert_run_job ora-staging-worker-dispatch-sweep /internal/rides/dispatch-sweep POST
upsert_run_job ora-staging-worker-dispatch-fcm-sweep /internal/outbox/dispatch-fcm-sweep POST
upsert_run_job ora-staging-worker-no-show-sweep /internal/rides/no-show-sweep POST
upsert_run_job ora-staging-worker-expires-at-cleanup /internal/storage/expires-at-cleanup POST

# Scheduler → Run Jobs API (OAuth). Minimum interval 1 minute on standard cron.
upsert_scheduler_job ora-staging-sched-expire-sweep ora-staging-worker-expire-sweep '* * * * *'
upsert_scheduler_job ora-staging-sched-offer-expire-sweep ora-staging-worker-offer-expire-sweep '* * * * *'
upsert_scheduler_job ora-staging-sched-dispatch-sweep ora-staging-worker-dispatch-sweep '* * * * *'
upsert_scheduler_job ora-staging-sched-dispatch-fcm-sweep ora-staging-worker-dispatch-fcm-sweep '* * * * *'
upsert_scheduler_job ora-staging-sched-no-show-sweep ora-staging-worker-no-show-sweep '*/5 * * * *'
upsert_scheduler_job ora-staging-sched-expires-at-cleanup ora-staging-worker-expires-at-cleanup '*/15 * * * *'

echo "OK Cloud Scheduler wired for staging (6 jobs). Image=$IMAGE"
