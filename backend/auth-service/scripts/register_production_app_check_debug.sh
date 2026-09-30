#!/usr/bin/env bash
# Register a Firebase App Check debug token (UUID) for com.ora.ora — local/CI smoke only.
# Never commit PRODUCTION_APP_CHECK_DEBUG_SECRET. Does not print the secret.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ENV_FILE="$ROOT/.env"
PROJECT="${GCP_PROJECT_ID:-ora-app-d8112}"
PN=498169438285
APP_ID='1:498169438285:android:3b100b1c7a7248f1ddbc04'

if [[ -f "$ENV_FILE" ]] && grep -q '^PRODUCTION_APP_CHECK_DEBUG_SECRET=' "$ENV_FILE" 2>/dev/null; then
  echo "OK PRODUCTION_APP_CHECK_DEBUG_SECRET already present in .env (not shown)"
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 required" >&2
  exit 2
fi

DEBUG_UUID="$(python3 -c 'import uuid; print(uuid.uuid4())')"
AT="$(gcloud auth print-access-token)"
QP="$PROJECT"

HTTP_CODE="$(curl -sS -o /tmp/appcheck_debug_create.json -w '%{http_code}' -X POST \
  -H "Authorization: Bearer ${AT}" \
  -H "x-goog-user-project: ${QP}" \
  -H "Content-Type: application/json" \
  "https://firebaseappcheck.googleapis.com/v1/projects/${PN}/apps/${APP_ID}/debugTokens" \
  -d "{\"displayName\":\"Ora production smoke (local)\",\"token\":\"${DEBUG_UUID}\"}")"

if [[ "$HTTP_CODE" != "200" && "$HTTP_CODE" != "409" ]]; then
  echo "ERROR: debug token create HTTP ${HTTP_CODE}" >&2
  exit 2
fi

if [[ ! -f "$ENV_FILE" ]]; then
  touch "$ENV_FILE"
fi
echo "PRODUCTION_APP_CHECK_DEBUG_SECRET=${DEBUG_UUID}" >>"$ENV_FILE"
echo "OK registered App Check debug token for Android app (secret appended to .env only)"
