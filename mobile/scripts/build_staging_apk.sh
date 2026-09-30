#!/usr/bin/env bash
# Shareable staging APK — HTTPS remote API, no adb reverse.
set -euo pipefail

MOBILE="$(cd "$(dirname "$0")/.." && pwd)"
URL_FILE="$MOBILE/.staging_api_url"

if [[ -z "${ORA_API_BASE_URL:-}" ]]; then
  if [[ -f "$URL_FILE" ]]; then
    ORA_API_BASE_URL="$(tr -d '[:space:]' <"$URL_FILE")"
  else
    echo "ERROR: set ORA_API_BASE_URL or deploy backend first (writes $URL_FILE)" >&2
    exit 2
  fi
fi

if [[ "$ORA_API_BASE_URL" != https://* ]]; then
  echo "ERROR: staging APK requires HTTPS ORA_API_BASE_URL (got ${ORA_API_BASE_URL%%/*}://...)" >&2
  exit 2
fi

if [[ -z "${ORA_GOOGLE_PLACES_API_KEY:-}" ]]; then
  echo "ERROR: export ORA_GOOGLE_PLACES_API_KEY (client Places key only)" >&2
  exit 2
fi

cd "$MOBILE"
flutter build apk --debug \
  --dart-define=ORA_ENV=staging \
  --dart-define=ORA_APP_CHECK=false \
  --dart-define=ORA_API_BASE_URL="$ORA_API_BASE_URL" \
  --dart-define=ORA_GOOGLE_PLACES_API_KEY="$ORA_GOOGLE_PLACES_API_KEY"

echo "APK=$MOBILE/build/app/outputs/flutter-apk/app-debug.apk"
echo "ORA_API_BASE_URL=$ORA_API_BASE_URL"

# Prove URL embedded (no secrets)
strings "$MOBILE/build/app/outputs/flutter-apk/app-debug.apk" 2>/dev/null | rg -F "${ORA_API_BASE_URL%/}" | head -1 || true
