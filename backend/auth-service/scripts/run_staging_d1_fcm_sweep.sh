#!/usr/bin/env bash
# Trigger N4 dispatch + D1 FCM sweeps on staging (worker token required).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ -f .env ]]; then set -a; source .env; set +a; fi
: "${ORA_INTERNAL_WORKER_TOKEN:?}"
BASE="${STAGING_API_BASE_URL:-}"
if [[ -z "$BASE" && -f ../../mobile/.staging_api_url ]]; then
  BASE="$(cat ../../mobile/.staging_api_url)"
fi
: "${BASE:?STAGING_API_BASE_URL or mobile/.staging_api_url}"
HDR=( -H "X-Ora-Worker-Token: ${ORA_INTERNAL_WORKER_TOKEN}" )
echo "== N4 dispatch-sweep =="
curl -sS -X POST "${BASE%/}/internal/rides/dispatch-sweep" "${HDR[@]}"
echo ""
echo "== D1 dispatch-fcm-sweep =="
curl -sS -X POST "${BASE%/}/internal/outbox/dispatch-fcm-sweep" "${HDR[@]}"
echo ""
echo "OK — check Cloud Logging for D1_DISPATCH_FCM"
