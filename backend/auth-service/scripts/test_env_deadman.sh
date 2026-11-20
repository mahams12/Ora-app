#!/usr/bin/env bash
# Dead-man teardown for the temp test window — fires ONCE at T+N minutes and
# deletes every billable test resource, even if the operator forgets.
#
# Mechanism (no continuously-billed infra):
#   Cloud Scheduler (one-shot cron, OAuth)  →  Cloud Run Job
#   The job runs the public google-cloud-cli image, executes the same
#   deletions as test_env_down.sh, then deletes its own scheduler job AND
#   itself. Total runtime ~1 min → effectively $0.
#
#   ./scripts/test_env_deadman.sh            # arm at T+90min (default)
#   DEADMAN_MINUTES=45 ./scripts/test_env_deadman.sh
#   ./scripts/test_env_deadman.sh --disarm   # remove job+schedule+SA
set -euo pipefail

PROJECT="${GCP_PROJECT_ID:-oraapp-a9be5}"
REGION="${GCP_REGION:-asia-south1}"
SERVICE="${SERVICE_NAME:-ora-auth-service}"
QUEUE="ora-dispatch"
SCHED_SWEEP="ora-worker-sweeps"
JOB="ora-test-deadman"
SCHED_DM="ora-test-deadman"
SA_NAME="ora-test-deadman"
SA_EMAIL="${SA_NAME}@${PROJECT}.iam.gserviceaccount.com"
MINUTES="${DEADMAN_MINUTES:-90}"

if [[ "${1:-}" == "--disarm" ]]; then
  gcloud scheduler jobs delete "$SCHED_DM" --location="$REGION" \
    --project="$PROJECT" --quiet 2>/dev/null || true
  gcloud run jobs delete "$JOB" --region="$REGION" \
    --project="$PROJECT" --quiet 2>/dev/null || true
  echo "deadman disarmed (SA kept — zero cost; delete in console if wanted)"
  exit 0
fi

# ── 1. Service account with JUST enough power to delete test resources ─
gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT" \
  >/dev/null 2>&1 || gcloud iam service-accounts create "$SA_NAME" \
  --project="$PROJECT" --display-name="Test env dead-man teardown"
for role in roles/run.admin roles/cloudtasks.admin roles/cloudscheduler.admin roles/secretmanager.admin; do
  gcloud projects add-iam-policy-binding "$PROJECT" \
    --member="serviceAccount:${SA_EMAIL}" --role="$role" \
    --condition=None >/dev/null
done

# ── 2. Teardown job — google-cloud-cli image, no build needed ───────────
CMD=$(cat <<EOS
set -e
gcloud scheduler jobs delete ${SCHED_SWEEP} --location=${REGION} --project=${PROJECT} --quiet || true
if gcloud tasks queues describe ${QUEUE} --location=${REGION} --project=${PROJECT} >/dev/null 2>&1; then
  gcloud tasks queues pause ${QUEUE} --location=${REGION} --project=${PROJECT} || true
  gcloud tasks queues purge ${QUEUE} --location=${REGION} --project=${PROJECT} || true
  gcloud tasks queues delete ${QUEUE} --location=${REGION} --project=${PROJECT} --quiet || true
fi
gcloud run services delete ${SERVICE} --region=${REGION} --project=${PROJECT} --quiet || true
gcloud secrets delete ora-test-worker-token --project=${PROJECT} --quiet || true
gcloud secrets delete ora-test-google-maps-key --project=${PROJECT} --quiet || true
gcloud scheduler jobs delete ${SCHED_DM} --location=${REGION} --project=${PROJECT} --quiet || true
gcloud run jobs delete ${JOB} --region=${REGION} --project=${PROJECT} --quiet || true
EOS
)

gcloud run jobs create "$JOB" --region="$REGION" --project="$PROJECT" \
  --image=gcr.io/google.com/cloudsdktool/google-cloud-cli:slim \
  --service-account="$SA_EMAIL" \
  --command="/bin/bash" --args="-c,$CMD" \
  --tasks=1 --task-timeout=10m --max-retries=1 2>/dev/null || \
gcloud run jobs update "$JOB" --region="$REGION" --project="$PROJECT" \
  --image=gcr.io/google.com/cloudsdktool/google-cloud-cli:slim \
  --service-account="$SA_EMAIL" \
  --command="/bin/bash" --args="-c,$CMD" \
  --tasks=1 --task-timeout=10m --max-retries=1

# ── 3. One-shot scheduler trigger at T+MINUTES ─────────────────────────
# Cron has no "once"; the job deletes this schedule entry when it fires,
# so it can never recur.
FIRE_AT="$(date -u -v+"${MINUTES}"M '+%M %H %d %m')"
SCHEDULE="$(echo "$FIRE_AT" | awk '{print $1" "$2" "$3" "$4" *"}')"
URI="https://${REGION}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${PROJECT}/jobs/${JOB}:run"

if gcloud scheduler jobs describe "$SCHED_DM" --location="$REGION" \
    --project="$PROJECT" >/dev/null 2>&1; then
  gcloud scheduler jobs update http "$SCHED_DM" \
    --project="$PROJECT" --location="$REGION" \
    --schedule="$SCHEDULE" --uri="$URI" --http-method=POST \
    --oauth-service-account-email="$SA_EMAIL"
else
  gcloud scheduler jobs create http "$SCHED_DM" \
    --project="$PROJECT" --location="$REGION" \
    --schedule="$SCHEDULE" --time-zone="UTC" \
    --uri="$URI" --http-method=POST \
    --oauth-service-account-email="$SA_EMAIL"
fi

echo "Dead-man armed: teardown fires at ~$(date -u -v+"${MINUTES}"M '+%H:%M UTC %Y-%m-%d') (${MINUTES} min)."
echo "Verify: gcloud scheduler jobs describe $SCHED_DM --location=$REGION --project=$PROJECT"
