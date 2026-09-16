#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."
export PORT="${PORT:-8080}"
export FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID:-ora-app-d8112}"
export GOOGLE_APPLICATION_CREDENTIALS="${GOOGLE_APPLICATION_CREDENTIALS:-${PWD}/secrets/service-account.json}"
export REQUIRE_APP_CHECK="${REQUIRE_APP_CHECK:-false}"
export ORA_ENV="${ORA_ENV:-development}"
export NODE_OPTIONS="${NODE_OPTIONS:-}"
echo "starting $(date) project=${FIREBASE_PROJECT_ID} appCheck=${REQUIRE_APP_CHECK}" >> /tmp/ora_auth.log
exec ./node_modules/.bin/tsx src/index.ts >> /tmp/ora_auth.log 2>&1
