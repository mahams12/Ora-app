#!/usr/bin/env bash
# Upsert staging server secrets in Secret Manager (Maps + worker token). No values printed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="${GCP_PROJECT_ID:-ora-app-d8112}"
SA_EMAIL="${CLOUD_RUN_RUNTIME_SA:-firebase-adminsdk-fbsvc@${PROJECT}.iam.gserviceaccount.com}"
MAPS_SECRET_NAME="${MAPS_SECRET_NAME:-ora-staging-google-maps-server-key}"
WORKER_SECRET_NAME="${WORKER_SECRET_NAME:-ora-staging-internal-worker-token}"

if [[ ! -f .env ]]; then
  echo "ERROR: missing $ROOT/.env" >&2
  exit 2
fi

# shellcheck disable=SC1091
set -a
source .env
set +a

: "${GOOGLE_MAPS_SERVER_KEY:?GOOGLE_MAPS_SERVER_KEY required in .env}"
: "${ORA_INTERNAL_WORKER_TOKEN:?ORA_INTERNAL_WORKER_TOKEN required in .env}"

if [[ ${#ORA_INTERNAL_WORKER_TOKEN} -lt 16 ]]; then
  echo "ERROR: ORA_INTERNAL_WORKER_TOKEN must be at least 16 characters" >&2
  exit 2
fi

gcloud config set project "$PROJECT" >/dev/null
gcloud services enable secretmanager.googleapis.com --project="$PROJECT" >/dev/null 2>&1 || true

upsert_secret() {
  local name="$1"
  local value="$2"
  if ! gcloud secrets describe "$name" --project="$PROJECT" >/dev/null 2>&1; then
    printf '%s' "$value" | gcloud secrets create "$name" --data-file=- --project="$PROJECT"
    echo "OK created secret name=$name"
  else
    printf '%s' "$value" | gcloud secrets versions add "$name" --data-file=- --project="$PROJECT"
    echo "OK added secret version name=$name"
  fi
  gcloud secrets add-iam-policy-binding "$name" \
    --project="$PROJECT" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/secretmanager.secretAccessor" \
    --quiet >/dev/null
}

upsert_secret "$MAPS_SECRET_NAME" "$GOOGLE_MAPS_SERVER_KEY"
upsert_secret "$WORKER_SECRET_NAME" "$ORA_INTERNAL_WORKER_TOKEN"

gcloud secrets versions list "$MAPS_SECRET_NAME" --project="$PROJECT" --limit=1 --format='value(name)' >/dev/null
gcloud secrets versions list "$WORKER_SECRET_NAME" --project="$PROJECT" --limit=1 --format='value(name)' >/dev/null

echo "OK server secrets wired (names only): $MAPS_SECRET_NAME $WORKER_SECRET_NAME"
