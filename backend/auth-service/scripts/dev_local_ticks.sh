#!/usr/bin/env bash
# Local replacement for Cloud Scheduler — drives the internal sweep endpoints
# that staging/production run via Cloud Run jobs. Pure localhost; no cloud calls.
#
# Fast loop (every ~1s): dispatch waves + FCM outbox projection.
# Slow loop (every ~5s): ride expiry, offer expiry, no-show sweep.
# Storage cleanup runs once at startup.
set -euo pipefail

PORT="${PORT:-8080}"
BASE="http://127.0.0.1:${PORT}/v1/internal"
TOKEN="${ORA_INTERNAL_WORKER_TOKEN:-local-dev-worker-token-xx}"
SLOW_EVERY=5

tick() {
  curl -fsS -m 10 -X POST "$1" -H "X-Ora-Worker-Token: ${TOKEN}" >/dev/null 2>&1 || true
}

echo "Local dispatch ticks → $BASE (worker token required by routes)"
tick "$BASE/storage/expires-at-cleanup"

i=0
while true; do
  tick "$BASE/rides/dispatch-sweep"
  tick "$BASE/outbox/dispatch-fcm-sweep"
  tick "$BASE/outbox/ride-state-fcm-sweep"
  if (( i % SLOW_EVERY == 0 )); then
    tick "$BASE/rides/expire-sweep"
    tick "$BASE/rides/offer-expire-sweep"
    tick "$BASE/rides/no-show-sweep"
    # RTDB GEO presence hygiene (no-op on the Firestore backend).
    tick "$BASE/geo/presence-sweep"
  fi
  i=$((i + 1))
  sleep 1
done
