#!/usr/bin/env bash
# Local auth-service for Flutter / APK on physical devices — start once, keep running.
#
# Usage:
#   ./scripts/dev_backend.sh start          # background daemon (idempotent)
#   ./scripts/dev_backend.sh stop
#   ./scripts/dev_backend.sh restart
#   ./scripts/dev_backend.sh status
#   ./scripts/dev_backend.sh logs           # tail log file
#   ./scripts/dev_backend.sh install        # macOS LaunchAgent (survives reboot)
#   ./scripts/dev_backend.sh uninstall
#
# Phone API URL (debug APK / flutter run): http://127.0.0.1:8081/v1
# Mac listens on :8080 — run ./scripts/dev_adb_reverse.sh after USB connect.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LOCAL_DIR="$ROOT/.local"
PID_FILE="$LOCAL_DIR/dev-backend.pid"
LOG_FILE="$LOCAL_DIR/dev-backend.log"
ENTRY="$ROOT/scripts/launchd_entry.sh"
PLIST_LABEL="com.ora.auth-service.dev"
PLIST_PATH="${HOME}/Library/LaunchAgents/${PLIST_LABEL}.plist"

PORT="${PORT:-8080}"
HEALTH_URL="http://127.0.0.1:${PORT}/healthz"

mkdir -p "$LOCAL_DIR"

health_ok() {
  curl -fsS -m 2 "$HEALTH_URL" >/dev/null 2>&1
}

read_pid() {
  if [[ -f "$PID_FILE" ]]; then
    cat "$PID_FILE"
  fi
}

pid_alive() {
  local pid="${1:-}"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

port_listener_pid() {
  lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | head -1
}

cmd_start() {
  if health_ok; then
    echo "auth-service already up at :$PORT ($HEALTH_URL)"
    return 0
  fi

  local old_pid
  old_pid="$(read_pid || true)"
  if pid_alive "$old_pid"; then
    echo "Stopping stale pid $old_pid (health check failed)…"
    kill "$old_pid" 2>/dev/null || true
    sleep 1
  fi

  local other
  other="$(port_listener_pid || true)"
  if [[ -n "$other" ]]; then
    echo "Port $PORT in use by pid $other (not our health check). Stop it or set PORT." >&2
    exit 1
  fi

  if [[ ! -x "$ENTRY" ]]; then
    chmod +x "$ENTRY"
  fi

  echo "Starting auth-service on :$PORT → log: $LOG_FILE"
  nohup "$ENTRY" >>"$LOG_FILE" 2>&1 &
  echo $! >"$PID_FILE"
  sleep 2

  if health_ok; then
    echo "OK: $HEALTH_URL"
    echo "Next (each USB session): cd $ROOT && ./scripts/dev_adb_reverse.sh"
  else
    echo "Start failed. Last log lines:" >&2
    tail -20 "$LOG_FILE" >&2 || true
    exit 1
  fi
}

cmd_stop() {
  local pid kill_pid
  pid="$(read_pid || true)"
  kill_pid="$pid"
  if ! pid_alive "$kill_pid"; then
    kill_pid="$(port_listener_pid || true)"
  fi
  if [[ -n "$kill_pid" ]] && pid_alive "$kill_pid"; then
    kill "$kill_pid" 2>/dev/null || true
    sleep 1
    echo "Stopped pid $kill_pid"
  else
    echo "No dev-backend process found on :$PORT"
  fi
  rm -f "$PID_FILE"
}

cmd_status() {
  if health_ok; then
    echo "UP   $HEALTH_URL"
    local lp
    lp="$(port_listener_pid || true)"
    [[ -n "$lp" ]] && echo "PID  $lp"
  else
    echo "DOWN $HEALTH_URL"
    exit 1
  fi
}

cmd_logs() {
  touch "$LOG_FILE"
  exec tail -f "$LOG_FILE"
}

write_plist() {
  mkdir -p "${HOME}/Library/LaunchAgents"
  cat >"$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${PLIST_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${ENTRY}</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${ROOT}</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${LOG_FILE}</string>
  <key>StandardErrorPath</key>
  <string>${LOG_FILE}</string>
</dict>
</plist>
EOF
  chmod +x "$ENTRY"
  echo "Wrote $PLIST_PATH"
}

cmd_install() {
  write_plist
  launchctl bootout "gui/$(id -u)/${PLIST_LABEL}" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
  launchctl enable "gui/$(id -u)/${PLIST_LABEL}"
  sleep 2
  if health_ok; then
    echo "LaunchAgent installed and auth-service is UP."
  else
    echo "LaunchAgent loaded; waiting for health…" >&2
    sleep 3
    cmd_status || true
  fi
  echo "Logs: $LOG_FILE"
  echo "Uninstall: ./scripts/dev_backend.sh uninstall"
}

cmd_uninstall() {
  launchctl bootout "gui/$(id -u)/${PLIST_LABEL}" 2>/dev/null || true
  rm -f "$PLIST_PATH"
  cmd_stop || true
  echo "LaunchAgent removed."
}

case "${1:-start}" in
  start) cmd_start ;;
  stop) cmd_stop ;;
  restart) cmd_stop; cmd_start ;;
  status) cmd_status ;;
  logs) cmd_logs ;;
  install) cmd_install ;;
  uninstall) cmd_uninstall ;;
  *)
    echo "Usage: $0 {start|stop|restart|status|logs|install|uninstall}" >&2
    exit 1
    ;;
esac
