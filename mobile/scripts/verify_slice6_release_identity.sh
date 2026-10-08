#!/usr/bin/env bash
# Slice 6 verification only — release signing, SHA-256, static audit (no Slice 7 E2E).
set -euo pipefail

MOBILE="$(cd "$(dirname "$0")/.." && pwd)"
ART="$MOBILE/.e2e_artifacts"
REPORT="$ART/slice6_verification_run.json"
KEY_PROPS="${ORA_ANDROID_KEY_PROPERTIES_FILE:-$MOBILE/android/key.properties}"
APP_ID='1:498169438285:android:3b100b1c7a7248f1ddbc04'
PROJECT=ora-app-d8112

if [[ ! -f "$KEY_PROPS" ]]; then
  python3 - <<PY
import json
print(json.dumps({"verdict":"BLOCKED","reason":"missing_key_properties","path":"$KEY_PROPS"}, indent=2))
PY
  >"$REPORT"
  echo "BLOCKED: missing $KEY_PROPS" >&2
  exit 2
fi

export ORA_ANDROID_KEY_PROPERTIES_FILE="$KEY_PROPS"
bash "$MOBILE/scripts/build_production_release.sh" both

APK="$MOBILE/build/app/outputs/flutter-apk/app-release.apk"
APKSIGNER=$(ls -d "$HOME/Library/Android/sdk/build-tools/"*/apksigner 2>/dev/null | sort -V | tail -1)
SHA256=""
if [[ -n "${APKSIGNER:-}" && -f "$APK" ]]; then
  SHA256="$("$APKSIGNER" verify --print-certs "$APK" 2>/dev/null | awk '/Signer #1 certificate SHA-256:/ {print $NF}' | tr -d ':')"
fi

FIREBASE_SHA_OK=false
if [[ -n "$SHA256" ]]; then
  AT=$(gcloud auth print-access-token)
  EXISTING=$(curl -sS -H "Authorization: Bearer $AT" -H "x-goog-user-project: $PROJECT" \
    "https://firebase.googleapis.com/v1beta1/projects/$PROJECT/androidApps/$APP_ID/sha")
  if printf '%s' "$EXISTING" | SHA="$SHA256" python3 -c "
import json, os, sys
d = json.load(sys.stdin)
h = os.environ['SHA'].lower()
sys.exit(0 if any(c.get('shaHash','').lower()==h for c in d.get('certificates',[])) else 1)
" 2>/dev/null; then
    FIREBASE_SHA_OK=true
  else
    HTTP=$(curl -sS -o /dev/null -w '%{http_code}' -X POST \
      -H "Authorization: Bearer $AT" -H "x-goog-user-project: $PROJECT" -H "Content-Type: application/json" \
      "https://firebase.googleapis.com/v1beta1/projects/$PROJECT/androidApps/$APP_ID/sha" \
      -d "{\"shaHash\":\"${SHA256}\"}")
    [[ "$HTTP" == "200" || "$HTTP" == "409" ]] && FIREBASE_SHA_OK=true
  fi
fi

PROD_HOST="ora-auth-service-2zmxvrrs7a-uc.a.run.app"
STATIC_OK=true
strings "$APK" 2>/dev/null | rg -qF "$PROD_HOST" || STATIC_OK=false
strings "$APK" 2>/dev/null | rg -qF "127.0.0.1" && STATIC_OK=false

VERDICT=BLOCKED
if [[ -n "$SHA256" && "$FIREBASE_SHA_OK" == true && "$STATIC_OK" == true ]]; then
  VERDICT=GREEN
fi

python3 - <<PY >"$REPORT"
import json
print(json.dumps({
  "verdict": "$VERDICT",
  "release_sha256_prefix": "${SHA256[:16]}..." if "${SHA256}" else None,
  "firebase_release_sha_registered": $FIREBASE_SHA_OK,
  "static_audit_ok": $STATIC_OK,
  "apk_path": "mobile/build/app/outputs/flutter-apk/app-release.apk",
  "aab_path": "mobile/build/app/outputs/bundle/release/app-release.aab",
}, indent=2))
PY
cat "$REPORT"
[[ "$VERDICT" == GREEN ]]
