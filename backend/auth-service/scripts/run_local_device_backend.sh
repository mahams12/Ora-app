#!/usr/bin/env bash
# Durable local auth-service for physical Android testing.
# Keeps the process in the foreground so it does not die with a short-lived shell.
#
# Runs entirely against Firebase emulators — the startup guard
# (assertFirebaseTargetConfig) refuses to boot without them, so this script
# can never silently fall back to production Firebase, real FCM, or paid
# Google Routes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export PORT="${PORT:-8080}"
export ORA_ENV="${ORA_ENV:-development}"
export FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID:-ora-app-d8112}"
export FIRESTORE_EMULATOR_HOST="${FIRESTORE_EMULATOR_HOST:-127.0.0.1:8181}"
export FIREBASE_AUTH_EMULATOR_HOST="${FIREBASE_AUTH_EMULATOR_HOST:-127.0.0.1:9099}"
export FIREBASE_DATABASE_EMULATOR_HOST="${FIREBASE_DATABASE_EMULATOR_HOST:-127.0.0.1:9000}"
# Required so the RTDB adapter is constructed; the emulator host above is what
# actually receives traffic. Value is ignored when the emulator env is set.
export FIREBASE_DATABASE_URL="${FIREBASE_DATABASE_URL:-https://ora-app-d8112-default-rtdb.local-emulator.local}"
export REQUIRE_APP_CHECK="${REQUIRE_APP_CHECK:-false}"
export ORA_INTERNAL_WORKER_TOKEN="${ORA_INTERNAL_WORKER_TOKEN:-local-dev-worker-token-xx}"
export ORA_REQUIRE_FIREBASE_EMULATOR="${ORA_REQUIRE_FIREBASE_EMULATOR:-true}"
# Hard guarantee: never attempt a real FCM send in emulator mode.
export ORA_FCM_SENDER="none"
# Zero-cost pricing: straight-line routing, no Google Routes calls.
export ORA_ROUTING_PROVIDER="haversine"
# Local default: RTDB geohash GEO (rollback: GEO_BACKEND=firestore).
export GEO_BACKEND="${GEO_BACKEND:-rtdb}"
# Emulator mode needs no cloud credentials or paid API keys — strip any that
# leaked into the shell so nothing can reach a real Google service.
unset GOOGLE_MAPS_SERVER_KEY GOOGLE_APPLICATION_CREDENTIALS || true

echo "Starting auth-service on :$PORT (project=$FIREBASE_PROJECT_ID, emulators)"
echo "After start, on the Mac run: adb reverse tcp:$PORT tcp:$PORT"
echo "Flutter debug build must use: --dart-define=ORA_API_BASE_URL=http://127.0.0.1:$PORT/v1 --dart-define=ORA_ALLOW_HTTP_API=true"
exec ./node_modules/.bin/tsx src/index.ts
