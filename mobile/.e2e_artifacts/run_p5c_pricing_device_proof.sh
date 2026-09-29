#!/usr/bin/env bash
# Phase 5C pricing physical-device proof (ops only).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ART="$ROOT/mobile/.e2e_artifacts"
BACKEND="$ROOT/backend/auth-service"
PKG=com.ora.ora
DEVICE="${ANDROID_SERIAL:-RF8R40ZQ1JH}"
UI="$ART/p5c_proof_ui.xml"
LOG="$ART/p5c_backend_8081.log"
MARKER="=== P5C_PRICING_PROOF $(date -Iseconds) ==="

if [[ -z "${ORA_GOOGLE_PLACES_API_KEY:-}" ]]; then
  echo "ERROR: export ORA_GOOGLE_PLACES_API_KEY before running." >&2
  exit 2
fi

dump_ui() {
  adb -s "$DEVICE" shell uiautomator dump /sdcard/p5c_ui.xml >/dev/null 2>&1 || true
  adb -s "$DEVICE" pull /sdcard/p5c_ui.xml "$UI" >/dev/null 2>&1 || true
}

tap_desc() {
  local needle="$1"
  python3 - "$needle" "$UI" <<'PY'
import re, sys
needle, path = sys.argv[1], sys.argv[2]
try:
  t = open(path).read()
except OSError:
  sys.exit(1)
for m in re.finditer(
    r'content-desc="([^"]*)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', t
):
  desc = m.group(1).replace("&#10;", " ")
  if needle.lower() in desc.lower():
    x1, y1, x2, y2 = map(int, m.groups()[1:])
    print((x1 + x2) // 2, (y1 + y2) // 2)
    sys.exit(0)
sys.exit(2)
PY
}

tap_if_desc() {
  local needle="$1"
  if coords=$(tap_desc "$needle" 2>/dev/null); then
    read -r x y <<<"$coords"
    adb -s "$DEVICE" shell input tap "$x" "$y"
    return 0
  fi
  return 1
}

wait_desc() {
  local needle="$1" tries="${2:-30}"
  local i=0
  while [[ $i -lt $tries ]]; do
    dump_ui
    if grep -q "$needle" "$UI" 2>/dev/null; then
      return 0
    fi
    sleep 2
    i=$((i + 1))
  done
  return 1
}

echo "== device =="
adb devices -l
adb -s "$DEVICE" get-state

echo "== backend :8080 =="
for pid in $(lsof -t -iTCP:8080 -sTCP:LISTEN 2>/dev/null || true); do
  kill "$pid" 2>/dev/null || true
done
for pid in $(lsof -t -iTCP:8081 -sTCP:LISTEN 2>/dev/null || true); do
  kill "$pid" 2>/dev/null || true
done
sleep 2
cd "$BACKEND"
set -a && source .env && set +a
export GOOGLE_APPLICATION_CREDENTIALS="$BACKEND/secrets/service-account.json"
export REQUIRE_APP_CHECK=false
export ORA_INTERNAL_WORKER_TOKEN="${ORA_INTERNAL_WORKER_TOKEN:-local-dev-worker-token-xx}"
echo "$MARKER" >>"$LOG"
nohup ./node_modules/.bin/tsx src/index.ts >>"$LOG" 2>&1 &
echo $! >"$ART/p5c_backend_8080.pid"
sleep 5
curl -fsS http://127.0.0.1:8080/healthz
echo
rg -q "pricing_estimate_begin" "$BACKEND/src/pricing/routes.ts"
echo "pricing_routes_source=ok"

echo "== adb reverse 8081 -> 8080 =="
adb -s "$DEVICE" reverse --remove-all 2>/dev/null || true
adb -s "$DEVICE" reverse tcp:8081 tcp:8080
adb -s "$DEVICE" reverse --list

echo "== flutter build + install =="
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
adb -s "$DEVICE" shell cmd location providers add-test-provider gps --supportsAltitude --supportsSpeed --supportsBearing 2>/dev/null || true
adb -s "$DEVICE" shell cmd location providers set-test-provider-enabled gps true
adb -s "$DEVICE" shell cmd location providers set-test-provider-location gps --location 31.5204,74.3587 --accuracy 5

echo "== launch + logcat =="
adb -s "$DEVICE" logcat -c
adb -s "$DEVICE" shell am force-stop "$PKG"
adb -s "$DEVICE" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 5

# Auth / splash recovery
for _ in 1 2 3 4 5; do
  dump_ui
  if grep -q "Signing you in" "$UI" 2>/dev/null; then
    tap_if_desc "Try again" || true
    sleep 6
  elif grep -q "Phone number" "$UI" 2>/dev/null || grep -q "Enter your phone" "$UI" 2>/dev/null; then
    adb -s "$DEVICE" shell input tap 540 1364
    adb -s "$DEVICE" shell input text '+923012345678'
    adb -s "$DEVICE" shell input keyevent KEYCODE_BACK
    sleep 1
    tap_if_desc "Send code" || tap_if_desc "Send Code" || adb -s "$DEVICE" shell input tap 540 1640
    sleep 8
    adb -s "$DEVICE" shell input tap 540 610
    adb -s "$DEVICE" shell input text '123456'
    tap_if_desc "Verify" || adb -s "$DEVICE" shell input tap 540 810
    sleep 12
  elif grep -q "Request a ride" "$UI" 2>/dev/null || grep -q "Home" "$UI" 2>/dev/null; then
    break
  else
    sleep 3
  fi
done

wait_desc "Request a ride" 20 || wait_desc "Request ride" 10 || true
tap_if_desc "Request a ride" || tap_if_desc "Request ride" || true
sleep 4

dump_ui
tap_if_desc "Use current location" || true
sleep 2
tap_if_desc "Confirm pickup" || true
sleep 2

# Destination via Places
dump_ui
adb -s "$DEVICE" shell input tap 569 1760
sleep 1
adb -s "$DEVICE" shell input keyevent KEYCODE_CTRL_A 2>/dev/null || true
adb -s "$DEVICE" shell input text 'Liberty%20Market%20Lahore'
sleep 4
dump_ui
tap_if_desc "Gulberg" || tap_if_desc "Liberty Market" || true
sleep 3
tap_if_desc "Confirm destination" || true
sleep 2
tap_if_desc "Continue" || true
sleep 3

tap_if_desc "Trio" || true
sleep 2
tap_if_desc "Continue" || true
sleep 4

wait_desc "Review" 15 || wait_desc "Retry pricing" 15 || true
sleep 3
tap_if_desc "Retry pricing" || true
sleep 10

dump_ui
adb -s "$DEVICE" exec-out screencap -p >"$ART/p5c_proof_after_pricing.png"

adb -s "$DEVICE" logcat -d >"$ART/p5c_proof_logcat.txt" 2>/dev/null || true

echo "== proof artifacts =="
echo "ui=$UI screenshot=$ART/p5c_proof_after_pricing.png logcat=$ART/p5c_proof_logcat.txt backend_log=$LOG"
