#!/usr/bin/env bash
# Ora anywhere-testing tunnels — keeps 3 bore tunnels alive.
#   bore.pub:9099  -> local auth emulator   :9099   (fixed port required by app)
#   bore.pub:9000  -> local RTDB emulator   :9000   (fixed port required by app)
#   bore.pub:21918 -> local backend API     :8080   (port baked into the APK)
# If 9099/9000/21918 are ever taken by another bore.pub user while a tunnel is
# down, the APK breaks — rerun: ./mobile/scripts/build_local_device_apk.sh with
# ORA_API_DEVICE_URL=http://bore.pub:<new-api-port>/v1
set -uo pipefail
LOG=/tmp/ora_tunnels_keepalive.log

keep() { # keep <local_port> <remote_port>
  local lp="$1" rp="$2"
  while true; do
    if ! pgrep -f "bore local ${lp} --to bore.pub --port ${rp}" >/dev/null 2>&1; then
      echo "$(date -u +%FT%TZ) restarting ${lp}->bore.pub:${rp}" >>"$LOG"
      bore local "$lp" --to bore.pub --port "$rp" >>"$LOG" 2>&1 &
    fi
    sleep 20
  done
}

keep 9199 9099 &
keep 9000 9000 &
keep 8080 21918 &
keep 8899 8899 &
wait
