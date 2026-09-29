#!/usr/bin/env bash
# Phase 5C physical-device proof driver (ops only — does not modify app source).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ART="$ROOT/mobile/.e2e_artifacts"
BACKEND="$ROOT/backend/auth-service"
PKG=com.ora.ora
DEVICE="${ANDROID_SERIAL:-RF8R40ZQ1JH}"
mkdir -p "$ART"

echo "== adb devices =="
adb devices -l
adb -s "$DEVICE" get-state

echo "== free/restart backend on 8081 with Maps key =="
# Prefer 8081 to avoid fighting an unkillable stale :8080 process from agent sandbox
cd "$BACKEND"
set -a && source .env && set +a
export GOOGLE_APPLICATION_CREDENTIALS="$BACKEND/secrets/service-account.json"
export PORT=8081
export REQUIRE_APP_CHECK=false
export ORA_INTERNAL_WORKER_TOKEN="${ORA_INTERNAL_WORKER_TOKEN:-local-dev-worker-token-xx}"
export NODE_PATH="$BACKEND/node_modules"

if ! curl -fsS -m 2 http://127.0.0.1:8081/healthz >/dev/null 2>&1; then
  echo "Starting auth-service from current src (tsx) on :8081 — keep this process running for device proof." >&2
  nohup env PORT=8081 \
    GOOGLE_APPLICATION_CREDENTIALS="$GOOGLE_APPLICATION_CREDENTIALS" \
    FIREBASE_PROJECT_ID="$FIREBASE_PROJECT_ID" \
    REQUIRE_APP_CHECK=false \
    GOOGLE_MAPS_SERVER_KEY="$GOOGLE_MAPS_SERVER_KEY" \
    ORA_INTERNAL_WORKER_TOKEN="$ORA_INTERNAL_WORKER_TOKEN" \
    ./node_modules/.bin/tsx src/index.ts >>"$ART/p5c_backend_8081.log" 2>&1 &
  echo $! >"$ART/p5c_backend_8081.pid"
  sleep 4
fi
curl -fsS http://127.0.0.1:8081/healthz
echo
CODE=$(curl -sS -o /tmp/p5c_est.json -w "%{http_code}" -X POST http://127.0.0.1:8081/v1/pricing/estimate \
  -H 'Content-Type: application/json' \
  -d '{"pickup":{"lat":31.52,"lng":74.35},"destination":{"lat":31.51,"lng":74.34},"category":"easy","city":"lahore"}')
echo "pricing_unauth_http=$CODE (expect 401)"

echo "== adb reverse =="
adb -s "$DEVICE" reverse --remove-all || true
adb -s "$DEVICE" reverse tcp:8081 tcp:8081
adb -s "$DEVICE" reverse tcp:8080 tcp:8081
adb -s "$DEVICE" reverse --list

if [[ -z "${ORA_GOOGLE_PLACES_API_KEY:-}" ]]; then
  echo "ERROR: export ORA_GOOGLE_PLACES_API_KEY before running (Places API New must allow Autocomplete)." >&2
  exit 2
fi

echo "== flutter build+install 5C =="
cd "$ROOT/mobile"
flutter build apk --debug \
  --dart-define=ORA_GOOGLE_PLACES_API_KEY="$ORA_GOOGLE_PLACES_API_KEY" \
  --dart-define=ORA_API_BASE_URL=http://127.0.0.1:8081/v1 \
  --dart-define=ORA_ALLOW_HTTP_API=true
adb -s "$DEVICE" install -r build/app/outputs/flutter-apk/app-debug.apk

echo "== location prep =="
adb -s "$DEVICE" shell pm grant "$PKG" android.permission.ACCESS_FINE_LOCATION
adb -s "$DEVICE" shell pm grant "$PKG" android.permission.ACCESS_COARSE_LOCATION
adb -s "$DEVICE" shell settings put secure location_mode 3
adb -s "$DEVICE" shell appops set "$PKG" android:mock_location allow
adb -s "$DEVICE" shell cmd location providers add-test-provider gps --supportsAltitude --supportsSpeed --supportsBearing || true
adb -s "$DEVICE" shell cmd location providers set-test-provider-enabled gps true
adb -s "$DEVICE" shell cmd location providers set-test-provider-location gps --location 31.5204,74.3587 --accuracy 5

echo "READY: launch app and continue interactive proof (or re-invoke agent)."
echo "Backend log: $ART/p5c_backend_8081.log"
