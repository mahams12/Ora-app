#!/usr/bin/env bash
# launchd / long-lived dev entry — sources .env then runs auth-service (no watch).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SA="${GOOGLE_APPLICATION_CREDENTIALS:-./secrets/service-account.json}"
if [[ ! -f "$SA" ]]; then
  echo "Missing Firebase Admin credentials: $SA" >&2
  exit 1
fi

if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi

export PORT="${PORT:-8080}"
export FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID:-ora-app-d8112}"
export REQUIRE_APP_CHECK="${REQUIRE_APP_CHECK:-false}"
export ORA_INTERNAL_WORKER_TOKEN="${ORA_INTERNAL_WORKER_TOKEN:-local-dev-worker-token-xx}"
# Geo store is Firestore-native (geoDrivers) — no REDIS_URL needed.
export GOOGLE_APPLICATION_CREDENTIALS="$SA"

exec ./node_modules/.bin/tsx src/index.ts
