#!/usr/bin/env bash
# Zero-cloud local auth-service — runs entirely against Firebase emulators.
# No service account, no Google Cloud calls, no billing. $0 incremental cost.
#
# Prereq: firebase emulators running from repo root:
#   firebase emulators:start --project ora-app-d8112
#   (firestore :8181, auth :9099, database :9000 — see firebase.json)
#
# Phone access (USB): ./scripts/dev_adb_reverse.sh, then in the app use
#   --dart-define=ORA_API_BASE_URL=http://127.0.0.1:8081/v1
#   --dart-define=ORA_ALLOW_HTTP_API=true
#   --dart-define=ORA_FIREBASE_EMULATOR_HOST=127.0.0.1
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export PORT="${PORT:-8080}"
export FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID:-ora-app-d8112}"
export FIRESTORE_EMULATOR_HOST="${FIRESTORE_EMULATOR_HOST:-127.0.0.1:8181}"
export FIREBASE_AUTH_EMULATOR_HOST="${FIREBASE_AUTH_EMULATOR_HOST:-127.0.0.1:9099}"
export FIREBASE_DATABASE_EMULATOR_HOST="${FIREBASE_DATABASE_EMULATOR_HOST:-127.0.0.1:9000}"
# Required so the RTDB adapter is constructed; the emulator host above is what
# actually receives traffic. Value is ignored when the emulator env is set.
export FIREBASE_DATABASE_URL="${FIREBASE_DATABASE_URL:-https://ora-app-d8112-default-rtdb.local-emulator.local}"
export REQUIRE_APP_CHECK="${REQUIRE_APP_CHECK:-false}"
export ORA_ENV="${ORA_ENV:-development}"
export ORA_INTERNAL_WORKER_TOKEN="${ORA_INTERNAL_WORKER_TOKEN:-local-dev-worker-token-xx}"
export ORA_REQUIRE_FIREBASE_EMULATOR="${ORA_REQUIRE_FIREBASE_EMULATOR:-true}"
# Hard guarantee: never attempt a real FCM send in emulator mode.
export ORA_FCM_SENDER="none"
# Zero-cost pricing: straight-line routing, no Google Routes calls.
export ORA_ROUTING_PROVIDER="haversine"
# Local default: RTDB geohash GEO (verified against Firestore parity 2026-10;
# rollback locally with GEO_BACKEND=firestore). Production stays firestore
# unless GEO_BACKEND is explicitly set there.
export GEO_BACKEND="${GEO_BACKEND:-rtdb}"
# Never source .env here: it may contain keys for paid Google services
# (GOOGLE_MAPS_SERVER_KEY etc.). Paid routing stays disabled.
unset GOOGLE_MAPS_SERVER_KEY GOOGLE_APPLICATION_CREDENTIALS || true

echo "auth-service :$PORT — FIRESTORE $FIRESTORE_EMULATOR_HOST, AUTH $FIREBASE_AUTH_EMULATOR_HOST, RTDB $FIREBASE_DATABASE_EMULATOR_HOST (fcm=none, maps=off)"
exec ./node_modules/.bin/tsx src/index.ts
