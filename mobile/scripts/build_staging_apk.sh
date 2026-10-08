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
  # Allow local.properties (gitignored) same pattern as Maps SDK key.
  LOCAL_PROPS="$MOBILE/android/local.properties"
  if [[ -f "$LOCAL_PROPS" ]]; then
    ORA_GOOGLE_PLACES_API_KEY="$(
      awk -F= '/^ORA_GOOGLE_PLACES_API_KEY=/{print substr($0, index($0,"=")+1); exit}' "$LOCAL_PROPS"
    )"
  fi
fi

if [[ -z "${ORA_GOOGLE_PLACES_API_KEY:-}" ]]; then
  echo "ERROR: export ORA_GOOGLE_PLACES_API_KEY (client Places key only) or set it in android/local.properties" >&2
  exit 2
fi

# Maps SDK Android key → local.properties (gitignored). Never embed in Dart.
if [[ -n "${ORA_GOOGLE_MAPS_ANDROID_API_KEY:-}" ]]; then
  LOCAL_PROPS="$MOBILE/android/local.properties"
  if [[ -f "$LOCAL_PROPS" ]]; then
    if grep -q '^ORA_GOOGLE_MAPS_ANDROID_API_KEY=' "$LOCAL_PROPS"; then
      # shellcheck disable=SC2016
      sed -i.bak 's|^ORA_GOOGLE_MAPS_ANDROID_API_KEY=.*|ORA_GOOGLE_MAPS_ANDROID_API_KEY='"$ORA_GOOGLE_MAPS_ANDROID_API_KEY"'|' "$LOCAL_PROPS"
      rm -f "$LOCAL_PROPS.bak"
    else
      printf '\nORA_GOOGLE_MAPS_ANDROID_API_KEY=%s\n' "$ORA_GOOGLE_MAPS_ANDROID_API_KEY" >>"$LOCAL_PROPS"
    fi
  else
    printf 'ORA_GOOGLE_MAPS_ANDROID_API_KEY=%s\n' "$ORA_GOOGLE_MAPS_ANDROID_API_KEY" >"$LOCAL_PROPS"
  fi
  echo "Maps SDK Android key: present in local.properties (value not logged)"
else
  echo "WARN: ORA_GOOGLE_MAPS_ANDROID_API_KEY unset — map tiles may fail until configured" >&2
fi

# Disposable MapLibre PoC — MapTiler key (optional; PoC fails closed if absent).
LOCAL_PROPS="$MOBILE/android/local.properties"
if [[ -z "${MAPLIBRE_TILE_KEY:-}" && -f "$LOCAL_PROPS" ]]; then
  MAPLIBRE_TILE_KEY="$(
    awk -F= '/^MAPLIBRE_TILE_KEY=/{print substr($0, index($0,"=")+1); exit}' "$LOCAL_PROPS"
  )"
fi
if [[ -z "${MAPLIBRE_TILE_KEY:-}" && -n "${ORA_MAPTILER_API_KEY:-}" ]]; then
  MAPLIBRE_TILE_KEY="$ORA_MAPTILER_API_KEY"
fi
if [[ -z "${MAPLIBRE_TILE_KEY:-}" && -f "$LOCAL_PROPS" ]]; then
  MAPLIBRE_TILE_KEY="$(
    awk -F= '/^ORA_MAPTILER_API_KEY=/{print substr($0, index($0,"=")+1); exit}' "$LOCAL_PROPS"
  )"
fi
if [[ -n "${MAPLIBRE_TILE_KEY:-}" ]]; then
  echo "MapLibre PoC MapTiler key: present (value not logged)"
else
  echo "WARN: MAPLIBRE_TILE_KEY unset — MapLibre PoC will fail closed until configured" >&2
fi

cd "$MOBILE"
flutter build apk --debug \
  --dart-define=ORA_ENV=staging \
  --dart-define=ORA_APP_CHECK=false \
  --dart-define=ORA_API_BASE_URL="$ORA_API_BASE_URL" \
  --dart-define=ORA_GOOGLE_PLACES_API_KEY="$ORA_GOOGLE_PLACES_API_KEY" \
  --dart-define=ORA_FIREBASE_DATABASE_URL="${ORA_FIREBASE_DATABASE_URL:-https://ora-app-d8112-default-rtdb.asia-southeast1.firebasedatabase.app}" \
  --dart-define=MAPLIBRE_TILE_KEY="${MAPLIBRE_TILE_KEY:-}"

echo "APK=$MOBILE/build/app/outputs/flutter-apk/app-debug.apk"
echo "ORA_API_BASE_URL=$ORA_API_BASE_URL"

# Prove URL embedded (no secrets)
strings "$MOBILE/build/app/outputs/flutter-apk/app-debug.apk" 2>/dev/null | rg -F "${ORA_API_BASE_URL%/}" | head -1 || true
