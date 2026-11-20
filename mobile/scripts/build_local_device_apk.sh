#!/usr/bin/env bash
# Local-emulator device build — zero cloud cost, consistent defines.
#
# Builds the debug APK that talks to the emulator backend over adb reverse
# (USB) or the Mac's LAN IP for Firebase emulators. Mirrors the define set
# from build_staging_apk.sh so every local build is identical — this is the
# fix for intermittent "Map preview unavailable · tile key not configured"
# seen when ad-hoc `flutter build apk` omitted MAPLIBRE_TILE_KEY.
#
# Prereqs:
#   1. Emulators running from repo root (firebase emulators:start)
#   2. backend/auth-service/scripts/dev_emulator_backend.sh running (:8080)
#   3. backend/auth-service/scripts/dev_adb_reverse.sh run while USB attached
#
# Env overrides:
#   ORA_API_DEVICE_URL     — what the PHONE dials (default: auto Wi-Fi
#                            http://<lan-ip>:8080/v1; set ORA_DEVICE_NET=usb
#                            for the old adb-reverse http://127.0.0.1:8081/v1)
#   ORA_DEVICE_NET         — wifi (default) | usb
#   ORA_API_HOST_PORT      — Mac-side backend port in wifi mode (default 8080)
#   ORA_EMULATOR_LAN_HOST  — Mac LAN IP for Auth/RTDB emulators (default: auto-detect en0)
#   MAPLIBRE_TILE_KEY      — else read from android/local.properties (gitignored)
set -euo pipefail

MOBILE="$(cd "$(dirname "$0")/.." && pwd)"
LOCAL_PROPS="$MOBILE/android/local.properties"

prop() {
  # prop <key> — read a value from android/local.properties if present.
  [[ -f "$LOCAL_PROPS" ]] || return 0
  awk -F= -v k="$1" '$0 ~ "^"k"=" {print substr($0, index($0,"=")+1); exit}' "$LOCAL_PROPS"
}

# Firebase emulators need the Mac's LAN IP on a physical device — the
# FlutterFire SDKs remap 127.0.0.1→10.0.2.2 which only works in an emulator.
EMU_HOST="${ORA_EMULATOR_LAN_HOST:-}"
if [[ -z "$EMU_HOST" ]]; then
  EMU_HOST="$(ipconfig getifaddr en0 2>/dev/null || true)"
fi
if [[ -z "$EMU_HOST" ]]; then
  echo "ERROR: could not detect LAN IP — set ORA_EMULATOR_LAN_HOST" >&2
  exit 2
fi

NET_MODE="${ORA_DEVICE_NET:-wifi}"
if [[ -n "${ORA_API_DEVICE_URL:-}" ]]; then
  API_URL="$ORA_API_DEVICE_URL"
elif [[ "$NET_MODE" == "usb" ]]; then
  API_URL="http://127.0.0.1:${ORA_API_DEVICE_PORT:-8081}/v1"
else
  API_URL="http://${EMU_HOST}:${ORA_API_HOST_PORT:-8080}/v1"
fi

MAPTILER="${MAPLIBRE_TILE_KEY:-}"
[[ -z "$MAPTILER" ]] && MAPTILER="$(prop MAPLIBRE_TILE_KEY)"
[[ -z "$MAPTILER" ]] && MAPTILER="$(prop ORA_MAPTILER_API_KEY)"
if [[ -n "$MAPTILER" ]]; then
  echo "MapTiler key: present (value not logged)"
else
  # $0 path: MapPreviewStyleLoader falls back to OpenFreeMap when no key.
  echo "MapTiler key: absent → OpenFreeMap tiles (\$0, no key needed)"
fi

cd "$MOBILE"
flutter build apk --debug \
  --dart-define=ORA_ENV=development \
  --dart-define=ORA_APP_CHECK=false \
  --dart-define=ORA_API_BASE_URL="$API_URL" \
  --dart-define=ORA_ALLOW_HTTP_API=true \
  --dart-define=ORA_FIREBASE_EMULATOR_HOST="$EMU_HOST" \
  --dart-define=MAPLIBRE_TILE_KEY="$MAPTILER" \
  --dart-define=ORA_DEMO_LISTINGS="${ORA_DEMO_LISTINGS:-true}" \
  --dart-define=ORA_ADAPTIVE_PRESENCE="${ORA_ADAPTIVE_PRESENCE:-true}" \
  ${ORA_GOOGLE_PLACES_API_KEY:+--dart-define=ORA_GOOGLE_PLACES_API_KEY="$ORA_GOOGLE_PLACES_API_KEY"}

echo "APK=$MOBILE/build/app/outputs/flutter-apk/app-debug.apk"
echo "API=$API_URL (net=$NET_MODE)  EMU_HOST=$EMU_HOST  MAPTILER=$([[ -n $MAPTILER ]] && echo set || echo MISSING/OpenFreeMap)"
