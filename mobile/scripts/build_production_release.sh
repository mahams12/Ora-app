#!/usr/bin/env bash
# Production release APK/AAB — HTTPS prod Cloud Run, App Check on, no adb reverse.
set -euo pipefail

MOBILE="$(cd "$(dirname "$0")/.." && pwd)"
URL_FILE="$MOBILE/.production_api_url"
ARTIFACT="${1:-apk}" # apk | appbundle | both

if [[ -z "${ORA_API_BASE_URL:-}" ]]; then
  if [[ -f "$URL_FILE" ]]; then
    ORA_API_BASE_URL="$(tr -d '[:space:]' <"$URL_FILE")"
  else
    echo "ERROR: set ORA_API_BASE_URL or run production Cloud Run deploy (writes $URL_FILE)" >&2
    exit 2
  fi
fi

if [[ "$ORA_API_BASE_URL" != https://* ]]; then
  echo "ERROR: production release requires HTTPS ORA_API_BASE_URL" >&2
  exit 2
fi

if [[ -z "${ORA_GOOGLE_PLACES_API_KEY:-}" ]]; then
  LP="$MOBILE/android/local.properties"
  if [[ -f "$LP" ]]; then
    ORA_GOOGLE_PLACES_API_KEY="$(grep '^ORA_GOOGLE_PLACES_API_KEY=' "$LP" | cut -d= -f2- | tr -d '[:space:]')"
  fi
fi
if [[ -z "${ORA_GOOGLE_PLACES_API_KEY:-}" ]]; then
  echo "ERROR: export ORA_GOOGLE_PLACES_API_KEY or set in android/local.properties (client Places key only)" >&2
  exit 2
fi

KEY_PROPS="${ORA_ANDROID_KEY_PROPERTIES_FILE:-$MOBILE/android/key.properties}"
export ORA_ANDROID_KEY_PROPERTIES_FILE="$KEY_PROPS"
if [[ ! -f "$KEY_PROPS" ]]; then
  echo "ERROR: missing release signing config at $KEY_PROPS (see android/key.properties.example)" >&2
  exit 2
fi
# storeFile must exist (path relative to android/ unless absolute)
STORE_REL="$(grep '^storeFile=' "$KEY_PROPS" | cut -d= -f2- | tr -d '[:space:]')"
if [[ -n "$STORE_REL" ]]; then
  if [[ "$STORE_REL" = /* ]]; then
    STORE_PATH="$STORE_REL"
  else
    STORE_PATH="$MOBILE/android/$STORE_REL"
  fi
  if [[ ! -f "$STORE_PATH" ]]; then
    echo "ERROR: keystore file not found at $STORE_PATH (from storeFile in key.properties)" >&2
    exit 2
  fi
fi

cd "$MOBILE"

COMMON=(
  --release
  --dart-define=ORA_ENV=production
  --dart-define=ORA_APP_CHECK=true
  --dart-define=ORA_API_BASE_URL="$ORA_API_BASE_URL"
  --dart-define=ORA_GOOGLE_PLACES_API_KEY="$ORA_GOOGLE_PLACES_API_KEY"
)

build_apk() {
  flutter build apk "${COMMON[@]}"
  echo "APK=$MOBILE/build/app/outputs/flutter-apk/app-release.apk"
}

build_aab() {
  flutter build appbundle "${COMMON[@]}"
  echo "AAB=$MOBILE/build/app/outputs/bundle/release/app-release.aab"
}

case "$ARTIFACT" in
  apk) build_apk ;;
  appbundle) build_aab ;;
  both) build_apk; build_aab ;;
  *) echo "Usage: $0 [apk|appbundle|both]" >&2; exit 2 ;;
esac

echo "ORA_ENV=production ORA_APP_CHECK=true"
echo "ORA_API_BASE_URL=$ORA_API_BASE_URL"
echo "version=$(grep '^version:' pubspec.yaml | awk '{print $2}')"

# Static sanity (no secrets)
APK_PATH="$MOBILE/build/app/outputs/flutter-apk/app-release.apk"
if [[ -f "$APK_PATH" ]]; then
  strings "$APK_PATH" 2>/dev/null | rg -F "${ORA_API_BASE_URL%/}" | head -1 && echo "OK prod URL present in APK" || echo "WARN prod URL string not found"
  strings "$APK_PATH" 2>/dev/null | rg -F "127.0.0.1" | head -1 && echo "WARN localhost found" || echo "OK no 127.0.0.1"
  strings "$APK_PATH" 2>/dev/null | rg -F "ora-auth-service-staging" | head -1 && echo "WARN staging URL found" || echo "OK no staging Cloud Run URL"
fi
