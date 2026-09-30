#!/usr/bin/env bash
# Production release device smoke — no adb reverse, no local backend.
set -euo pipefail
DEVICE="${ANDROID_SERIAL:-RF8R40ZQ1JH}"
PKG=com.ora.ora
ART="$(cd "$(dirname "$0")" && pwd)"
UI="$ART/prod_release_smoke_ui.xml"
LOG="$ART/prod_release_smoke_logcat.txt"
MARK="$(date -u +%Y%m%dT%H%M%SZ)"

adb -s "$DEVICE" reverse --remove-all
echo "adb_reverse=$(adb -s "$DEVICE" reverse --list || true)"

adb -s "$DEVICE" logcat -c
adb -s "$DEVICE" shell am force-stop "$PKG"
adb -s "$DEVICE" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null
sleep 4

dump() { adb -s "$DEVICE" shell uiautomator dump /sdcard/ora_ui.xml >/dev/null; adb -s "$DEVICE" pull /sdcard/ora_ui.xml "$UI" >/dev/null; }
tap_desc() {
  python3 - "$1" "$UI" <<'PY'
import re, sys, subprocess
needle, path = sys.argv[1], sys.argv[2]
t = open(path).read()
for m in re.finditer(r'content-desc="([^"]*)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', t):
  if needle.lower() in m.group(1).replace("&#10;"," ").lower():
    x,y = (int(m.group(2))+int(m.group(4)))//2, (int(m.group(3))+int(m.group(5)))//2
    subprocess.check_call(["adb","-s",sys.argv[3],"shell","input","tap",str(x),str(y)])
    raise SystemExit(0)
raise SystemExit(1)
PY
}

# Auth
dump
tap_desc "Send code" "$DEVICE" || tap_desc "Send verification" "$DEVICE" || true
sleep 1
adb -s "$DEVICE" shell input tap 540 1365
adb -s "$DEVICE" shell input text "923012345678"
sleep 1
dump && tap_desc "Send code" "$DEVICE" || tap_desc "Send verification" "$DEVICE"
sleep 4
adb -s "$DEVICE" shell input text "123456"
sleep 3
dump

# Open ride / pricing
tap_desc "Where are you headed" "$DEVICE" || tap_desc "City rides" "$DEVICE" || tap_desc "Easy" "$DEVICE" || true
sleep 2
dump && tap_desc "Easy" "$DEVICE" || true
sleep 8
dump

PID=$(adb -s "$DEVICE" shell pidof "$PKG" | tr -d '\r')
adb -s "$DEVICE" logcat -d --pid="$PID" -v time >"$LOG" 2>&1 || true

echo "MARKER=$MARK"
rg -i "appcheck|playintegrity|integrity|app_check|LocalRequestInterceptor" "$LOG" | tail -20 || echo "no_appcheck_lines"
rg -i "PKR|fare|km" "$UI" | head -5 || true
