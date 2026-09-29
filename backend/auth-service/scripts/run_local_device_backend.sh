#!/usr/bin/env bash
# Durable local auth-service for physical Android testing.
# Keeps the process in the foreground so it does not die with a short-lived shell.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SA="${GOOGLE_APPLICATION_CREDENTIALS:-./secrets/service-account.json}"
if [[ ! -f "$SA" ]]; then
  echo "Missing Firebase Admin credentials: $SA" >&2
  echo "Place the service-account JSON at backend/auth-service/secrets/service-account.json" >&2
  exit 1
fi

export PORT="${PORT:-8080}"
export FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID:-ora-app-d8112}"
export REQUIRE_APP_CHECK="${REQUIRE_APP_CHECK:-false}"
export ORA_INTERNAL_WORKER_TOKEN="${ORA_INTERNAL_WORKER_TOKEN:-local-dev-worker-token-xx}"
export REDIS_URL="${REDIS_URL:-redis://127.0.0.1:6379}"
export GOOGLE_APPLICATION_CREDENTIALS="$SA"

echo "Starting auth-service on :$PORT (project=$FIREBASE_PROJECT_ID)"
echo "After start, on the Mac run: adb reverse tcp:$PORT tcp:$PORT"
echo "Flutter debug build must use: --dart-define=ORA_API_BASE_URL=http://127.0.0.1:$PORT/v1 --dart-define=ORA_ALLOW_HTTP_API=true"
exec ./node_modules/.bin/tsx src/index.ts
