#!/usr/bin/env bash
# USB phones → Mac auth-service (:8080). APK / debug uses http://127.0.0.1:8081/v1 on device.
set -euo pipefail

MAC_PORT="${PORT:-8080}"
DEVICE_PORT="${ORA_DEVICE_API_PORT:-8081}"

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
  echo "$s  tcp:${DEVICE_PORT} → tcp:${MAC_PORT}"
done

echo "Device API base: http://127.0.0.1:${DEVICE_PORT}/v1"
echo "Mac health:      curl http://127.0.0.1:${MAC_PORT}/healthz"
