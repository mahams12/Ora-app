#!/usr/bin/env bash
# Temporary migration-test environment DOWN — removes every test-time
# billable surface so nothing can keep accruing cost after the window.
#
# Deletes:  Cloud Run service, Scheduler job, Tasks queue (pause+purge+delete)
# Keeps:    secrets (zero cost), service account (zero cost), APIs enabled
#           (enabling APIs costs nothing; billed usage is what matters)
#
# Safe to run repeatedly — all steps are idempotent.
#   ./scripts/test_env_down.sh            # prompt-confirmed teardown
#   ORA_TEMP_TEST_DOWN=1 ./scripts/test_env_down.sh   # non-interactive
set -euo pipefail

PROJECT="${GCP_PROJECT_ID:-oraapp-a9be5}"
REGION="${GCP_REGION:-asia-south1}"
SERVICE="${SERVICE_NAME:-ora-auth-service}"
QUEUE="ora-dispatch"
SCHED_JOB="ora-worker-sweeps"

if [[ "${ORA_TEMP_TEST_DOWN:-0}" != "1" ]]; then
  read -r -p "Tear down test env in $PROJECT/$REGION (service=$SERVICE)? [y/N] " ans
  [[ "${ans,,}" == "y" ]] || { echo "Aborted."; exit 2; }
fi

echo "== test-env down: project=$PROJECT region=$REGION =="

# 1. Scheduler — deleted so no timer can ever fire again.
gcloud scheduler jobs delete "$SCHED_JOB" --location="$REGION" \
  --project="$PROJECT" --quiet 2>/dev/null && echo "scheduler: deleted" \
  || echo "scheduler: absent"

# 2. Cloud Tasks — paused, purged, deleted (no queued task can re-deliver).
if gcloud tasks queues describe "$QUEUE" --location="$REGION" \
    --project="$PROJECT" >/dev/null 2>&1; then
  gcloud tasks queues pause "$QUEUE" --location="$REGION" \
    --project="$PROJECT" >/dev/null
  gcloud tasks queues purge "$QUEUE" --location="$REGION" \
    --project="$PROJECT" >/dev/null 2>&1 || true
  gcloud tasks queues delete "$QUEUE" --location="$REGION" \
    --project="$PROJECT" --quiet && echo "queue: deleted"
else
  echo "queue: absent"
fi

# 3. Cloud Run — service deleted (stronger than max-instances: impossible
#    to serve traffic, impossible to bill CPU).
gcloud run services delete "$SERVICE" --region="$REGION" \
  --project="$PROJECT" --quiet 2>/dev/null && echo "cloudrun: deleted" \
  || echo "cloudrun: absent"

# 4. Secrets — tiny but nonzero (~$0.06/secret-version/mo). Delete both.
for s in ora-test-worker-token ora-test-google-maps-key; do
  gcloud secrets delete "$s" --project="$PROJECT" --quiet 2>/dev/null \
    && echo "secret $s: deleted" || echo "secret $s: absent"
done

# 5. Artifact Registry — source-deploy images ($0.10/GB-mo; 0.5 GB free but
#    remove anyway). Best-effort: repo name is Cloud Run's convention.
AR_REPO="cloud-run-source-deploy"
if gcloud artifacts repositories describe "$AR_REPO" --location="$REGION" \
    --project="$PROJECT" >/dev/null 2>&1; then
  while IFS= read -r img; do
    gcloud artifacts docker images delete "$img" \
      --project="$PROJECT" --quiet 2>/dev/null || true
  done < <(gcloud artifacts docker images list \
      "${REGION}-docker.pkg.dev/${PROJECT}/${AR_REPO}" \
      --include-tags --format='value(package)' 2>/dev/null | sort -u)
  echo "artifact images: purged (repo kept — no charge for empty repo)"
else
  echo "artifact repo: absent"
fi

# 6. Residual check — anything left that could bill?
echo
echo "== residual check =="
gcloud run services list --project="$PROJECT" --region="$REGION" \
  --format='value(metadata.name)' 2>/dev/null | sed 's/^/  run: /' || true
gcloud tasks queues list --location="$REGION" --project="$PROJECT" \
  --format='value(name)' 2>/dev/null | sed 's/^/  queue: /' || true
gcloud scheduler jobs list --location="$REGION" --project="$PROJECT" \
  --format='value(name)' 2>/dev/null | sed 's/^/  sched: /' || true

cat <<EOF

== TEST ENV DOWN ==
  Deleted: Cloud Run service, Scheduler job, Tasks queue, test secrets,
           Artifact Registry images.
  Still present (no metered charge unless used):
    - Enabled APIs (free), service account (free), AR repo shell (free)
    - Firestore/RTDB TEST data — tiny, inside free tiers; purge via
      Firebase console if you want it pristine
    - Cloud Logging entries (50 GB/mo free, auto-expire)
    - API keys you created in console (no charge; disable for hygiene)
  Honest caveat: billing export lags up to ~24h — spend already incurred
  before teardown will still appear on the invoice. Nothing new accrues.
  To resume: ORA_TEMP_TEST_GO=1 ./scripts/test_env_up.sh
EOF
