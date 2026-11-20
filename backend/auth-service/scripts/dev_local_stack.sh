#!/usr/bin/env bash
# One-shot zero-cloud local stack: Firebase emulators + auth-service + ticks.
# Everything runs in this shell; Ctrl-C tears all three down together.
#
#   ./scripts/dev_local_stack.sh            # start stack (firestore GEO, prod parity)
#   GEO_BACKEND=rtdb ./scripts/dev_local_stack.sh   # legacy rtdb geohash path
#   ORA_SEED=1 ./scripts/dev_local_stack.sh # also seed emulator test accounts
#
# Prereq: `firebase` CLI on PATH (`npm i -g firebase-tools`), Java for emulators.
# No cloud calls: backend refuses to boot without emulator env, FCM is a noop,
# routing is haversine, and cloud keys are stripped by dev_emulator_backend.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"             # backend/auth-service
REPO="$(cd "$ROOT/../.." && pwd)"                    # repo root (firebase.json)
PORT="${PORT:-8080}"
export GEO_BACKEND="${GEO_BACKEND:-firestore}"       # prod parity
export ORA_ENV=development
# Local-emulator exception — instant driver approval for dev/E2E flows.
export DRIVER_AUTO_APPROVE="${DRIVER_AUTO_APPROVE:-true}"

EMU_PID=""
BACKEND_PID=""
TICKS_PID=""

cleanup() {
  trap - INT TERM EXIT
  echo "Stopping local stack..."
  # SIGINT to firebase first — its own shutdown stops the java emulator
  # children. Then the wrapper pids, then any port stragglers as backstop.
  kill -INT "$EMU_PID" 2>/dev/null || true
  kill "$TICKS_PID" "$BACKEND_PID" 2>/dev/null || true
  for _ in $(seq 1 10); do
    lsof -nP -iTCP:8181 -iTCP:9099 -iTCP:9000 -iTCP:"$PORT" -sTCP:LISTEN \
      >/dev/null 2>&1 || break
    sleep 1
  done
  lsof -nP -tiTCP:8181 -tiTCP:9099 -tiTCP:9000 -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null \
    | xargs kill 2>/dev/null || true
}
trap cleanup INT TERM EXIT

command -v firebase >/dev/null || {
  echo "ERROR: firebase CLI not found — npm i -g firebase-tools" >&2; exit 2; }

# Fail fast on stale emulators/backend holding our ports — a healthy
# healthz/8181 check would silently validate the WRONG process otherwise.
STALE=""
for p in 8181 9099 9000 "$PORT"; do
  if lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1; then
    STALE="$STALE $p"
  fi
done
if [[ -n "$STALE" ]]; then
  echo "ERROR: ports already in use:$STALE — stale emulator/backend?" >&2
  echo "  inspect: lsof -nP -iTCP:8181 -iTCP:9099 -iTCP:9000 -iTCP:$PORT -sTCP:LISTEN" >&2
  exit 2
fi

echo "[1/3] Firebase emulators (auth:9099 firestore:8181 rtdb:9000)"
(cd "$REPO" && firebase emulators:start --project "${FIREBASE_PROJECT_ID:-oraapp-a9be5}") &
EMU_PID=$!

# Wait for the Firestore emulator port to accept connections.
echo "      waiting for firestore :8181 ..."
for _ in $(seq 1 60); do
  (echo > /dev/tcp/127.0.0.1/8181) >/dev/null 2>&1 && break
  sleep 1
done
(echo > /dev/tcp/127.0.0.1/8181) >/dev/null 2>&1 || {
  echo "ERROR: firestore emulator did not start on :8181" >&2; exit 2; }

echo "[2/3] auth-service :$PORT (GEO_BACKEND=$GEO_BACKEND, emulator-only)"
(cd "$ROOT" && PORT="$PORT" ./scripts/dev_emulator_backend.sh) &
BACKEND_PID=$!

echo "      waiting for /healthz ..."
for _ in $(seq 1 30); do
  curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1 || {
  echo "ERROR: auth-service did not become healthy on :$PORT" >&2; exit 2; }

if [[ "${ORA_SEED:-0}" == "1" ]]; then
  echo "      seeding emulator test accounts ..."
  (cd "$ROOT" && ./node_modules/.bin/tsx scripts/seed_device_test_accounts.ts) || true
fi

echo "[3/3] local ticks (dispatch/expiry sweeps — Cloud Tasks replacement)"
(cd "$ROOT" && PORT="$PORT" ./scripts/dev_local_ticks.sh) &
TICKS_PID=$!

LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || echo '<mac-ip>')"
cat <<EOF

LOCAL STACK UP — zero cloud cost
  Backend:   http://${LAN_IP}:${PORT}/v1   (devices on same Wi-Fi)
  Health:    curl http://127.0.0.1:${PORT}/healthz
  Build APK: mobile/scripts/build_local_device_apk.sh
  OTP:       enter 000000 in the app — auto-fetches emulator code
  Stop:      Ctrl-C in this terminal (foreground), or
             kill <stack-pid>   (TERM — note: SIGINT is ignored when the
             script itself was launched with '&', POSIX semantics)
EOF

wait
