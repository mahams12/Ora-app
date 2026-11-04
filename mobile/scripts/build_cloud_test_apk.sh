#!/usr/bin/env bash
# Cloud test build — hosted Firebase (ora-app-d8112) + Cloud Run staging API.
# No emulator host => the app uses real Firebase Auth/Firestore/RTDB with the
# project's google-services.json. Works from any network, no Mac dependency.
#
# Usage:
#   ORA_CLOUD_API_URL=https://ora-auth-service-staging-...run.app/v1 \
#     bash mobile/scripts/build_cloud_test_apk.sh
set -euo pipefail

MOBILE="$(cd "$(dirname "$0")/.." && pwd)"
LOCAL_PROPS="$MOBILE/android/local.properties"

prop() {
  [[ -f "$LOCAL_PROPS" ]] || return 0
  awk -F= -v k="$1" '$0 ~ "^"k"=" {print substr($0, index($0,"=")+1); exit}' "$LOCAL_PROPS"
}

API_URL="${ORA_CLOUD_API_URL:-}"
if [[ -z "$API_URL" && -f "$MOBILE/.staging_api_url" ]]; then
  API_URL="$(cat "$MOBILE/.staging_api_url")"
fi
if [[ -z "$API_URL" ]]; then
  echo "ERROR: set ORA_CLOUD_API_URL (e.g. https://ora-auth-service-staging-....run.app/v1)" >&2
  exit 2
fi

MAPTILER="${MAPLIBRE_TILE_KEY:-}"
[[ -z "$MAPTILER" ]] && MAPTILER="$(prop MAPLIBRE_TILE_KEY)"
[[ -z "$MAPTILER" ]] && MAPTILER="$(prop ORA_MAPTILER_API_KEY)"

cd "$MOBILE"
flutter build apk --debug \
  --dart-define=ORA_ENV=staging \
  --dart-define=ORA_APP_CHECK=false \
  --dart-define=ORA_API_BASE_URL="$API_URL" \
  --dart-define=MAPLIBRE_TILE_KEY="$MAPTILER" \
  ${ORA_GOOGLE_PLACES_API_KEY:+--dart-define=ORA_GOOGLE_PLACES_API_KEY="$ORA_GOOGLE_PLACES_API_KEY"}

cp build/app/outputs/flutter-apk/app-debug.apk \
   build/app/outputs/flutter-apk/ora-test-cloud.apk
echo "APK=$MOBILE/build/app/outputs/flutter-apk/ora-test-cloud.apk"
echo "API=$API_URL (real Firebase, no emulator)"
