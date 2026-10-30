#!/usr/bin/env bash
# USB phones → Mac auth-service + Firebase emulators.
# APK / debug uses http://127.0.0.1:8081/v1 on device; Firebase emulators are
# reached at 127.0.0.1:9099 (Auth) and 127.0.0.1:9000 (RTDB) on the device.
set -euo pipefail

MAC_PORT="${PORT:-8080}"
DEVICE_PORT="${ORA_DEVICE_API_PORT:-8081}"
AUTH_PORT="${ORA_AUTH_EMULATOR_PORT:-9099}"
RTDB_PORT="${ORA_RTDB_EMULATOR_PORT:-9000}"

SERIALS=()
while IFS= read -r line; do
  SERIALS+=("$line")
done < <(adb devices | awk 'NR>1 && $2=="device" {print $1}')

if [[ ${#SERIALS[@]} -eq 0 ]]; then
  echo "No adb devices in 'device' state. Plug in phone(s) and accept USB debugging." >&2
  exit 1
fi

for s in "${SERIALS[@]}"; do
  adb -s "$s" reverse "tcp:${DEVICE_PORT}" "tcp:${MAC_PORT}"
  adb -s "$s" reverse "tcp:${AUTH_PORT}" "tcp:${AUTH_PORT}"
  adb -s "$s" reverse "tcp:${RTDB_PORT}" "tcp:${RTDB_PORT}"
  echo "$s  api tcp:${DEVICE_PORT} → tcp:${MAC_PORT}, auth tcp:${AUTH_PORT}, rtdb tcp:${RTDB_PORT}"
done

echo "Device API base:        http://127.0.0.1:${DEVICE_PORT}/v1"
echo "Device auth emulator:   127.0.0.1:${AUTH_PORT} (dart-define ORA_FIREBASE_EMULATOR_HOST=127.0.0.1)"
echo "Device rtdb emulator:   127.0.0.1:${RTDB_PORT}"
echo "Mac health:             curl http://127.0.0.1:${MAC_PORT}/healthz"
